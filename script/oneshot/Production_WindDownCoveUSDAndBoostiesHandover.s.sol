// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";

interface IBasketManager {
    function setManagementFee(address basket, uint16 managementFeeBps) external;
    function managementFee(address basket) external view returns (uint16);
}

interface IFeeCollector {
    function claimTreasuryFee(address basketToken) external;
    function claimSponsorFee(address basketToken) external;
    function basketTokenSponsors(address basketToken) external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IAccessControlEnumerable {
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface ICurveTwoAssetPoolWithBalances {
    function coins(uint256 arg0) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function remove_liquidity(uint256 _burnAmount, uint256[] memory _minAmounts) external returns (uint256[] memory);
}

interface IYearnStakingDelegate {
    function setTreasury(address treasury_) external;
    function treasury() external view returns (address);
}

/// @title Production_WindDownCoveUSDAndBoostiesHandover
/// @notice One-shot Safe batch to wind down coveUSD active management and hand over boosties YSD controls.
/// @dev Actions queued by this script:
/// 1. Schedule BasketManager management fee update to 0 bps via timelock.
/// 2. Revoke BasketManager REBALANCE_PROPOSER_ROLE, TOKENSWAP_PROPOSER_ROLE, and TOKENSWAP_EXECUTOR_ROLE.
/// 3. Claim pending protocol fees from FeeCollector (treasury fee and sponsor fee when authorized).
/// 4. Withdraw coveYFI/YFI Curve LP held by the Safe via balanced remove_liquidity.
/// 5. Hand over YearnStakingDelegate controls to ychad.eth:
///    DEFAULT_ADMIN_ROLE and PAUSER_ROLE immediate handover/revokes, then timelocked TIMELOCK_ROLE + treasury transfer.
contract ProductionWindDownCoveUSDAndBoostiesHandover is DeployScript, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    string internal constant _BASKET_TOKEN_SYMBOL = "USD";
    uint16 internal constant _ZERO_MANAGEMENT_FEE_BPS = 0;
    uint256 internal constant _LP_WITHDRAW_HAIRCUT_BPS = 500;

    address internal constant _BOOSTIES_YSD = 0x05dcdBF02F29239D1f8d9797E22589A2DE1C152F;
    address internal constant _COVEYFI_YFI_CURVE_POOL = 0xa3f152837492340dAAf201F4dFeC6cD73A8a9760;
    address internal constant _COVEYFI = 0xFf71841EeFca78a64421db28060855036765c248;
    address internal constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant _YCHAD = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    bytes32 internal constant _REBALANCE_PROPOSER_ROLE = keccak256("REBALANCE_PROPOSER_ROLE");
    bytes32 internal constant _TOKENSWAP_PROPOSER_ROLE = keccak256("TOKENSWAP_PROPOSER_ROLE");
    bytes32 internal constant _TOKENSWAP_EXECUTOR_ROLE = keccak256("TOKENSWAP_EXECUTOR_ROLE");
    bytes32 internal constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant _TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    bytes32 internal constant _BASKET_FEE_ZERO_SALT = keccak256("Production_WindDown_BasketFeeZero_v1");
    bytes32 internal constant _YSD_HANDOVER_SALT = keccak256("Production_WindDown_YSDHandover_v1");

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _safe() internal pure returns (address) {
        return COVE_COMMUNITY_MULTISIG;
    }

    /// @notice Build and execute the one-shot Safe batch.
    /// @dev Ordered action list:
    /// 1. Queue timelocked BasketManager management fee change to 0 bps.
    /// 2. Queue BasketManager proposer/executor role revocations.
    /// 3. Queue protocol fee claims from FeeCollector.
    /// 4. Queue balanced coveYFI/YFI Curve LP withdrawal.
    /// 5. Queue immediate YSD DEFAULT_ADMIN_ROLE/PAUSER_ROLE handover and revokes.
    /// 6. Queue timelocked YSD TIMELOCK_ROLE + treasury handover.
    function deploy() public isBatch(_safe()) {
        deployer.setAutoBroadcast(true);

        address basketManager = deployer.getAddress(buildBasketManagerName());
        address feeCollector = deployer.getAddress(buildFeeCollectorName());
        address basketToken = deployer.getAddress(buildBasketTokenName(_BASKET_TOKEN_SYMBOL));
        address timelock = deployer.getAddress(buildTimelockControllerName());

        uint256 delay = TimelockController(payable(timelock)).getMinDelay();

        _queueManagementFeeToZero(timelock, delay, basketManager, basketToken);
        _queueBasketManagerRoleRevokes(basketManager);
        _queueFeeClaims(feeCollector, basketToken);
        _queueBalancedCoveYfiYfiLpWithdraw();

        _queueYsdImmediateHandover(_BOOSTIES_YSD);
        _queueYsdTimelockHandover(timelock, delay, _BOOSTIES_YSD);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            executeBatch(true);
        } else {
            executeBatch(false);
        }
    }

    /// @notice Fork-only helper to fully simulate schedule + timelock execution in one run.
    function dryRunWithTimelockExecution() public {
        deploy();

        address timelock = deployer.getAddress(buildTimelockControllerName());
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();
        vm.warp(block.timestamp + delay + 1);

        executeBasketFeeTimelock();
        executeYsdHandoverTimelock();
    }

    /// @notice Executes the scheduled basket-fee timelock operation.
    function executeBasketFeeTimelock() public {
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address basketToken = deployer.getAddress(buildBasketTokenName(_BASKET_TOKEN_SYMBOL));
        address timelock = deployer.getAddress(buildTimelockControllerName());

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildBasketFeeZeroBatch(basketManager, basketToken);

        _executeTimelockBatch(timelock, targets, values, payloads, _BASKET_FEE_ZERO_SALT);

        require(
            IBasketManager(basketManager).managementFee(basketToken) == _ZERO_MANAGEMENT_FEE_BPS,
            "Basket fee not set to 0"
        );
    }

    /// @notice Executes the scheduled YSD timelock/treasury handover operation.
    function executeYsdHandoverTimelock() public {
        address timelock = deployer.getAddress(buildTimelockControllerName());
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildYsdTimelockHandoverBatch(timelock, _BOOSTIES_YSD);

        require(targets.length > 0, "No YSD timelock ops to execute");
        _executeTimelockBatch(timelock, targets, values, payloads, _YSD_HANDOVER_SALT);

        require(IAccessControlEnumerable(_BOOSTIES_YSD).hasRole(_TIMELOCK_ROLE, _YCHAD), "YCHAD missing TIMELOCK_ROLE");
        require(IYearnStakingDelegate(_BOOSTIES_YSD).treasury() == _YCHAD, "YSD treasury not handed over");
    }

    function _queueManagementFeeToZero(
        address timelock,
        uint256 delay,
        address basketManager,
        address basketToken
    )
        internal
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildBasketFeeZeroBatch(basketManager, basketToken);

        addToBatch(
            timelock,
            0,
            abi.encodeCall(
                TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), _BASKET_FEE_ZERO_SALT, delay)
            )
        );
    }

    function _buildBasketFeeZeroBatch(
        address basketManager,
        address basketToken
    )
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](1);
        values = new uint256[](1);
        payloads = new bytes[](1);
        targets[0] = basketManager;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IBasketManager.setManagementFee, (basketToken, _ZERO_MANAGEMENT_FEE_BPS));
    }

    function _queueBasketManagerRoleRevokes(address basketManager) internal {
        _queueRoleRevokes(basketManager, _REBALANCE_PROPOSER_ROLE);
        _queueRoleRevokes(basketManager, _TOKENSWAP_PROPOSER_ROLE);
        _queueRoleRevokes(basketManager, _TOKENSWAP_EXECUTOR_ROLE);
    }

    function _queueRoleRevokes(address target, bytes32 role) internal {
        address[] memory members = _getRoleMembers(target, role);
        for (uint256 i; i < members.length; ++i) {
            addToBatch(target, 0, abi.encodeCall(IAccessControlEnumerable.revokeRole, (role, members[i])));
        }
    }

    function _queueFeeClaims(address feeCollector, address basketToken) internal {
        addToBatch(feeCollector, 0, abi.encodeCall(IFeeCollector.claimTreasuryFee, (basketToken)));

        address sponsor = IFeeCollector(feeCollector).basketTokenSponsors(basketToken);
        bool safeIsAdmin = IFeeCollector(feeCollector).hasRole(DEFAULT_ADMIN_ROLE, _safe());
        if (sponsor == _safe() || safeIsAdmin) {
            addToBatch(feeCollector, 0, abi.encodeCall(IFeeCollector.claimSponsorFee, (basketToken)));
        }
    }

    function _queueBalancedCoveYfiYfiLpWithdraw() internal {
        uint256 lpBalance = IERC20(_COVEYFI_YFI_CURVE_POOL).balanceOf(_safe());
        if (lpBalance == 0) {
            return;
        }

        ICurveTwoAssetPoolWithBalances pool = ICurveTwoAssetPoolWithBalances(_COVEYFI_YFI_CURVE_POOL);
        address coin0 = pool.coins(0);
        address coin1 = pool.coins(1);
        require(
            (coin0 == _COVEYFI && coin1 == _YFI) || (coin0 == _YFI && coin1 == _COVEYFI),
            "Unexpected coveYFI/YFI pool coins"
        );

        uint256 totalSupply = IERC20(_COVEYFI_YFI_CURVE_POOL).totalSupply();
        require(totalSupply != 0, "Pool supply is zero");

        uint256 expectedAmount0 = (lpBalance * pool.balances(0)) / totalSupply;
        uint256 expectedAmount1 = (lpBalance * pool.balances(1)) / totalSupply;

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = _applyHaircut(expectedAmount0, _LP_WITHDRAW_HAIRCUT_BPS);
        minAmounts[1] = _applyHaircut(expectedAmount1, _LP_WITHDRAW_HAIRCUT_BPS);

        addToBatch(
            _COVEYFI_YFI_CURVE_POOL,
            0,
            abi.encodeCall(ICurveTwoAssetPoolWithBalances.remove_liquidity, (lpBalance, minAmounts))
        );
    }

    function _queueYsdImmediateHandover(address ysd) internal {
        IAccessControlEnumerable ysdAccess = IAccessControlEnumerable(ysd);
        address safe = _safe();

        bool grantDefaultAdmin = !ysdAccess.hasRole(DEFAULT_ADMIN_ROLE, _YCHAD);
        bool grantPauser = !ysdAccess.hasRole(_PAUSER_ROLE, _YCHAD);

        address[] memory pausers = _getRoleMembers(ysd, _PAUSER_ROLE);
        address[] memory defaultAdmins = _getRoleMembers(ysd, DEFAULT_ADMIN_ROLE);

        uint256 pauserRevokes;
        for (uint256 i; i < pausers.length; ++i) {
            if (pausers[i] != _YCHAD) {
                ++pauserRevokes;
            }
        }

        bool revokeSafeDefaultAdmin;
        uint256 defaultAdminRevokesExceptSafe;
        for (uint256 i; i < defaultAdmins.length; ++i) {
            address admin = defaultAdmins[i];
            if (admin == _YCHAD) {
                continue;
            }
            if (admin == safe) {
                revokeSafeDefaultAdmin = true;
            } else {
                ++defaultAdminRevokesExceptSafe;
            }
        }

        uint256 txCount = (grantDefaultAdmin ? 1 : 0) + (grantPauser ? 1 : 0) + pauserRevokes
            + defaultAdminRevokesExceptSafe + (revokeSafeDefaultAdmin ? 1 : 0);
        if (txCount == 0) {
            return;
        }

        require(ysdAccess.hasRole(DEFAULT_ADMIN_ROLE, safe), "Safe not YSD admin");

        if (grantDefaultAdmin) {
            addToBatch(ysd, 0, abi.encodeCall(IAccessControlEnumerable.grantRole, (DEFAULT_ADMIN_ROLE, _YCHAD)));
        }

        if (grantPauser) {
            addToBatch(ysd, 0, abi.encodeCall(IAccessControlEnumerable.grantRole, (_PAUSER_ROLE, _YCHAD)));
        }

        for (uint256 i; i < pausers.length; ++i) {
            address pauser = pausers[i];
            if (pauser == _YCHAD) {
                continue;
            }
            addToBatch(ysd, 0, abi.encodeCall(IAccessControlEnumerable.revokeRole, (_PAUSER_ROLE, pauser)));
        }

        for (uint256 i; i < defaultAdmins.length; ++i) {
            address admin = defaultAdmins[i];
            if (admin == _YCHAD || admin == safe) {
                continue;
            }
            addToBatch(ysd, 0, abi.encodeCall(IAccessControlEnumerable.revokeRole, (DEFAULT_ADMIN_ROLE, admin)));
        }

        if (revokeSafeDefaultAdmin) {
            // Keep Safe admin privilege until all prior YSD role updates are queued.
            addToBatch(ysd, 0, abi.encodeCall(IAccessControlEnumerable.revokeRole, (DEFAULT_ADMIN_ROLE, safe)));
        }
    }

    function _queueYsdTimelockHandover(address timelock, uint256 delay, address ysd) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildYsdTimelockHandoverBatch(timelock, ysd);
        if (targets.length == 0) {
            return;
        }

        addToBatch(
            timelock,
            0,
            abi.encodeCall(
                TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), _YSD_HANDOVER_SALT, delay)
            )
        );
    }

    function _buildYsdTimelockHandoverBatch(
        address timelock,
        address ysd
    )
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        IAccessControlEnumerable ysdAccess = IAccessControlEnumerable(ysd);

        bool grantTimelockRole = !ysdAccess.hasRole(_TIMELOCK_ROLE, _YCHAD);
        bool setTreasuryToYchad = IYearnStakingDelegate(ysd).treasury() != _YCHAD;

        address[] memory timelockMembers = _getRoleMembers(ysd, _TIMELOCK_ROLE);
        bool revokeTimelockAtEnd;
        uint256 timelockRevokesExceptTimelock;
        for (uint256 i; i < timelockMembers.length; ++i) {
            address member = timelockMembers[i];
            if (member == _YCHAD) {
                continue;
            }
            if (member == timelock) {
                revokeTimelockAtEnd = true;
            } else {
                ++timelockRevokesExceptTimelock;
            }
        }

        uint256 txCount = (grantTimelockRole ? 1 : 0) + (setTreasuryToYchad ? 1 : 0) + timelockRevokesExceptTimelock
            + (revokeTimelockAtEnd ? 1 : 0);
        if (txCount == 0) {
            return (new address[](0), new uint256[](0), new bytes[](0));
        }

        targets = new address[](txCount);
        values = new uint256[](txCount);
        payloads = new bytes[](txCount);

        uint256 index;

        if (grantTimelockRole) {
            targets[index] = ysd;
            values[index] = 0;
            payloads[index] = abi.encodeCall(IAccessControlEnumerable.grantRole, (_TIMELOCK_ROLE, _YCHAD));
            ++index;
        }

        if (setTreasuryToYchad) {
            targets[index] = ysd;
            values[index] = 0;
            payloads[index] = abi.encodeCall(IYearnStakingDelegate.setTreasury, (_YCHAD));
            ++index;
        }

        for (uint256 i; i < timelockMembers.length; ++i) {
            address member = timelockMembers[i];
            if (member == _YCHAD || member == timelock) {
                continue;
            }
            targets[index] = ysd;
            values[index] = 0;
            payloads[index] = abi.encodeCall(IAccessControlEnumerable.revokeRole, (_TIMELOCK_ROLE, member));
            ++index;
        }

        if (revokeTimelockAtEnd) {
            // Revoke the executing timelock role holder last so previous calls still pass access checks.
            targets[index] = ysd;
            values[index] = 0;
            payloads[index] = abi.encodeCall(IAccessControlEnumerable.revokeRole, (_TIMELOCK_ROLE, timelock));
            ++index;
        }

        require(index == txCount, "Invalid YSD timelock tx count");
    }

    function _executeTimelockBatch(
        address timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 salt
    )
        internal
    {
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            vm.broadcast();
            TimelockController(payable(timelock)).executeBatch(targets, values, payloads, bytes32(0), salt);
        } else {
            vm.prank(COVE_DEPLOYER_ADDRESS);
            TimelockController(payable(timelock)).executeBatch(targets, values, payloads, bytes32(0), salt);
        }
    }

    function _getRoleMembers(address target, bytes32 role) internal view returns (address[] memory members) {
        uint256 count = IAccessControlEnumerable(target).getRoleMemberCount(role);
        members = new address[](count);
        for (uint256 i; i < count; ++i) {
            members[i] = IAccessControlEnumerable(target).getRoleMember(role, i);
        }
    }

    function _applyHaircut(uint256 amount, uint256 haircutBps) internal pure returns (uint256) {
        require(haircutBps <= 10_000, "Invalid haircut bps");
        return (amount * (10_000 - haircutBps)) / 10_000;
    }
}

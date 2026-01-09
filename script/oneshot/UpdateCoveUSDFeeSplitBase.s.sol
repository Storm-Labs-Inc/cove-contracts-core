// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { Constants } from "test/utils/Constants.t.sol";

interface IBasketManager {
    function setManagementFee(address basket, uint16 managementFeeBps) external;
    function managementFee(address basket) external view returns (uint16);
}

interface IFeeCollector {
    function setSponsorSplit(address basketToken, uint16 sponsorSplit) external;
    function basketTokenSponsorSplits(address basketToken) external view returns (uint16);
}

abstract contract UpdateCoveUSDFeeSplitBase is
    DeployScript,
    Constants,
    StdAssertions,
    BatchScript,
    BuildDeploymentJsonNames
{
    using DeployerFunctions for Deployer;

    uint16 public constant NEW_MANAGEMENT_FEE_BPS = 80; // 0.80%
    uint16 public constant NEW_SPONSOR_SPLIT_BPS = 3750; // 37.5% of 0.80% = 0.30%

    string internal constant _BASKET_TOKEN_SYMBOL = "USD";

    function _safe() internal view virtual returns (address);

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function deploy() public isBatch(_safe()) {
        deployer.setAutoBroadcast(true);

        address basketManager = deployer.getAddress(buildBasketManagerName());
        address feeCollector = deployer.getAddress(buildFeeCollectorName());
        address basketToken = deployer.getAddress(buildBasketTokenName(_BASKET_TOKEN_SYMBOL));
        address timelock = deployer.getAddress(buildTimelockControllerName());

        TimelockController timelockController = TimelockController(payable(timelock));
        uint256 delay = timelockController.getMinDelay();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);

        targets[0] = basketManager;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IBasketManager.setManagementFee, (basketToken, NEW_MANAGEMENT_FEE_BPS));

        addToBatch(feeCollector, 0, abi.encodeCall(IFeeCollector.setSponsorSplit, (basketToken, NEW_SPONSOR_SPLIT_BPS)));

        addToBatch(
            timelock,
            0,
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), bytes32(0), delay))
        );

        // ============================= TESTING (fork only) =============================
        vm.prank(_safe());
        IFeeCollector(feeCollector).setSponsorSplit(basketToken, NEW_SPONSOR_SPLIT_BPS);

        vm.prank(_safe());
        timelockController.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), delay);

        vm.warp(block.timestamp + delay);
        vm.prank(COVE_DEPLOYER_ADDRESS);
        timelockController.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));

        assertEq(
            IBasketManager(basketManager).managementFee(basketToken),
            NEW_MANAGEMENT_FEE_BPS,
            "management fee not updated"
        );
        assertEq(
            IFeeCollector(feeCollector).basketTokenSponsorSplits(basketToken),
            NEW_SPONSOR_SPLIT_BPS,
            "sponsor split not updated"
        );

        // if context is ScriptBroadcast (forge script ... --broadcast),
        // actually execute the batch
        // otherwise, just simulate the batch
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            executeBatch(true);
        } else {
            executeBatch(false);
        }
    }
}

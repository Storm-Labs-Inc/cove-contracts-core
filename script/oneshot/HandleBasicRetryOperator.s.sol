// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";

import { BasketToken } from "src/BasketToken.sol";
import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);
}

contract HandleBasicRetryOperator is DeployScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserStatus {
        address user;
        uint256 claimableDeposits;
        uint256 fallbackAssets;
        uint256 claimableRedeems;
        uint256 fallbackShares;
    }

    // Multicall that lives on most EVM chains, including Ethereum mainnet.
    address internal constant _MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    // ~6 months of blocks assuming ~12s block time: 6 * 30 days * 24h * 3600s / 12s ≈ 1.296M
    uint256 internal constant _LOOKBACK_BLOCKS_DEFAULT = 1_296_000;
    // Batch size for log queries; keep within RPC limits.
    uint256 internal constant _LOG_STEP_DEFAULT = 10_000;

    mapping(address => bool) internal _latestApproval;
    EnumerableSet.AddressSet internal _controllers;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function deploy() public {
        string memory operatorKey = vm.envOr("BASIC_RETRY_OPERATOR_KEY", _buildOperatorKey());
        string memory basketTokenKey = vm.envOr("BASKET_TOKEN_KEY", _buildBasketTokenKey());

        address operatorAddress = vm.envOr("BASIC_RETRY_OPERATOR", deployer.getAddress(operatorKey));
        require(operatorAddress != address(0), "BasicRetryOperator not found");

        address basketTokenAddress = vm.envOr("BASKET_TOKEN", deployer.getAddress(basketTokenKey));
        require(basketTokenAddress != address(0), "BasketToken not found");

        BasketToken basketToken = BasketToken(basketTokenAddress);

        uint256 lookbackBlocks = vm.envOr("LOOKBACK_BLOCKS", _LOOKBACK_BLOCKS_DEFAULT);
        uint256 logStep = vm.envOr("LOG_STEP", _LOG_STEP_DEFAULT);
        if (logStep == 0) {
            logStep = _LOG_STEP_DEFAULT;
        }

        uint256 currentBlock = block.number;
        if (lookbackBlocks > currentBlock) {
            lookbackBlocks = currentBlock;
        }
        uint256 fromBlock = currentBlock - lookbackBlocks;

        _scanOperatorApprovals(fromBlock, currentBlock, basketTokenAddress, operatorAddress, logStep);

        address[] memory allControllers = _controllers.values();
        uint256 controllerCount = allControllers.length;

        if (controllerCount == 0) {
            console.log("No OperatorSet events detected for the selected operator in the lookback window.");
            return;
        }

        UserStatus[] memory statuses = new UserStatus[](controllerCount);

        uint256 actionableUsers;
        uint256 multicallActions;

        console.log("\n=== HandleBasicRetryOperator Report ===");
        console.log("Operator address:");
        console.logAddress(operatorAddress);
        console.log("BasketToken address:");
        console.logAddress(basketTokenAddress);
        console.log("Scanning blocks:");
        console.logUint(fromBlock);
        console.log("to");
        console.logUint(currentBlock);
        console.log("Controllers discovered:");
        console.logUint(controllerCount);

        for (uint256 i = 0; i < controllerCount; ++i) {
            address user = allControllers[i];
            if (!_latestApproval[user]) {
                continue;
            }
            if (!basketToken.isOperator(user, operatorAddress)) {
                continue;
            }

            UserStatus memory status = _collectStatus(user, basketToken);
            if (!_needsAnyAction(status)) {
                continue;
            }

            statuses[actionableUsers] = status;
            ++actionableUsers;
            multicallActions += _needsDeposit(status) ? 1 : 0;
            multicallActions += _needsRedeem(status) ? 1 : 0;

            console.log("\nUser:");
            console.logAddress(status.user);
            if (status.claimableDeposits > 0) {
                console.log("  claimableDeposits");
                console.logUint(status.claimableDeposits);
            }
            if (status.fallbackAssets > 0) {
                console.log("  fallbackAssets");
                console.logUint(status.fallbackAssets);
            }
            if (status.claimableRedeems > 0) {
                console.log("  claimableRedeems");
                console.logUint(status.claimableRedeems);
            }
            if (status.fallbackShares > 0) {
                console.log("  fallbackShares");
                console.logUint(status.fallbackShares);
            }
        }

        if (actionableUsers == 0) {
            console.log("\nNo users require BasicRetryOperator handling at this time.");
            return;
        }

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](multicallActions);
        uint256 callIndex;

        for (uint256 i = 0; i < actionableUsers; ++i) {
            UserStatus memory status = statuses[i];
            if (_needsDeposit(status)) {
                calls[callIndex++] = IMulticall3.Call3({
                    target: operatorAddress,
                    allowFailure: false,
                    callData: abi.encodeWithSelector(
                        BasicRetryOperator.handleDeposit.selector, status.user, basketTokenAddress
                    )
                });
            }
            if (_needsRedeem(status)) {
                calls[callIndex++] = IMulticall3.Call3({
                    target: operatorAddress,
                    allowFailure: false,
                    callData: abi.encodeWithSelector(
                        BasicRetryOperator.handleRedeem.selector, status.user, basketTokenAddress
                    )
                });
            }
        }

        console.log("\nUsers needing action:");
        console.logUint(actionableUsers);
        console.log("Total BasicRetryOperator calls:");
        console.logUint(multicallActions);

        bytes memory aggregateCallData = abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls);
        console.log("\nMulticall3 target:");
        console.logAddress(_multicallAddress());
        console.log("aggregate3 calldata (hex):");
        console.logBytes(aggregateCallData);

        console.log("\nBroadcasting aggregate3 transaction...");
        vm.broadcast();
        IMulticall3(_multicallAddress()).aggregate3(calls);
    }

    function _buildOperatorKey() internal view returns (string memory) {
        return buildBasicRetryOperatorName();
    }

    function _buildBasketTokenKey() internal view returns (string memory) {
        return buildBasketTokenName("USD");
    }

    function _collectStatus(address user, BasketToken basketToken) internal view returns (UserStatus memory) {
        return UserStatus({
            user: user,
            claimableDeposits: basketToken.maxDeposit(user),
            fallbackAssets: basketToken.claimableFallbackAssets(user),
            claimableRedeems: basketToken.maxRedeem(user),
            fallbackShares: basketToken.claimableFallbackShares(user)
        });
    }

    function _needsAnyAction(UserStatus memory status) internal pure returns (bool) {
        return status.claimableDeposits > 0 || status.fallbackAssets > 0 || status.claimableRedeems > 0
            || status.fallbackShares > 0;
    }

    function _needsDeposit(UserStatus memory status) internal pure returns (bool) {
        return status.claimableDeposits > 0 || status.fallbackAssets > 0;
    }

    function _needsRedeem(UserStatus memory status) internal pure returns (bool) {
        return status.claimableRedeems > 0 || status.fallbackShares > 0;
    }

    function _scanOperatorApprovals(
        uint256 fromBlock,
        uint256 toBlock,
        address basketToken,
        address operator,
        uint256 step
    )
        internal
    {
        if (toBlock < fromBlock) {
            return;
        }

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = keccak256("OperatorSet(address,address,bool)");

        uint256 start = fromBlock;
        while (start <= toBlock) {
            uint256 end = start + step;
            if (end > toBlock) {
                end = toBlock;
            }

            Vm.EthGetLogs[] memory logs = vm.eth_getLogs(start, end, basketToken, topics);
            for (uint256 i = 0; i < logs.length; ++i) {
                Vm.EthGetLogs memory logEntry = logs[i];
                if (logEntry.topics.length < 3) {
                    continue;
                }

                address controller = address(uint160(uint256(logEntry.topics[1])));
                address loggedOperator = address(uint160(uint256(logEntry.topics[2])));
                if (loggedOperator != operator) {
                    continue;
                }

                bool approved = abi.decode(logEntry.data, (bool));
                _latestApproval[controller] = approved;

                _controllers.add(controller);
            }

            if (end == type(uint256).max) {
                break;
            }
            start = end + 1;
        }
    }

    function _multicallAddress() internal view returns (address) {
        return vm.envOr("MULTICALL_ADDRESS", _MULTICALL3);
    }
}

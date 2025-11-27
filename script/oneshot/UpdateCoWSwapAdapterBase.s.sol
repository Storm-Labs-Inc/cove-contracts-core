// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { console2 } from "forge-std/console2.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { VmSafe } from "forge-std/Vm.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { BasketManager } from "src/BasketManager.sol";
import { Constants } from "test/utils/Constants.t.sol";

/// @title UpdateCoWSwapAdapterBase
/// @notice Abstract base contract for deploying and updating the CoWSwap adapter with new appData hash.
/// @dev Subclasses must override `_safe()`, `_buildPrefix()`, and `_appDataHash()`.
///
/// Usage (via subclass):
///   1. Deploy new contracts:
///      forge script <SubclassScript> --sig "deploy()" --rpc-url $RPC_URL --broadcast
///   2. Schedule timelock (via Safe batch):
///      forge script <SubclassScript> --sig "scheduleTimelock()" --rpc-url $RPC_URL
///   3. Execute timelock (after delay):
///      forge script <SubclassScript> --sig "executeTimelock()" --rpc-url $RPC_URL --broadcast
abstract contract UpdateCoWSwapAdapterBase is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    string internal constant _IMPLEMENTATION_SUFFIX = "CoWSwapCloneImplementation_AppDataV2";
    string internal constant _ADAPTER_SUFFIX = "CowSwapAdapter_AppDataV2";

    /// @notice Returns the Safe multisig address for batch transactions.
    function _safe() internal view virtual returns (address);

    /// @notice Returns the appData hash for CoWSwap orders.
    function _appDataHash() internal view virtual returns (bytes32);

    /// @notice Deploys the new CoWSwapCloneWithAppData implementation and CoWSwapAdapter contracts.
    function deploy() public {
        deployer.setAutoBroadcast(true);

        address oldAdapter = deployer.getAddress(buildCowSwapAdapterName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        bytes32 appDataHash = _appDataHash();

        address newCloneImplementation = address(
            deployer.deploy_CoWSwapCloneWithAppData(string.concat(_buildPrefix(), _IMPLEMENTATION_SUFFIX), appDataHash)
        );

        address newAdapter = address(
            deployer.deploy_CoWSwapAdapter(string.concat(_buildPrefix(), _ADAPTER_SUFFIX), newCloneImplementation)
        );

        console2.log("=== CoWSwap Adapter Deployment ===");
        console2.log("Environment:", _buildPrefix());
        console2.log("BasketManager:", basketManager);
        console2.log("Previous adapter:", oldAdapter);
        console2.log("New clone implementation:", newCloneImplementation);
        console2.log("New adapter:", newAdapter);
        console2.log("appDataHash:");
        console2.logBytes32(appDataHash);
    }

    /// @notice Schedules the timelock transaction to replace the adapter via Safe batch.
    function scheduleTimelock() public isBatch(_safe()) {
        deployer.setAutoBroadcast(true);

        address timelock = deployer.getAddress(buildTimelockControllerName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address newAdapter = deployer.getAddress(string.concat(_buildPrefix(), _ADAPTER_SUFFIX));
        if (newAdapter == address(0)) {
            revert("New adapter deployment not found");
        }

        uint256 delay = TimelockController(payable(timelock)).getMinDelay();
        bytes memory calldata_ = abi.encodeWithSelector(BasketManager.setTokenSwapAdapter.selector, newAdapter);

        addToBatch(
            timelock,
            0,
            abi.encodeWithSelector(
                TimelockController.schedule.selector, basketManager, 0, calldata_, bytes32(0), bytes32(0), delay
            )
        );

        console2.log("=== Schedule Timelock Transaction ===");
        console2.log("Environment:", _buildPrefix());
        console2.log("Timelock:", timelock);
        console2.log("BasketManager:", basketManager);
        console2.log("New adapter:", newAdapter);
        console2.log("Delay (s):", delay);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            executeBatch(true);
        } else {
            executeBatch(false);
        }
    }

    /// @notice Executes the timelock transaction after the delay has passed.
    function executeTimelock() public {
        address timelock = deployer.getAddress(buildTimelockControllerName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address newAdapter = deployer.getAddress(string.concat(_buildPrefix(), _ADAPTER_SUFFIX));
        if (newAdapter == address(0)) {
            revert("New adapter deployment not found");
        }

        console2.log("=== Execute Timelock Transaction ===");
        console2.log("Environment:", _buildPrefix());
        console2.log("Timelock:", timelock);
        console2.log("BasketManager:", basketManager);
        console2.log("New adapter:", newAdapter);

        bytes memory data = abi.encodeWithSelector(BasketManager.setTokenSwapAdapter.selector, newAdapter);
        vm.broadcast();
        TimelockController(payable(timelock)).execute(basketManager, 0, data, bytes32(0), bytes32(0));
    }
}

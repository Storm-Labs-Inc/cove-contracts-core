// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { DefaultDeployerFunction } from "forge-deploy/DefaultDeployerFunction.sol";
import { console2 } from "forge-std/console2.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { VmSafe } from "forge-std/Vm.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { BasketManager } from "src/BasketManager.sol";
import { Constants } from "test/utils/Constants.t.sol";

/// @title UpdateCoWSwapAdapterV3Base
/// @notice Abstract base contract for deploying and updating the CoWSwap adapter with configurable appData and domain
/// separator.
/// @dev Subclasses must override `_safe()`, `_buildPrefix()`, `_appDataHash()`, and `_cowSettlementDomainSeparator()`.
abstract contract UpdateCoWSwapAdapterV3Base is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    string internal constant _CLONE_ARTIFACT = "CoWSwapCloneWithAppDataAndDomain.sol:CoWSwapCloneWithAppDataAndDomain";
    string internal constant _IMPLEMENTATION_SUFFIX = "CoWSwapCloneImplementation_AppDataV3";
    string internal constant _ADAPTER_SUFFIX = "CowSwapAdapter_AppDataV3";

    /// @notice Returns the Safe multisig address for batch transactions.
    function _safe() internal view virtual returns (address);

    /// @notice Returns the appData hash for CoWSwap orders.
    function _appDataHash() internal view virtual returns (bytes32);

    /// @notice Returns the GPv2Settlement domain separator to validate order digests.
    function _cowSettlementDomainSeparator() internal view virtual returns (bytes32);

    /// @notice Deploys the new CoWSwapCloneWithAppDataAndDomain implementation and CoWSwapAdapter contracts.
    function deploy() public {
        deployer.setAutoBroadcast(true);

        address oldAdapter = deployer.getAddress(buildCowSwapAdapterName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        bytes32 appDataHash = _appDataHash();
        bytes32 domainSeparator = _cowSettlementDomainSeparator();

        address newCloneImplementation = address(
            DefaultDeployerFunction.deploy(
                deployer,
                string.concat(_buildPrefix(), _IMPLEMENTATION_SUFFIX),
                _CLONE_ARTIFACT,
                abi.encode(appDataHash, domainSeparator)
            )
        );

        address newAdapter = address(
            deployer.deploy_CoWSwapAdapter(string.concat(_buildPrefix(), _ADAPTER_SUFFIX), newCloneImplementation)
        );

        console2.log("=== CoWSwap Adapter Deployment (v3) ===");
        console2.log("Environment:", _buildPrefix());
        console2.log("BasketManager:", basketManager);
        console2.log("Previous adapter:", oldAdapter);
        console2.log("New clone implementation:", newCloneImplementation);
        console2.log("New adapter:", newAdapter);
        console2.log("appDataHash:");
        console2.logBytes32(appDataHash);
        console2.log("GPv2 domain separator:");
        console2.logBytes32(domainSeparator);
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

        console2.log("=== Schedule Timelock Transaction (v3) ===");
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

        console2.log("=== Execute Timelock Transaction (v3) ===");
        console2.log("Environment:", _buildPrefix());
        console2.log("Timelock:", timelock);
        console2.log("BasketManager:", basketManager);
        console2.log("New adapter:", newAdapter);

        bytes memory data = abi.encodeWithSelector(BasketManager.setTokenSwapAdapter.selector, newAdapter);
        vm.broadcast();
        TimelockController(payable(timelock)).execute(basketManager, 0, data, bytes32(0), bytes32(0));
    }
}

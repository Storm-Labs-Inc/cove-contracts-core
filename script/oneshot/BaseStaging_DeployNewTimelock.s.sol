// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { console2 } from "forge-std/console2.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { VmSafe } from "forge-std/Vm.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

/// @title BaseStaging_DeployNewTimelock
/// @notice Deploys a new TimelockController and updates roles for Base staging.
/// @dev Usage:
///   1. Deploy new timelock:
///      DEPLOYMENT_CONTEXT=8453 forge script ... --sig "deploy()" --broadcast
///   2. Queue role update via Safe batch:
///      DEPLOYMENT_CONTEXT=8453 forge script ... --sig "updateTimelockRole()"
contract BaseStagingDeployNewTimelock is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public constant OLD_TIMELOCK = 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function _safe() internal view returns (address) {
        return BASE_STAGING_COMMUNITY_MULTISIG;
    }

    /// @notice Deploys a new TimelockController and updates the MasterRegistry.
    function deploy() public {
        deployer.setAutoBroadcast(true);

        address admin = BASE_STAGING_COMMUNITY_MULTISIG;
        address manager = BASE_STAGING_OPS_MULTISIG;

        address[] memory proposers = new address[](2);
        proposers[0] = admin;
        proposers[1] = manager;

        address[] memory executors = new address[](3);
        executors[0] = admin;
        executors[1] = manager;
        executors[2] = COVE_DEPLOYER_ADDRESS;

        address timelockAdmin = admin;
        address timelock = address(
            deployer.deploy_TimelockController(buildTimelockControllerName(), 0, proposers, executors, timelockAdmin)
        );

        console2.log("=== Deploy New Timelock ===");
        console2.log("New Timelock:", timelock);

        IMasterRegistry masterRegistry = IMasterRegistry(deployer.getAddress(buildMasterRegistryName()));

        vm.broadcast();
        masterRegistry.updateRegistry("TimelockController", timelock);
    }

    /// @notice Queues a Safe batch to revoke TIMELOCK_ROLE from old timelock and grant to new one.
    function updateTimelockRole() public isBatch(_safe()) {
        deployer.setAutoBroadcast(true);

        address basketManager = deployer.getAddress(buildBasketManagerName());
        address newTimelock = deployer.getAddress(buildTimelockControllerName());

        console2.log("=== Update TIMELOCK_ROLE on BasketManager ===");
        console2.log("BasketManager:", basketManager);
        console2.log("Old Timelock (revoke):", OLD_TIMELOCK);
        console2.log("New Timelock (grant):", newTimelock);

        IAccessControl accessControl = IAccessControl(basketManager);

        // Revoke TIMELOCK_ROLE from old timelock
        addToBatch(
            basketManager, 0, abi.encodeWithSelector(accessControl.revokeRole.selector, TIMELOCK_ROLE, OLD_TIMELOCK)
        );

        // Grant TIMELOCK_ROLE to new timelock
        addToBatch(
            basketManager, 0, abi.encodeWithSelector(accessControl.grantRole.selector, TIMELOCK_ROLE, newTimelock)
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

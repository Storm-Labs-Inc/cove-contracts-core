// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { FarmingPluginFactory } from "src/rewards/FarmingPluginFactory.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Staging_FarmingPluginFactory_UpdateRoles
 * @notice Script to update the roles in the FarmingPluginFactory contract for the staging environment.
 */
// solhint-disable var-name-mixedcase
contract UpdateRoles is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);

        FarmingPluginFactory farmingPluginFactory =
            FarmingPluginFactory(deployer.getAddress(buildFarmingPluginFactoryName()));
        IAccessControlEnumerable accessControl = IAccessControlEnumerable(address(farmingPluginFactory));

        // Revoke manage role given to deployer
        address oldManager = COVE_DEPLOYER_ADDRESS;

        if (accessControl.hasRole(MANAGER_ROLE, oldManager)) {
            addToBatch(
                address(farmingPluginFactory),
                0,
                abi.encodeWithSelector(accessControl.revokeRole.selector, MANAGER_ROLE, oldManager)
            );
        }

        // Set the default plugin owner to the community multisig
        addToBatch(
            address(farmingPluginFactory),
            0,
            abi.encodeWithSelector(farmingPluginFactory.setDefaultPluginOwner.selector, COVE_STAGING_COMMUNITY_MULTISIG)
        );

        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }
}

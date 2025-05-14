// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol"; // Not directly used
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
// import { StdAssertions } from "forge-std/StdAssertions.sol"; // Not directly used
// import { console } from "forge-std/console.sol"; // Not directly used

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Staging_AssetRegistry_ReplaceManagerRole
 * @notice Script to replace the current manager with the new manager in the AssetRegistry contract for the staging
 * environment.
 */
// solhint-disable var-name-mixedcase
contract ReplaceManagerRole is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);

        AssetRegistry assetRegistry = AssetRegistry(deployer.getAddress(buildAssetRegistryName()));
        IAccessControlEnumerable accessControl = IAccessControlEnumerable(address(assetRegistry));

        address oldManager = COVE_DEPLOYER_ADDRESS;
        address newManager = COVE_STAGING_OPS_MULTISIG;

        if (
            !accessControl.hasRole(MANAGER_ROLE, oldManager)
                && accessControl.hasRole(MANAGER_ROLE, COVE_STAGING_OPS_MULTISIG)
        ) {
            revert(
                string.concat(
                    buildAssetRegistryName(),
                    " already has the new manager as the manager. Was this script already run?"
                )
            );
        }

        if (accessControl.hasRole(MANAGER_ROLE, oldManager)) {
            addToBatch(
                address(assetRegistry),
                0,
                abi.encodeWithSelector(accessControl.revokeRole.selector, MANAGER_ROLE, oldManager)
            );
        }
        if (!accessControl.hasRole(MANAGER_ROLE, newManager)) {
            addToBatch(
                address(assetRegistry),
                0,
                abi.encodeWithSelector(accessControl.grantRole.selector, MANAGER_ROLE, newManager)
            );
        }
        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }
}

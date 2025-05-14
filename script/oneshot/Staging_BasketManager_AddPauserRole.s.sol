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
import { BasketManager } from "src/BasketManager.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title AddPauserRole
 * @notice Script to add pauser roles to the BasketManager contract for the staging environment.
 * @dev This script iterates through a list of predefined addresses and grants them the PAUSER_ROLE
 * on the BasketManager contract. It uses BatchScript to group these operations.
 */
// solhint-disable var-name-mixedcase
contract AddPauserRole is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);

        BasketManager basketManager = BasketManager(deployer.getAddress(buildBasketManagerName()));
        IAccessControlEnumerable accessControl = IAccessControlEnumerable(address(basketManager));

        // Future: Consider adding logic to revoke existing pausers if needed.
        // Example to list current pausers (requires BasketManager to expose this or use events off-chain):
        uint256 pauserCount = accessControl.getRoleMemberCount(PAUSER_ROLE);
        if (pauserCount > 1) {
            revert(
                string.concat(buildBasketManagerName(), " already has more than 1 pauser. Was this script already run?")
            );
        }
        for (uint256 i = 0; i < pauserCount; i++) {
            address currentPauser = accessControl.getRoleMember(PAUSER_ROLE, i);
            // then potentially revoke them
            addToBatch(
                address(basketManager),
                0,
                abi.encodeWithSelector(accessControl.revokeRole.selector, PAUSER_ROLE, currentPauser)
            );
        }

        address[] memory pausersToAdd = new address[](4);
        pausersToAdd[0] = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        pausersToAdd[1] = COVE_STAGING_COMMUNITY_MULTISIG;
        pausersToAdd[2] = COVE_STAGING_OPS_MULTISIG;
        pausersToAdd[3] = COVE_DEPLOYER_ADDRESS;

        for (uint256 i = 0; i < pausersToAdd.length; i++) {
            if (pausersToAdd[i] != address(0) && !accessControl.hasRole(PAUSER_ROLE, pausersToAdd[i])) {
                addToBatch(
                    address(basketManager),
                    0,
                    abi.encodeWithSelector(accessControl.grantRole.selector, PAUSER_ROLE, pausersToAdd[i])
                );
            }
        }
        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }
}

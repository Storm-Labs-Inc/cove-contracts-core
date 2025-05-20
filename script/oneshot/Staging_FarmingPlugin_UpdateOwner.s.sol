// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Staging_FarmingPlugin_UpdateOwner
 * @notice Script to update the owner of the FarmingPlugin contract for the staging environment.
 */
// solhint-disable var-name-mixedcase
contract UpdateOwner is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public safe = COVE_STAGING_OPS_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);

        FarmingPlugin farmingPlugin = FarmingPlugin(0x27BdAAdfDc0c3E39ad38C86f2f1774B51E4D237e);

        addToBatch(
            address(farmingPlugin),
            0,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, COVE_STAGING_COMMUNITY_MULTISIG)
        );

        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }
}

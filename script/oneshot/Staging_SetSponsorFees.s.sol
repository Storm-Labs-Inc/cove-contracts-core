// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";

import { FeeCollector } from "src/FeeCollector.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Staging_SetManagementFee
 * @notice Script to set the management fee for the staging environment.
 */
// solhint-disable var-name-mixedcase
contract SetManagementFee is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);

        FeeCollector feeCollector = FeeCollector(deployer.getAddress(buildFeeCollectorName()));

        // Set sponsor to deployer for testing
        addToBatch(
            address(feeCollector),
            0,
            abi.encodeCall(feeCollector.setSponsor, (0x9f53dA1E245207e163E71DFC45dAFaB2d01770d0, COVE_DEPLOYER_ADDRESS))
        );
        // Set sponsor split to 50%
        addToBatch(
            address(feeCollector),
            0,
            abi.encodeCall(feeCollector.setSponsorSplit, (0x9f53dA1E245207e163E71DFC45dAFaB2d01770d0, 5000)) // 50%
        );

        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }
}

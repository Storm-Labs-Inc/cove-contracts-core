// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { BasketManager } from "src/BasketManager.sol";
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

        BasketManager basketManager = BasketManager(deployer.getAddress(buildBasketManagerName()));

        // Set the management fee to 0.5%
        // The call need to be coming from timelock. But the timelock is owned by the staging community multisig.
        // Therefore we need to construct the timelock transaction and add it to the batch.
        address timelock = deployer.getAddress(buildTimelockControllerName());
        address[] memory targets = new address[](1);
        targets[0] = address(basketManager);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(basketManager.setManagementFee, (0x9f53dA1E245207e163E71DFC45dAFaB2d01770d0, 200)); // in
            // bps, 2%
        // addToBatch(timelock, 0, abi.encodeCall(TimelockController.scheduleBatch, (targets, values, calldatas,
        // bytes32(0), bytes32(0), 0)));

        // if (encodedTxns.length > 0) {
        //     executeBatch(true);
        // }

        // vm.warp(block.timestamp + 1);
        // Prank the staging community multisig to execute the timelock transaction
        vm.broadcast(COVE_DEPLOYER_ADDRESS);
        TimelockController(payable(timelock)).executeBatch(targets, values, calldatas, bytes32(0), 0);
    }
}

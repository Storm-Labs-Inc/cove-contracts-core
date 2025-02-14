// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Deployments } from "./Deployments.s.sol";

contract StagingDeployments is Deployments {
    function deploy() public override {
        // Deploy staging timelock controller
        address stagingTimelock = _deployStagingTimelockController();

        // Call base deployment with staging addresses
        deploy(
            true, // isProduction
            true, // isStaging
            STAGING_COVE_ADMIN,
            STAGING_COVE_TREASURY,
            STAGING_COVE_PAUSER,
            STAGING_COVE_MANAGER,
            stagingTimelock,
            STAGING_COVE_REBALANCE_PROPOSER,
            STAGING_COVE_TOKEN_SWAP_PROPOSER,
            STAGING_COVE_TOKEN_SWAP_EXECUTOR
        );
    }
    // DEPLOYMENT_CONTEXT=1-fork forge script script/StagingDeployments.s.sol --rpc-url http://localhost:8545
    // --broadcast --sender 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5 -vvv --unlocked && ./forge-deploy sync;
}

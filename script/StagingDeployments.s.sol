// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Deployments } from "./Deployments.s.sol";

contract StagingDeployments is Deployments {
    address public stagingTimelock;

    function deploy() public override {
        stagingTimelock = getAddress("StagingTimelockController");
        // Deploy staging timelock controller
        if (stagingTimelock == address(0)) {
            stagingTimelock = _deployStagingTimelockController();
        }

        // Call base deployment with staging addresses
        deploy(
            true, // isProduction
            true, // isStaging
            0xaAc26aee89DeEFf5D0BE246391FABDfa547dc70C, // admin multisig
            0x5dA5a68e840785Fc001f3Bc55c4E9bE84d3A8dDc, // treasury
            0xc8C812D4cD68b3bD0d4D7E6f95661312733207dA, // pauser
            0x39B12050140d1d61D3239a58875DaE98f7f23314, //manager
            stagingTimelock,
            0x66955d9Be79C3d9a1Dec5C82f0B6EFC34C843CA6, // rebalance proposer
            0xAa662f0521a2287B408bd3Bc784258349d40874b, // token swap proposer
            0xf95a7D8e5351E922161ae8d35E9723F93b4dAf26 // token swap executor
        );
    }
    // DEPLOYMENT_CONTEXT=1-fork forge script script/StagingDeployments.s.sol --rpc-url http://localhost:8545
    // --broadcast --sender 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5 -vvv --unlocked && ./forge-deploy sync;
}

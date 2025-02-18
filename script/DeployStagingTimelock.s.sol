// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract DeployStagingTimelock is DeployScript, Constants, StdAssertions {
    address public stagingTimelock;

    function deploy() public virtual {
        labelKnownAddresses();
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");

        address[] memory proposers = new address[](3);
        proposers[0] = COVE_STAGING_COMMUNITY_MULTISIG;
        proposers[1] = COVE_STAGING_OPS_MULTISIG;
        proposers[2] = COVE_DEPLOYER_ADDRESS;
        address[] memory executors = new address[](1);
        executors[0] = COVE_DEPLOYER_ADDRESS;
        address timelockAdmin = COVE_STAGING_COMMUNITY_MULTISIG;
        address timelockController = _deployTimelockController(0, proposers, executors, timelockAdmin);

        IMasterRegistry registry = IMasterRegistry(COVE_MASTER_REGISTRY);
        vm.broadcast();
        registry.addRegistry("StagingTimelockController", address(timelockController));
        address timelockControllerAddress = registry.resolveNameToLatestAddress("StagingTimelockController");
        require(
            timelockControllerAddress == timelockController, "Failed to add StagingTimelockController to MasterRegistry"
        );
    }

    function _deployTimelockController(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address timelockAdmin
    )
        internal
        returns (address timelockController)
    {
        bytes memory constructorArgs = abi.encode(minDelay, proposers, executors, timelockAdmin);
        bytes memory creationBytecode = abi.encodePacked(type(TimelockController).creationCode, constructorArgs);
        vm.broadcast();
        timelockController = address(new TimelockController(minDelay, proposers, executors, timelockAdmin));
        deployer.save(
            "StagingTimelockController",
            timelockController,
            "TimelockController.sol:TimelockController",
            constructorArgs,
            creationBytecode
        );
        require(
            deployer.getAddress("StagingTimelockController") == timelockController,
            "Failed to save StagingTimelockController deployment"
        );
    }
}

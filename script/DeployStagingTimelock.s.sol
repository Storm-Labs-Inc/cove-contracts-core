// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer } from "forge-deploy/Deployer.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract DeployStagingTimelock is DeployScript, Constants, StdAssertions {
    using CustomDeployerFunctions for Deployer;

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
        address timelockController = address(
            deployer.deploy_TimelockController("Staging_TimelockController", 0, proposers, executors, timelockAdmin)
        );

        IMasterRegistry registry = IMasterRegistry(COVE_STAGING_MASTER_REGISTRY);
        vm.broadcast();
        registry.addRegistry("TimelockController", address(timelockController));

        address timelockControllerAddress = registry.resolveNameToLatestAddress("TimelockController");
        require(
            timelockControllerAddress == timelockController, "Failed to add StagingTimelockController to MasterRegistry"
        );

        IMasterRegistry prodRegistry = IMasterRegistry(COVE_MASTER_REGISTRY);
        address prodTimelockController = deployer.getAddress("TimelockController");
        vm.broadcast();
        prodRegistry.addRegistry("TimelockController", prodTimelockController);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { console } from "forge-std/console.sol";

contract StagingDeployBasicRetryOperator is DeployScript, Constants, StdAssertions, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    IMasterRegistry public masterRegistry;
    IMasterRegistry public stagingMasterRegistry;
    bool public shouldBroadcast;

    // Called from DeployScript's run() function
    function deploy() public virtual {
        deploy(true);
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy(bool shouldBroadcast_) public {
        shouldBroadcast = shouldBroadcast_;

        // Only allow COVE_DEPLOYER to update in production
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");

        stagingMasterRegistry = IMasterRegistry(COVE_STAGING_MASTER_REGISTRY);

        address basicRetryOperator = address(
            deployer.deploy_BasicRetryOperator(
                buildBasicRetryOperatorName(), COVE_DEPLOYER_ADDRESS, COVE_DEPLOYER_ADDRESS
            )
        );

        try stagingMasterRegistry.resolveNameToLatestAddress("BasicRetryOperator") returns (address currentOperator) {
            if (basicRetryOperator != currentOperator) {
                console.log("Current operator:", currentOperator);
                console.log("New operator:", basicRetryOperator);
                console.log("Redeploying and updating the registry");
                if (shouldBroadcast) vm.broadcast();
                stagingMasterRegistry.updateRegistry("BasicRetryOperator", basicRetryOperator);
            }
        } catch {
            console.log("BasicRetryOperator not deployed");
            console.log("Deploying and updating the registry");
            if (shouldBroadcast) vm.broadcast();
            stagingMasterRegistry.addRegistry("BasicRetryOperator", basicRetryOperator);
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";

import { console2 } from "forge-std/console2.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { BasketManager } from "src/BasketManager.sol";
import { Constants } from "test/utils/Constants.t.sol";

/// @title BaseStaging_RedeployCoWSwapAdapterAppData
/// @notice Re-deploys the CoWSwap adapter with the updated appData requirements and wires it into the Base staging
/// BasketManager.
contract BaseStagingRedeployCoWSwapAdapterAppData is DeployScript, Constants, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    string internal constant _IMPLEMENTATION_SUFFIX = "CoWSwapCloneImplementation_AppDataV1";
    string internal constant _ADAPTER_SUFFIX = "CowSwapAdapter_AppDataV1";

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public {
        deployer.setAutoBroadcast(true);

        address oldAdapter = deployer.getAddress(buildCowSwapAdapterName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address timelock = deployer.getAddress(buildTimelockControllerName());
        bytes32 appDataHash = STAGING_COWSWAP_APPDATA_HASH;

        address newCloneImplementation = address(
            deployer.deploy_CoWSwapCloneWithAppData(string.concat(_buildPrefix(), _IMPLEMENTATION_SUFFIX), appDataHash)
        );

        address newAdapter = address(
            deployer.deploy_CoWSwapAdapter(string.concat(_buildPrefix(), _ADAPTER_SUFFIX), newCloneImplementation)
        );

        console2.log("Previous adapter:", oldAdapter);
        console2.log("New clone implementation:", newCloneImplementation);
        console2.log("New adapter:", newAdapter);
        console2.log("appDataHash:");
        console2.logBytes32(appDataHash);

        vm.prank(timelock);
        BasketManager(basketManager).setTokenSwapAdapter(newAdapter);
    }
}

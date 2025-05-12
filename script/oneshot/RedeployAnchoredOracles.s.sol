// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title RedeployAnchoredOracles
 * @notice Script to redeploy the anchored oracles for staging environment
 */
contract RedeployAnchoredOracles is DeployScript, Constants, StdAssertions, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    // Oracle configuration parameters
    uint256 public constant MAX_DIVERGENCE = 0.005e18; // 0.5%

    address public governor;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    address[] public assets;
    address[] public primaryOracles;
    address[] public anchorOracles;

    function _buildPrefix() internal view override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        assets = new address[](5);
        primaryOracles = new address[](5);
        anchorOracles = new address[](5);

        assets[0] = ETH_USDC;
        assets[1] = ETH_SDAI;
        assets[2] = ETH_SUSDE;
        assets[3] = ETH_SFRXUSD;
        assets[4] = ETH_YSYG_YVUSDS_1;

        deployer.setAutoBroadcast(true);
        // Print current configuration
        _printCurrentConfiguration();

        // Deploy anchored oracles for all assets
        _deployAnchoredOracles();

        // Print final configuration
        console.log("\n--- Final Configuration ---");
        _printCurrentConfiguration();

        executeBatch(true);
    }

    function _printCurrentConfiguration() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));

        console.log("--- Current EulerRouter Configuration ---");
        console.log("EulerRouter address:", address(router));
        governor = router.governor();
        console.log("Governor:", governor);

        // Check configured oracles
        console.log("\n--- Configured Oracles ---");
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            string memory assetSymbol = IERC20Metadata(asset).symbol();
            address currentAnchoredOracle = router.getConfiguredOracle(asset, USD);
            primaryOracles[i] = AnchoredOracle(currentAnchoredOracle).primaryOracle();
            anchorOracles[i] = AnchoredOracle(currentAnchoredOracle).anchorOracle();

            console.log(
                string.concat(
                    assetSymbol,
                    "/USD\nCurrent Anchored Oracle: ",
                    vm.toString(currentAnchoredOracle),
                    "\nPrimary Oracle: ",
                    vm.toString(primaryOracles[i]),
                    "\nAnchor Oracle: ",
                    vm.toString(anchorOracles[i]),
                    "\n"
                )
            );
        }
    }

    function _deployAnchoredOracles() private {
        // Deploy anchored oracles for these assets
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));

        for (uint256 i = 0; i < assets.length; i++) {
            string memory assetName = IERC20Metadata(assets[i]).name();
            console.log(
                string.concat(
                    "Deploying anchored oracle for ",
                    assetName,
                    " with primary oracle ",
                    vm.toString(primaryOracles[i]),
                    " and anchor oracle ",
                    vm.toString(anchorOracles[i])
                )
            );

            // Deploy anchored oracle
            address anchoredOracle = address(
                deployer.deploy_AnchoredOracle(
                    buildAnchoredOracleName(assets[i], USD), primaryOracles[i], anchorOracles[i], MAX_DIVERGENCE
                )
            );

            // Set anchored oracle
            addToBatch(
                address(router),
                0,
                abi.encodeWithSelector(EulerRouter.govSetConfig.selector, assets[i], USD, anchoredOracle)
            );
            console.log(string.concat("Set ", assetName, "/USD anchored oracle to ", vm.toString(anchoredOracle)));
        }
    }
}

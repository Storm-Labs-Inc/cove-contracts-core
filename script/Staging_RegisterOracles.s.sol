// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { BuildDeploymentJsonNames } from "./utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Staging_RegisterOracles
 * @notice Script to update the oracles for 4626 tokens in the staging environment
 * @dev This script deploys and configures oracles for sUSDe, sDAI, and sFRAX
 */
// solhint-disable contract-name-camelcase
contract Staging_RegisterOracles is DeployScript, Constants, StdAssertions, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public governor;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);
        // Print current configuration
        _printCurrentConfiguration();

        // Register anchored oracles
        _registerAnchoredOracles();

        // Print final configuration
        console.log("\n--- Final Configuration ---");
        _printCurrentConfiguration();

        // executeBatch(true);
    }

    function _printCurrentConfiguration() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));

        console.log("--- Current EulerRouter Configuration ---");
        console.log("EulerRouter address:", address(router));
        governor = router.governor();
        console.log("Governor:", governor);

        // Check configured oracles
        console.log("\n--- Configured Oracles ---");
        address USDC_oracle = router.getConfiguredOracle(ETH_USDC, USD);
        console.log("USDC/USD oracle:", USDC_oracle);

        address sUSDe_oracle = router.getConfiguredOracle(ETH_SUSDE, USD);
        console.log("sUSDe/USD oracle:", sUSDe_oracle);

        address sDAI_oracle = router.getConfiguredOracle(ETH_SDAI, USD);
        console.log("sDAI/USD oracle:", sDAI_oracle);

        address sfrxUSD_oracle = router.getConfiguredOracle(ETH_SFRXUSD, USD);
        console.log("sfrxUSD/USD oracle:", sfrxUSD_oracle);
    }

    function _registerAnchoredOracles() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));

        // 1. Get anchored oracles
        address USDC_oracle = deployer.getAddress(buildAnchoredOracleName(ETH_USDC, USD));
        address sUSDe_oracle = deployer.getAddress(buildAnchoredOracleName(ETH_SUSDE, USD));
        address sDAI_oracle = deployer.getAddress(buildAnchoredOracleName(ETH_SDAI, USD));
        address sfrxUSD_oracle = deployer.getAddress(buildAnchoredOracleName(ETH_SFRXUSD, USD));

        // 2. Register oracles
        addToBatch(
            address(router), 0, abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_USDC, USD, USDC_oracle)
        );
        console.logBytes(abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_USDC, USD, USDC_oracle));
        console.log("Registered USDC/USD oracle");

        addToBatch(
            address(router), 0, abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SUSDE, USD, sUSDe_oracle)
        );
        console.logBytes(abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SUSDE, USD, sUSDe_oracle));
        console.log("Registered sUSDe/USD oracle");

        addToBatch(
            address(router), 0, abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SDAI, USD, sDAI_oracle)
        );
        console.logBytes(abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SDAI, USD, sDAI_oracle));
        console.log("Registered sDAI/USD oracle");

        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SFRXUSD, USD, sfrxUSD_oracle)
        );
        console.logBytes(abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SFRXUSD, USD, sfrxUSD_oracle));
        console.log("Registered sfrxUSD/USD oracle");
    }
}

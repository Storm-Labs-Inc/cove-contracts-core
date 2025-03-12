// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

// solhint-disable contract-name-camelcase
contract Deployments_Staging is Deployments {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function _setPermissionedAddresses() internal virtual override {
        // Set permissioned addresses
        // Staging deploy
        admin = COVE_STAGING_COMMUNITY_MULTISIG;
        treasury = COVE_STAGING_COMMUNITY_MULTISIG;
        pauser = COVE_DEPLOYER_ADDRESS;
        manager = COVE_STAGING_OPS_MULTISIG;
        timelock = getAddress(buildTimelockControllerName());
        rebalanceProposer = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        tokenSwapProposer = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        tokenSwapExecutor = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
    }

    function _deployNonCoreContracts() internal override {
        address[] memory basketAssets = new address[](4);
        basketAssets[0] = ETH_USDC;
        basketAssets[1] = ETH_SDAI;
        basketAssets[2] = ETH_SUSDE;
        basketAssets[3] = ETH_SFRXUSD;

        // 0. USD
        // Primary: USDC --(Pyth)--> USD
        // Anchor: USDC --(Chainlink)--> USD
        _deployDefaultAnchoredOracleForAsset(
            ETH_USDC,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_USDC);

        // 1. sDAI
        // Primary: sDAI --(Pyth)--> USD
        // Anchor: sDAI --(4626)--> DAI --(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAsset(
            ETH_SDAI,
            false,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_SDAI_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_DAI_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_SDAI);

        // 2. sUSDe
        // Primary: sUSDe --(Pyth)--> USD
        // Anchor: sUSDe --(4626)--> USDe --(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAsset(
            ETH_SUSDE,
            false,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_SUSDE_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDE_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_SUSDE);

        // 3. sfrxUSD
        // Primary: sfrxUSD --(CurveEMA)--> sUSDe --(Pyth)--> USD
        // Anchor: sfrxUSD --(CurveEMA)--> sUSDe --(Chainlink)--> USD
        _deployCurveEMAOracleCrossAdapterForNonUSDPair(
            ETH_SFRXUSD,
            ETH_CURVE_SFRXUSD_SUSDE_POOL,
            ETH_SUSDE,
            0, // sfrxUSD is the first coin in the pool
            1, // sUSDe is the second coin in the pool
            OracleOptions({
                pythPriceFeed: PYTH_SUSDE_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_SUSDE_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_SFRXUSD);

        // Deploy launch strategy
        _deployManagedStrategy(COVE_DEPLOYER_ADDRESS, "Gauntlet V1");

        uint64[] memory initialWeights = new uint64[](4);
        initialWeights[0] = 0;
        initialWeights[1] = 0.3333333333333334e18;
        initialWeights[2] = 0.3333333333333333e18;
        initialWeights[3] = 0.3333333333333333e18;

        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "Stables",
                symbol: "stgUSD",
                rootAsset: ETH_USDC,
                bitFlag: assetsToBitFlag(basketAssets),
                strategy: getAddress(buildManagedWeightStrategyName("Gauntlet V1")),
                initialWeights: initialWeights
            })
        );

        // Deploy ERC20Mock for farming plugin rewards
        ERC20Mock mockERC20 = deployer.deploy_ERC20Mock("CoveMockERC20");

        // Deploy farming plugin
        address basketToken = getAddress(buildBasketTokenName("Stables"));
        address farmingPlugin = address(
            deployer.deploy_FarmingPlugin(
                buildFarmingPluginName(basketToken, address(mockERC20)),
                basketToken,
                address(mockERC20),
                COVE_DEPLOYER_ADDRESS
            )
        );
        _addToMasterRegistryLater("FP_stgUSD_E20M", farmingPlugin);
    }
}

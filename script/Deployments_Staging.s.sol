// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

contract DeploymentsStaging is Deployments {
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
        pauser = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        manager = COVE_STAGING_OPS_MULTISIG;
        timelock = getAddressOrRevert(buildTimelockControllerName());
        rebalanceProposer = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        tokenSwapProposer = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        tokenSwapExecutor = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
        rewardToken = address(deployer.deploy_ERC20Mock(string.concat(_buildPrefix(), "CoveMockERC20")));
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Staging_FeeCollector_0508"));
    }

    function _deployNonCoreContracts() internal override {
        // Basket assets
        address[] memory basketAssets = new address[](5);
        basketAssets[0] = ETH_USDC;
        basketAssets[1] = ETH_SUPERUSDC;
        basketAssets[2] = ETH_SUSDE;
        basketAssets[3] = ETH_SFRXUSD;
        basketAssets[4] = ETH_YSYG_YVUSDS_1;

        // Initial weights for respective basket assets
        uint64[] memory initialWeights = new uint64[](5);
        initialWeights[0] = 0;
        initialWeights[1] = 0.25e18;
        initialWeights[2] = 0.25e18;
        initialWeights[3] = 0.25e18;
        initialWeights[4] = 0.25e18;

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

        // 1. SUPERUSDC
        // Primary: SUPERUSDC-->(4626)--> USDC-->(Pyth)--> USD
        // Anchor: SUPERUSDC-->(4626)--> USDC-->(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAsset(
            ETH_SUPERUSDC,
            true,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_SUPERUSDC);

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
        // Primary: sfrxUSD --(4626)--> frxUSD --(Pyth)--> USD
        // Anchor: sfrxUSD --(4626)--> frxUSD --(CurveEMA)--> USDE --(Chainlink)--> USD
        _deployAnchoredOracleWith4626CurveEMAOracleUnderlying(
            ETH_SFRXUSD,
            ETH_CURVE_SFRXUSD_SUSDE_POOL,
            ETH_USDE,
            0, // sfrxUSD is the first coin in the pool, but the oracle uses frxUSD price
            1, // sUSDe is the second coin in the pool, but the oracle uses USDe price
            OracleOptions({
                pythPriceFeed: PYTH_FRXUSD_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDE_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_SFRXUSD);

        // 4. ysyG-yvUSDS-1
        // Primary: ysyG-yvUSDS-1 --(ChainedERC4626)--> USDS --(Pyth)--> USD
        // Anchor: ysyG-yvUSDS-1 --(ChainedERC4626)--> USDS --(Chainlink)--> USD
        _deployAnchoredOracleWithChainedERC4626(
            ETH_YSYG_YVUSDS_1,
            ETH_USDS,
            OracleOptions({
                pythPriceFeed: PYTH_USDS_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDS_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_YSYG_YVUSDS_1);

        // Deploy launch strategy
        _deployManagedStrategy(COVE_DEPLOYER_ADDRESS, "Gauntlet V1");

        // Set the initial weights for the strategy and deploy basket token
        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "Stables",
                symbol: "stgUSD",
                rootAsset: ETH_USDC,
                bitFlag: assetsToBitFlag(basketAssets),
                strategy: getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1")),
                initialWeights: initialWeights
            })
        );
    }
}

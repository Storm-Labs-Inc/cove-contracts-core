// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";

contract DeploymentsProduction is Deployments {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    uint256 public constant PYTH_MAX_STALENESS = 60 seconds;
    uint256 public constant TOTAL_MANAGEMENT_FEE = 50; // 50 basis points
    uint256 public constant SPONSOR_SPLIT = 5000; // 50% to sponsor

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _setPermissionedAddresses() internal virtual override {
        // Production deploy
        // TODO: confirm addresses for production
        admin = COVE_COMMUNITY_MULTISIG;
        treasury = COVE_COMMUNITY_MULTISIG;
        pauser = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        manager = COVE_OPS_MULTISIG;
        timelock = getAddressOrRevert(buildTimelockControllerName());
        rebalanceProposer = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        tokenSwapProposer = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        tokenSwapExecutor = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        rewardToken = ETH_COVE;
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Production_FeeCollector_0525"));
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
        // From 2025-05-24, the initial weights are:
        uint64[] memory initialWeights = new uint64[](5);
        initialWeights[0] = 0;
        initialWeights[1] = 0.1e17; // superUSDC
        initialWeights[2] = 0.4e17; // sUSDe
        initialWeights[3] = 0.1e17; // sfrxUSD
        initialWeights[4] = 0.4e17; // ysyG-yvUSDS-1

        // 0. USD
        // Primary: USDC --(Pyth)--> USD
        // Anchor: USDC --(Chainlink)--> USD
        _deployDefaultAnchoredOracleForAsset(
            ETH_USDC,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
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
                pythMaxStaleness: PYTH_MAX_STALENESS,
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
                pythMaxStaleness: PYTH_MAX_STALENESS,
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
                pythMaxStaleness: PYTH_MAX_STALENESS,
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
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDS_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );
        _addAssetToAssetRegistry(ETH_YSYG_YVUSDS_1);

        // Deploy launch strategy
        _deployManagedStrategy(COVE_DEPLOYER_ADDRESS, "Gauntlet");

        // Set the initial weights for the strategy and deploy basket token
        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "USD",
                symbol: "USD",
                rootAsset: ETH_USDC,
                bitFlag: assetsToBitFlag(basketAssets),
                strategy: getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet")),
                initialWeights: initialWeights
            })
        );

        // Set management fee to 50 basis points
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address basketToken = deployer.getAddress(buildBasketTokenName("USD"));
        if (shouldBroadcast) {
            vm.broadcast();
        }
        BasketManager(basketManager).setManagementFee(basketToken, 50);

        // Set fee collector split (50% to sponsor, 50% to COVE)
        address feeCollector = deployer.getAddress(buildFeeCollectorName());
        if (shouldBroadcast) {
            vm.broadcast();
        }
        FeeCollector(feeCollector).setSponsorSplit(basketToken, 5000);
    }
}

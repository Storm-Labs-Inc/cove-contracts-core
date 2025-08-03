// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";

import { VerifyStates_Production } from "./verify/VerifyStates_Production.s.sol";

import { console } from "forge-std/console.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";

contract DeploymentsProduction is Deployments {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    /// PYTH CONFIGS
    uint256 public constant PYTH_MAX_STALENESS = 60 seconds;
    uint256 public constant PYTH_MAX_CONF_WIDTH_BPS = 50; // 0.5%

    /// CHAINLINK CONFIGS
    uint256 public constant CHAINLINK_MAX_STALENESS = 1 days;

    /// ANCHORED ORACLE CONFIGS
    uint256 public constant ANCHORED_ORACLE_MAX_DIVERGENCE_BPS = 0.005e18; // 0.5% (in 1e18 precision)

    /// COVEUSD CONFIGS
    uint16 public constant COVE_USD_MANAGEMENT_FEE = 100; // 100 basis points
    uint16 public constant COVE_USD_SPONSOR_SPLIT = 4000; // 40% to sponsor

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
        return keccak256(abi.encodePacked("Production_FeeCollector_0526_2"));
    }

    function _postDeploy() internal override {
        (new VerifyStates_Production()).verifyDeployment();
    }

    function _cleanPermissionsExtra() internal override {
        // ManagedWeightStrategy
        ManagedWeightStrategy mwStrategy =
            ManagedWeightStrategy(getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1")));
        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        if (mwStrategy.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            mwStrategy.grantRole(DEFAULT_ADMIN_ROLE, admin);
            if (mwStrategy.hasRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS)) {
                mwStrategy.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
            }
            mwStrategy.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }
        if (shouldBroadcast) {
            vm.stopBroadcast();
        }
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
        initialWeights[1] = 0.1e18; // superUSDC
        initialWeights[2] = 0.4e18; // sUSDe
        initialWeights[3] = 0.1e18; // sfrxUSD
        initialWeights[4] = 0.4e18; // ysyG-yvUSDS-1

        // 0. USD
        // Primary: USDC --(Pyth)--> USD
        // Anchor: USDC --(Chainlink)--> USD
        _deployDefaultAnchoredOracleForAsset(
            ETH_USDC,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: ETH_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
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
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: ETH_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
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
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: ETH_CHAINLINK_USDE_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
            })
        );
        _addAssetToAssetRegistry(ETH_SUSDE);

        // 3. sfrxUSD
        // Primary: sfrxUSD --(4626)--> frxUSD --(Pyth)--> USD
        // Anchor: sfrxUSD --(4626)--> frxUSD --(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAsset(
            ETH_SFRXUSD,
            true,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_FRXUSD_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: ETH_CHAINLINK_FRXUSD_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
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
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: ETH_CHAINLINK_USDS_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
            })
        );
        _addAssetToAssetRegistry(ETH_YSYG_YVUSDS_1);

        // Deploy launch strategy
        _deployManagedStrategy(PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT, "Gauntlet V1");

        // Set the initial weights for the strategy and deploy basket token
        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "USD",
                symbol: "USD",
                rootAsset: ETH_USDC,
                bitFlag: assetsToBitFlag(basketAssets),
                strategy: getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1")),
                initialWeights: initialWeights
            })
        );

        address basketManager = deployer.getAddress(buildBasketManagerName());
        address basketToken = deployer.getAddress(buildBasketTokenName("USD"));
        address feeCollector = deployer.getAddress(buildFeeCollectorName());

        // Set sponsor to Guantlet multisig
        if (FeeCollector(feeCollector).hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            if (shouldBroadcast) {
                vm.broadcast();
            }
            FeeCollector(feeCollector).setSponsor(basketToken, SPONSOR_GAUNTLET);
        } else {
            console.log(
                "Not setting sponsor to Guantlet multisig because FeeCollector does not have DEFAULT_ADMIN_ROLE"
            );
        }

        // Set management fee to 100 basis points
        if (BasketManager(basketManager).hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            if (shouldBroadcast) {
                vm.broadcast();
            }
            BasketManager(basketManager).setManagementFee(basketToken, COVE_USD_MANAGEMENT_FEE);
        } else {
            console.log(
                "Not setting management fee to 100 basis points because BasketManager does not have DEFAULT_ADMIN_ROLE"
            );
        }

        // Set fee collector split (40% to sponsor, 60% to COVE)
        if (FeeCollector(feeCollector).hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            if (shouldBroadcast) {
                vm.broadcast();
            }
            FeeCollector(feeCollector).setSponsorSplit(basketToken, COVE_USD_SPONSOR_SPLIT);
        } else {
            console.log(
                "Not setting fee collector split to 40% to sponsor because FeeCollector does not have DEFAULT_ADMIN_ROLE"
            );
        }
    }
}

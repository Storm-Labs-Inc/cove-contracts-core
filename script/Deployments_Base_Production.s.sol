// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { VerifyStates_Base_Production } from "./verify/VerifyStates_Base_Production.s.sol";

import { console } from "forge-std/console.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";

contract DeploymentsBaseProduction is Deployments {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    /// PYTH CONFIGS
    uint256 public constant PYTH_MAX_STALENESS = 60 seconds;
    uint256 public constant PYTH_MAX_CONF_WIDTH_BPS = 50; // 0.5%

    /// CHAINLINK CONFIGS
    uint256 public constant CHAINLINK_MAX_STALENESS = 1 days;

    /// ANCHORED ORACLE CONFIGS
    uint256 public constant ANCHORED_ORACLE_MAX_DIVERGENCE_BPS = 0.005e18; // 0.5% (in 1e18 precision)

    /// BCOVEUSD CONFIGS
    uint16 public constant BASE_COVE_USD_MANAGEMENT_FEE = 100; // 100 basis points
    uint16 public constant BASE_COVE_USD_SPONSOR_SPLIT = 4000; // 40% to sponsor

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _setPermissionedAddresses() internal virtual override {
        // Base production deploy
        // Using placeholder addresses for now - these should be updated before mainnet deployment
        admin = BASE_COMMUNITY_MULTISIG;
        treasury = BASE_COMMUNITY_MULTISIG;
        pauser = BASE_AWS_KEEPER;
        manager = BASE_OPS_MULTISIG;

        // Try to get existing timelock or deploy new one for Base
        address existingTimelock = getAddress(buildTimelockControllerName());
        if (existingTimelock == address(0)) {
            // Deploy a timelock for Base
            address[] memory proposers = new address[](2);
            proposers[0] = admin;
            proposers[1] = manager;
            address[] memory executors = new address[](3);
            executors[0] = admin;
            executors[1] = manager;
            executors[2] = COVE_DEPLOYER_ADDRESS;
            address timelockAdmin = admin;
            timelock = address(
                deployer.deploy_TimelockController(
                    buildTimelockControllerName(), 0, proposers, executors, timelockAdmin
                )
            );
        } else {
            timelock = existingTimelock;
        }

        rebalanceProposer = BASE_AWS_KEEPER;
        tokenSwapProposer = BASE_AWS_KEEPER;
        tokenSwapExecutor = BASE_AWS_KEEPER;
        rewardToken = address(0); // No COVE token on Base yet
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Base_Production_FeeCollector_2025_10"));
    }

    function _deployPluginsViaFactory() internal override {
        // Skip farming plugin deployment on Base since there's no COVE token yet
        console.log("Skipping farming plugin deployment - no reward token on Base");
    }

    function _postDeploy() internal override {
        (new VerifyStates_Base_Production()).verifyDeployment();
    }

    function _cleanPermissionsExtra() internal override {
        // ManagedWeightStrategy
        ManagedWeightStrategy mwStrategy =
            ManagedWeightStrategy(getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1 Base")));
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
        // Override Pyth address for Base network
        // Note: We need to handle this differently as the Constants file is chain-agnostic
        address basePyth = BASE_PYTH;

        // Basket assets for Base
        address[] memory basketAssets = new address[](4);
        basketAssets[0] = BASE_USDC;
        basketAssets[1] = BASE_BASEUSD;
        basketAssets[2] = BASE_SUPERUSDC;
        basketAssets[3] = BASE_SPARKUSDC;

        // Initial weights for respective basket assets (equal weighting)
        uint64[] memory initialWeights = new uint64[](4);
        initialWeights[0] = 0.25e18; // USDC: 25%
        initialWeights[1] = 0.25e18; // baseUSD: 25%
        initialWeights[2] = 0.25e18; // superUSDC: 25%
        initialWeights[3] = 0.25e18; // sparkUSDC: 25%

        // 0. USDC
        // Primary: USDC --(Pyth)--> USD
        // Anchor: USDC --(Chainlink)--> USD
        _deployDefaultAnchoredOracleForAssetBase(
            BASE_USDC,
            basePyth,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: BASE_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
            })
        );
        _addAssetToAssetRegistry(BASE_USDC);

        // 1. baseUSD (Auto Finance Tokemak baseUSD)
        // Primary: baseUSD-->(4626)--> USDC-->(Pyth)--> USD
        // Anchor: baseUSD-->(4626)--> USDC-->(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAssetBase(
            BASE_BASEUSD,
            basePyth,
            true,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: BASE_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
            })
        );
        _addAssetToAssetRegistry(BASE_BASEUSD);

        // 2. superUSDC
        // Primary: superUSDC-->(4626)--> USDC-->(Pyth)--> USD
        // Anchor: superUSDC-->(4626)--> USDC-->(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAssetBase(
            BASE_SUPERUSDC,
            basePyth,
            true,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: BASE_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
            })
        );
        _addAssetToAssetRegistry(BASE_SUPERUSDC);

        // 3. sparkUSDC (Morpho Spark USDC Vault)
        // Primary: sparkUSDC-->(4626)--> USDC-->(Pyth)--> USD
        // Anchor: sparkUSDC-->(4626)--> USDC-->(Chainlink)--> USD
        _deployAnchoredOracleWith4626ForAssetBase(
            BASE_SPARKUSDC,
            basePyth,
            true,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: PYTH_MAX_STALENESS,
                pythMaxConfWidth: PYTH_MAX_CONF_WIDTH_BPS,
                chainlinkPriceFeed: BASE_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: CHAINLINK_MAX_STALENESS,
                maxDivergence: ANCHORED_ORACLE_MAX_DIVERGENCE_BPS
            })
        );
        _addAssetToAssetRegistry(BASE_SPARKUSDC);

        // Deploy launch strategy
        _deployManagedStrategy(BASE_GAUNTLET_SPONSOR, "Gauntlet V1 Base");

        // Set the initial weights for the strategy and deploy basket token
        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "bcoveUSD",
                symbol: "bcoveUSD",
                rootAsset: BASE_USDC,
                bitFlag: assetsToBitFlag(basketAssets),
                strategy: getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1 Base")),
                initialWeights: initialWeights
            })
        );

        address basketManager = deployer.getAddress(buildBasketManagerName());
        address basketToken = deployer.getAddress(buildBasketTokenName("bcoveUSD"));
        address feeCollector = deployer.getAddress(buildFeeCollectorName());

        // Set sponsor to Gauntlet placeholder
        if (FeeCollector(feeCollector).hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            if (shouldBroadcast) {
                vm.broadcast();
            }
            FeeCollector(feeCollector).setSponsor(basketToken, BASE_GAUNTLET_SPONSOR);
        } else {
            console.log(
                "Not setting sponsor to Gauntlet placeholder because FeeCollector does not have DEFAULT_ADMIN_ROLE"
            );
        }

        // Set management fee to 100 basis points
        if (BasketManager(basketManager).hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            if (shouldBroadcast) {
                vm.broadcast();
            }
            BasketManager(basketManager).setManagementFee(basketToken, BASE_COVE_USD_MANAGEMENT_FEE);
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
            FeeCollector(feeCollector).setSponsorSplit(basketToken, BASE_COVE_USD_SPONSOR_SPLIT);
        } else {
            console.log(
                "Not setting fee collector split to 40% to sponsor because FeeCollector does not have DEFAULT_ADMIN_ROLE"
            );
        }
    }

    // Helper function for Base network with custom Pyth address
    function _deployDefaultAnchoredOracleForAssetBase(
        address asset,
        address pythAddress,
        OracleOptions memory oracleOptions
    )
        internal
    {
        // Deploy Pyth oracle with Base-specific Pyth address
        address primary = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(asset, USD),
                pythAddress,
                asset,
                USD,
                oracleOptions.pythPriceFeed,
                oracleOptions.pythMaxStaleness,
                oracleOptions.pythMaxConfWidth
            )
        );
        address anchor = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(asset, USD),
                asset,
                USD,
                oracleOptions.chainlinkPriceFeed,
                oracleOptions.chainlinkMaxStaleness
            )
        );
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(asset, USD), primary, anchor, oracleOptions.maxDivergence
            )
        );
        // Register the asset/USD anchored oracle if it's not already registered
        _registerAnchoredOracleWithEulerRouter(asset, anchoredOracle);
    }

    // Helper function for Base network ERC4626 assets with custom Pyth address
    function _deployAnchoredOracleWith4626ForAssetBase(
        address asset,
        address pythAddress,
        bool shouldChain4626ForPyth,
        bool shouldChain4626ForChainlink,
        OracleOptions memory oracleOptions
    )
        internal
    {
        address primaryOracle;
        address underlyingAsset = IERC4626(asset).asset();
        if (shouldChain4626ForPyth) {
            address pythOracle = address(
                deployer.deploy_PythOracle(
                    buildPythOracleName(underlyingAsset, USD),
                    pythAddress,
                    underlyingAsset,
                    USD,
                    oracleOptions.pythPriceFeed,
                    oracleOptions.pythMaxStaleness,
                    oracleOptions.pythMaxConfWidth
                )
            );
            address erc4626Oracle =
                address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, underlyingAsset), IERC4626(asset)));
            primaryOracle = address(
                deployer.deploy_CrossAdapter(
                    buildCrossAdapterName(asset, underlyingAsset, USD, "4626", "Pyth"),
                    asset,
                    underlyingAsset,
                    USD,
                    erc4626Oracle,
                    pythOracle
                )
            );
        } else {
            primaryOracle = address(
                deployer.deploy_PythOracle(
                    buildPythOracleName(asset, USD),
                    pythAddress,
                    asset,
                    USD,
                    oracleOptions.pythPriceFeed,
                    oracleOptions.pythMaxStaleness,
                    oracleOptions.pythMaxConfWidth
                )
            );
        }

        address anchorOracle;
        if (shouldChain4626ForChainlink) {
            address chainlinkOracle = address(
                deployer.deploy_ChainlinkOracle(
                    buildChainlinkOracleName(underlyingAsset, USD),
                    underlyingAsset,
                    USD,
                    oracleOptions.chainlinkPriceFeed,
                    oracleOptions.chainlinkMaxStaleness
                )
            );
            address erc4626Oracle =
                address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, underlyingAsset), IERC4626(asset)));
            anchorOracle = address(
                deployer.deploy_CrossAdapter(
                    buildCrossAdapterName(asset, underlyingAsset, USD, "4626", "Chainlink"),
                    asset,
                    underlyingAsset,
                    USD,
                    erc4626Oracle,
                    chainlinkOracle
                )
            );
        } else {
            anchorOracle = address(
                deployer.deploy_ChainlinkOracle(
                    buildChainlinkOracleName(asset, USD),
                    asset,
                    USD,
                    oracleOptions.chainlinkPriceFeed,
                    oracleOptions.chainlinkMaxStaleness
                )
            );
        }

        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(asset, USD), primaryOracle, anchorOracle, oracleOptions.maxDivergence
            )
        );
        // Register the asset/USD anchored oracle if it's not already registered
        _registerAnchoredOracleWithEulerRouter(asset, anchoredOracle);
    }
}

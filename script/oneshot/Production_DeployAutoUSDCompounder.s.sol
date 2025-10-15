// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { CurveEMAOracle } from "euler-price-oracle/src/adapter/curve/CurveEMAOracle.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";

import { OraclePriceChecker } from "src/compounder/pricecheckers/OraclePriceChecker.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";

import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Production_DeployAutoUSDCompounder
 * @notice One-shot script to deploy AutoUSD Compounder and integrate it with coveUSD
 * @dev This script:
 *      1. Deploys AutopoolCompounder for autoUSD
 *      2. Deploys AutoPoolCompounderOracle for pricing
 *      3. Adds compounder to AssetRegistry
 *      4. Updates coveUSD basket bitflag
 *      5. Registers oracle in EulerRouter
 */
contract ProductionDeployAutoUSDCompounder is DeployScript, Constants, StdAssertions, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    // Deployment configuration
    uint256 public constant INITIAL_WEIGHT = 0; // Start with 0 weight, can be updated later
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500; // 5% max deviation for price checker

    // Oracle configuration for TOKE rewards
    address public constant CURVE_TOKE_ETH_POOL = 0xe0e970a99bc4F53804D8145beBBc7eBc9422Ba7F;
    address public constant CHAINLINK_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant CHAINLINK_MAX_STALENESS = 1 days;

    // Deployed contracts
    AutopoolCompounder public compounder;
    AutoPoolCompounderOracle public oracle;
    OraclePriceChecker public priceChecker;

    // Price oracles for TOKE rewards
    CurveEMAOracle public curveOracle;
    ChainlinkOracle public chainlinkOracle;
    CrossAdapter public crossAdapter;

    IMasterRegistry public masterRegistry;
    EulerRouter public eulerRouter;

    function _compounderName() internal pure returns (string memory) {
        return "Production_AutopoolCompounder_autoUSD";
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function deploy() public {
        deployer.setAutoBroadcast(true);

        console.log("\n==== Deploying AutoUSD Compounder ====");
        console.log("Deployer address:", msg.sender);

        // Get required addresses
        masterRegistry = IMasterRegistry(deployer.getAddress(buildMasterRegistryName()));
        require(address(masterRegistry) != address(0), "MasterRegistry not found");

        AssetRegistry assetRegistry = AssetRegistry(masterRegistry.resolveNameToLatestAddress("AssetRegistry"));
        require(address(assetRegistry) != address(0), "AssetRegistry not found");

        BasketManager basketManager = BasketManager(masterRegistry.resolveNameToLatestAddress("BasketManager"));
        require(address(basketManager) != address(0), "BasketManager not found");

        eulerRouter = EulerRouter(masterRegistry.resolveNameToLatestAddress("EulerRouter"));
        require(address(eulerRouter) != address(0), "EulerRouter not found");

        address basketTokenUSD = deployer.getAddress("Production_BasketToken_USD");
        require(basketTokenUSD != address(0), "BasketToken_USD not found");

        console.log("MasterRegistry:", address(masterRegistry));
        console.log("AssetRegistry:", address(assetRegistry));
        console.log("BasketManager:", address(basketManager));
        console.log("EulerRouter:", address(eulerRouter));
        console.log("BasketToken_USD:", basketTokenUSD);

        // Check autoUSD debt reporting before deployment
        IAutopool autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        uint256 oldestDebtReporting = autoUSD.oldestDebtReporting();
        console.log("\n==== AutoUSD Debt Reporting Check ====");
        console.log("Oldest debt reporting timestamp:", oldestDebtReporting);
        console.log("Current timestamp:", block.timestamp);
        if (oldestDebtReporting > 0) {
            uint256 debtAge = block.timestamp - oldestDebtReporting;
            console.log("Debt age (seconds):", debtAge);
            console.log("Debt age (hours):", debtAge / 3600);
            require(debtAge <= 24 hours, "Debt reporting is stale (>24 hours)");
        }

        // Deploy AutopoolCompounder
        console.log("\n==== Deploying AutopoolCompounder ====");
        compounder = deployer.deploy_AutopoolCompounder(
            _compounderName(), TOKEMAK_AUTOUSD, TOKEMAK_AUTOUSD_REWARDER, TOKEMAK_MILKMAN
        );
        console.log("AutopoolCompounder deployed at:", address(compounder));

        // Deploy AutoPoolCompounderOracle
        console.log("\n==== Deploying AutoPoolCompounderOracle ====");
        oracle = deployer.deploy_AutoPoolCompounderOracle(
            buildAutoPoolCompounderOracleName(address(compounder), ETH_USDC), IERC4626(address(compounder))
        );
        console.log("AutoPoolCompounderOracle deployed at:", address(oracle));

        // Deploy price oracles for TOKE rewards
        console.log("\n==== Deploying Price Oracles for TOKE Rewards ====");
        _deployPriceOracles();

        // Configure price checker for TOKE rewards
        console.log("\n==== Configuring Price Checker ====");
        vm.broadcast(msg.sender);
        compounder.updatePriceChecker(TOKEMAK_TOKE, address(priceChecker));
        console.log("Price checker configured for TOKE");

        // Set keeper role for the compounder (using PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT)
        console.log("\n==== Setting Keeper Role ====");
        vm.broadcast(msg.sender);
        ITokenizedStrategy(address(compounder)).setKeeper(PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT);
        console.log("Keeper set to:", PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT);

        // Add compounder to AssetRegistry
        console.log("\n==== Adding to Asset Registry ====");
        _addToAssetRegistry(assetRegistry);

        // Update basket bitflag to include compounder
        console.log("\n==== Updating Basket Bitflag ====");
        _updateBasketBitflag(basketManager, basketTokenUSD);

        // Deploy anchored oracle for compounder/USD
        console.log("\n==== Deploying Anchored Oracle ====");
        _deployAnchoredOracle();

        // Log deployed addresses for reference
        // These addresses can be manually added to deployment JSON if needed

        console.log("\n==== Deployment Complete ====");
        console.log("AutopoolCompounder:", address(compounder));
        console.log("AutoPoolCompounderOracle:", address(oracle));
        console.log("OraclePriceChecker:", address(priceChecker));

        // Run verification
        _verifyDeployment();
    }

    function _deployPriceOracles() private {
        // Deploy CurveEMAOracle for TOKE/ETH
        // Note: For TOKE/ETH pool, TOKE is coins[1] so priceOracleIndex = 0
        curveOracle = deployer.deploy_CurveEMAOracle(
            buildCurveEMAOracleName(TOKEMAK_TOKE, WETH),
            TOKEMAK_TOKE,
            CURVE_TOKE_ETH_POOL,
            0 // priceOracleIndex for TOKE (coins[1])
        );
        console.log("CurveEMAOracle (TOKE/ETH) deployed at:", address(curveOracle));

        // Deploy ChainlinkOracle for ETH/USD
        chainlinkOracle = deployer.deploy_ChainlinkOracle(
            buildChainlinkOracleName(WETH, USD), WETH, USD, CHAINLINK_ETH_USD_FEED, CHAINLINK_MAX_STALENESS
        );
        console.log("ChainlinkOracle (ETH/USD) deployed at:", address(chainlinkOracle));

        // Deploy CrossAdapter for TOKE -> ETH -> USD
        // CrossAdapter(base, cross, quote, oracleBaseCross, oracleCrossQuote)
        crossAdapter = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(TOKEMAK_TOKE, WETH, USD, "CurveEMA", "Chainlink"),
            TOKEMAK_TOKE, // base: TOKE
            WETH, // cross: ETH (intermediate asset)
            USD, // quote: USD
            address(curveOracle), // oracleBaseCross: TOKE/ETH
            address(chainlinkOracle) // oracleCrossQuote: ETH/USD
        );
        console.log("CrossAdapter (TOKE/USD) deployed at:", address(crossAdapter));

        // Deploy OraclePriceChecker
        priceChecker = deployer.deploy_OraclePriceChecker(
            "Production_OraclePriceChecker_TOKE", IPriceOracle(address(crossAdapter)), MAX_PRICE_DEVIATION_BPS
        );
        console.log("OraclePriceChecker deployed at:", address(priceChecker));
    }

    function _addToAssetRegistry(AssetRegistry assetRegistry) private {
        // Check if already added
        try assetRegistry.getAssetStatus(address(compounder)) returns (AssetRegistry.AssetStatus currentStatus) {
            if (currentStatus != AssetRegistry.AssetStatus.DISABLED) {
                console.log("Compounder already in AssetRegistry with status:", uint256(currentStatus));
                return;
            }
        } catch {
            // Not in registry, proceed to add
        }

        // Add to registry (requires MANAGER_ROLE)
        address manager = COVE_OPS_MULTISIG;
        vm.prank(manager);
        assetRegistry.addAsset(address(compounder));
        console.log("Compounder added to AssetRegistry");

        // Verify addition
        AssetRegistry.AssetStatus finalStatus = assetRegistry.getAssetStatus(address(compounder));
        require(finalStatus == AssetRegistry.AssetStatus.ENABLED, "Asset not enabled in registry");
    }

    function _updateBasketBitflag(BasketManager basketManager, address basketTokenUSD) private {
        // Get current basket assets
        address[] memory currentAssets = basketManager.basketAssets(basketTokenUSD);
        uint256 currentBitflag = BasketToken(basketTokenUSD).bitFlag();

        console.log("Current basket assets count:", currentAssets.length);
        console.log("Current bitflag:", currentBitflag);

        // Calculate new bitflag (add the bit for the new asset)
        uint256 newBitflag = currentBitflag | (1 << currentAssets.length);

        console.log("New basket assets count:", currentAssets.length + 1);
        console.log("New bitflag:", newBitflag);

        // Update basket (requires appropriate role)
        // Note: This requires a timelock proposal in production
        console.log("NOTE: Basket update requires timelock proposal in production");
        console.log("Call required: basketManager.updateBitFlag(basketToken, newBitflag)");
        console.log("  basketToken:", basketTokenUSD);
        console.log("  newBitflag:", newBitflag);
        console.log("  Compounder added at index:", currentAssets.length);

        address timelock = masterRegistry.resolveNameToLatestAddress("TimelockController");
        if (timelock == address(0)) {
            timelock = deployer.getAddress(buildTimelockControllerName());
        }
        console.log("Timelock controller (required caller):", timelock);

        vm.prank(timelock);
        basketManager.updateBitFlag(basketTokenUSD, newBitflag);
        console.log("Basket updated with new bitflag (pranked)");
    }

    function _registerOracle() private {
        // Register oracle for compounder/USD pair
        address governor = eulerRouter.governor();
        console.log("EulerRouter governor:", governor);

        // In production, this would need to go through governance
        // For testing, we'll use vm.prank
        vm.prank(governor);
        eulerRouter.govSetConfig(address(compounder), USD, address(oracle));

        console.log("Oracle registered for compounder/USD pair");

        // Verify registration
        address registeredOracle = eulerRouter.getConfiguredOracle(address(compounder), USD);
        require(registeredOracle == address(oracle), "Oracle not registered correctly");
    }

    function _deployAnchoredOracle() private {
        console.log("\n==== Creating Anchored Oracle for Compounder/USD ====");

        // Deploy CrossAdapter to convert from compounder/USDC to compounder/USD
        // Get USDC/USD oracle from EulerRouter
        address usdcOracle = eulerRouter.getConfiguredOracle(ETH_USDC, USD);
        require(usdcOracle != address(0), "USDC/USD oracle not found");

        // get primary USDC oracle and secondary USDC oracle from reading usdcOracle as AnchoredOracle
        address usdcPrimaryOracle = AnchoredOracle(usdcOracle).primaryOracle();
        address usdcAnchorOracle = AnchoredOracle(usdcOracle).anchorOracle();

        // Create CrossAdapter: compounder -> USDC (via oracle) -> USD (via USDC oracle)
        // CrossAdapter(base, cross, quote, oracleBaseCross, oracleCrossQuote)
        CrossAdapter compounderUsdAdapterPyth = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(address(compounder), ETH_USDC, USD, "AutoPoolCompounder", "Pyth"),
            address(compounder), // base: compounder
            ETH_USDC, // cross: USDC (intermediate asset)
            USD, // quote: USD
            address(oracle), // oracleBaseCross: compounder -> USDC
            usdcPrimaryOracle // oracleCrossQuote: USDC -> USD
        );
        console.log("Primary CrossAdapter (Compounder/USD) deployed at:", address(compounderUsdAdapterPyth));

        // Create CrossAdapter: compounder -> USDC (via oracle) -> USD (via USDC oracle)
        // CrossAdapter(base, cross, quote, oracleBaseCross, oracleCrossQuote)
        CrossAdapter compounderUsdAdapterChainlink = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(address(compounder), ETH_USDC, USD, "AutoPoolCompounder", "Chainlink"),
            address(compounder), // base: compounder
            ETH_USDC, // cross: USDC (intermediate asset)
            USD, // quote: USD
            address(oracle), // oracleBaseCross: compounder -> USDC
            usdcAnchorOracle // oracleCrossQuote: USDC -> USD
        );
        console.log("Secondary CrossAdapter (Compounder/USD) deployed at:", address(compounderUsdAdapterChainlink));

        // Deploy AnchoredOracle with the CrossAdapter as both primary and anchor (for simplicity)
        // In production, you might want different sources
        AnchoredOracle anchoredOracle = deployer.deploy_AnchoredOracle(
            buildAnchoredOracleName(address(compounder), USD),
            address(compounderUsdAdapterPyth), // primary oracle using pyth derived price
            address(compounderUsdAdapterChainlink), // anchor oracle using chainlink derived price
            0.01e18 // 1% max divergence
        );
        console.log("AnchoredOracle (Compounder/USD) deployed at:", address(anchoredOracle));

        // Register the anchored oracle instead of the raw oracle
        address governor = eulerRouter.governor();
        console.log("EulerRouter governor:", governor);

        // NOTE: On mainnet production this call MUST be executed by the EulerRouter governor multisig.
        //       vm.prank impersonates the governor for local fork simulations only.
        vm.prank(governor);
        eulerRouter.govSetConfig(address(compounder), USD, address(anchoredOracle));
        console.log("Anchored oracle registered for compounder/USD pair");
    }

    function _verifyDeployment() private view {
        console.log("\n==== Verifying Deployment ====");

        // Verify compounder configuration
        require(ITokenizedStrategy(address(compounder)).asset() == TOKEMAK_AUTOUSD, "Invalid autopool");
        require(address(compounder.rewarder()) == TOKEMAK_AUTOUSD_REWARDER, "Invalid rewarder");
        require(address(compounder.milkman()) == TOKEMAK_MILKMAN, "Invalid milkman");
        console.log(unicode"✅", " Compounder configuration verified");

        // Verify oracle configuration
        require(oracle.base() == address(compounder), "Invalid oracle base");
        require(oracle.quote() == ETH_USDC, "Invalid oracle quote");
        require(address(oracle.autopool()) == TOKEMAK_AUTOUSD, "Invalid oracle autopool");
        console.log(unicode"✅", " Oracle configuration verified");

        // Test oracle pricing (only if debt reporting is fresh)
        IAutopool autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        uint256 oldestDebt = autoUSD.oldestDebtReporting();
        if (oldestDebt > 0 && block.timestamp - oldestDebt <= 24 hours) {
            uint256 price = oracle.getQuote(1e18, address(compounder), ETH_USDC);
            console.log("Oracle price (1 compounder in USDC):", price);
            require(price > 0, "Invalid oracle price");
            console.log(unicode"✅", " Oracle pricing verified");
        } else {
            console.log(unicode"⚠️", " Oracle pricing not tested (stale debt reporting)");
        }

        console.log(unicode"\n✅", " All verifications passed!");
    }
}

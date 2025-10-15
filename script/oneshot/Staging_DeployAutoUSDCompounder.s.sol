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
 * @title Staging_DeployAutoUSDCompounder
 * @notice One-shot script to deploy the autoUSD Autopool compounder and wire it into the staging stack.
 * @dev This script mirrors the production deployment flow but uses staging registries and multisigs.
 *      It deploys the core contracts, registers required price oracles, and adds the compounder into
 *      the AssetRegistry. Calls that require multisig authority are executed via `vm.prank` for local
 *      forks; they MUST be submitted by the respective multisig on mainnet.
 */
contract StagingDeployAutoUSDCompounder is DeployScript, Constants, StdAssertions, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500; // 5%
    uint256 public constant CHAINLINK_MAX_STALENESS = 1 days;

    address public constant CURVE_TOKE_ETH_POOL = 0xe0e970a99bc4F53804D8145beBBc7eBc9422Ba7F;
    address public constant CHAINLINK_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    AutopoolCompounder public compounder;
    AutoPoolCompounderOracle public oracle;
    OraclePriceChecker public priceChecker;

    CurveEMAOracle public curveOracle;
    ChainlinkOracle public chainlinkOracle;
    CrossAdapter public crossAdapter;
    CrossAdapter public compounderUsdAdapterPyth;
    CrossAdapter public compounderUsdAdapterChainlink;
    AnchoredOracle public anchoredOracle;

    IMasterRegistry public masterRegistry;
    AssetRegistry public assetRegistry;
    BasketManager public basketManager;
    EulerRouter public eulerRouter;
    address public basketTokenStables;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function _compounderName() internal pure returns (string memory) {
        return "Staging_AutopoolCompounder_autoUSD";
    }

    function deploy() public {
        deployer.setAutoBroadcast(true);

        console.log("\n==== Staging AutoUSD Compounder Deployment ====");
        console.log("Deployer address:", msg.sender);

        masterRegistry = IMasterRegistry(deployer.getAddress(buildMasterRegistryName()));
        require(address(masterRegistry) != address(0), "MasterRegistry not found");

        assetRegistry = AssetRegistry(masterRegistry.resolveNameToLatestAddress("AssetRegistry"));
        require(address(assetRegistry) != address(0), "AssetRegistry not found");

        basketManager = BasketManager(masterRegistry.resolveNameToLatestAddress("BasketManager"));
        require(address(basketManager) != address(0), "BasketManager not found");

        eulerRouter = EulerRouter(masterRegistry.resolveNameToLatestAddress("EulerRouter"));
        require(address(eulerRouter) != address(0), "EulerRouter not found");

        basketTokenStables = masterRegistry.resolveNameToLatestAddress("BasketToken_Stables");
        if (basketTokenStables == address(0)) {
            basketTokenStables = deployer.getAddress(buildBasketTokenName("Stables"));
        }
        require(basketTokenStables != address(0), "BasketToken_Stables not found");

        console.log("MasterRegistry:", address(masterRegistry));
        console.log("AssetRegistry:", address(assetRegistry));
        console.log("BasketManager:", address(basketManager));
        console.log("EulerRouter:", address(eulerRouter));
        console.log("BasketToken_Stables:", basketTokenStables);

        _checkAutoUSDDebt();
        _deployCompounder();
        _deployCompounderOracle();
        _deployRewardOracles();
        _configureCompounder();
        _deployAnchoredOracle();

        // NOTE: On live network staging, these calls MUST be executed by the staging timelock/community multisig.
        _logBasketUpdate();
        _verifyDeployment();
        _addToAssetRegistry();
        _registerAnchoredOracle();
    }

    function _checkAutoUSDDebt() private view {
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
        } else {
            console.log("AutoUSD vault has no debt reporting history");
        }
    }

    function _deployCompounder() private {
        console.log("\n==== Deploying AutopoolCompounder ====");
        compounder = deployer.deploy_AutopoolCompounder(
            _compounderName(), TOKEMAK_AUTOUSD, TOKEMAK_AUTOUSD_REWARDER, TOKEMAK_MILKMAN
        );
        console.log("AutopoolCompounder deployed at:", address(compounder));
    }

    function _deployCompounderOracle() private {
        console.log("\n==== Deploying AutoPoolCompounderOracle ====");
        oracle = deployer.deploy_AutoPoolCompounderOracle(
            buildAutoPoolCompounderOracleName(address(compounder), ETH_USDC), IERC4626(address(compounder))
        );
        console.log("AutoPoolCompounderOracle deployed at:", address(oracle));
    }

    function _deployRewardOracles() private {
        console.log("\n==== Deploying Price Oracles for TOKE Rewards ====");
        curveOracle = deployer.deploy_CurveEMAOracle(
            buildCurveEMAOracleName(TOKEMAK_TOKE, WETH),
            TOKEMAK_TOKE,
            CURVE_TOKE_ETH_POOL,
            0 // priceOracleIndex for TOKE (coins[1])
        );
        console.log("CurveEMAOracle (TOKE/ETH) deployed at:", address(curveOracle));

        chainlinkOracle = deployer.deploy_ChainlinkOracle(
            buildChainlinkOracleName(WETH, USD), WETH, USD, CHAINLINK_ETH_USD_FEED, CHAINLINK_MAX_STALENESS
        );
        console.log("ChainlinkOracle (ETH/USD) deployed at:", address(chainlinkOracle));

        crossAdapter = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(TOKEMAK_TOKE, WETH, USD, "CurveEMA", "Chainlink"),
            TOKEMAK_TOKE,
            WETH,
            USD,
            address(curveOracle),
            address(chainlinkOracle)
        );
        console.log("CrossAdapter (TOKE/USD) deployed at:", address(crossAdapter));

        priceChecker = new OraclePriceChecker(IPriceOracle(address(crossAdapter)), MAX_PRICE_DEVIATION_BPS);
        deployer.save(
            "Staging_OraclePriceChecker_TOKE", address(priceChecker), "OraclePriceChecker.sol:OraclePriceChecker"
        );
        console.log("OraclePriceChecker deployed at:", address(priceChecker));
    }

    function _configureCompounder() private {
        console.log("\n==== Configuring Compounder ====");
        vm.broadcast(msg.sender);
        compounder.updatePriceChecker(TOKEMAK_TOKE, address(priceChecker));
        console.log("Price checker configured for TOKE");

        vm.broadcast(msg.sender);
        ITokenizedStrategy(address(compounder)).setKeeper(STAGING_COVE_SILVERBACK_AWS_ACCOUNT);
        console.log("Keeper set to:", STAGING_COVE_SILVERBACK_AWS_ACCOUNT);
    }

    function _addToAssetRegistry() private {
        AssetRegistry registry = assetRegistry;
        console.log("\n==== Adding Compounder to Asset Registry ====");
        try registry.getAssetStatus(address(compounder)) returns (AssetRegistry.AssetStatus currentStatus) {
            if (currentStatus != AssetRegistry.AssetStatus.DISABLED) {
                console.log("Compounder already registered with status:", uint256(currentStatus));
                return;
            }
        } catch {
            // asset not found, proceed to add
        }

        // NOTE: On mainnet staging this call MUST be executed by the staging ops multisig.
        //       vm.prank impersonates the multisig for local fork simulations only.
        vm.prank(COVE_STAGING_OPS_MULTISIG);
        registry.addAsset(address(compounder));
        console.log("Compounder added to AssetRegistry by staged ops multisig (pranked)");

        AssetRegistry.AssetStatus finalStatus = registry.getAssetStatus(address(compounder));
        require(finalStatus == AssetRegistry.AssetStatus.ENABLED, "Asset not enabled in registry");
    }

    function _logBasketUpdate() private {
        BasketManager manager = basketManager;
        console.log("\n==== Basket Update Reminder ====");
        address[] memory currentAssets = manager.basketAssets(basketTokenStables);
        uint256 currentBitflag = BasketToken(basketTokenStables).bitFlag();

        console.log("Current basket assets count:", currentAssets.length);
        console.log("Current bitflag:", currentBitflag);

        uint256 newBitflag = currentBitflag | (1 << currentAssets.length);
        console.log("Proposed new bitflag:", newBitflag);
        console.log("Compounder would be added at index:", currentAssets.length);
        console.log("NOTE: Submit basketManager.updateBitFlag via staging timelock/community multisig on mainnet.");

        address timelock = masterRegistry.resolveNameToLatestAddress("TimelockController");
        if (timelock == address(0)) {
            timelock = deployer.getAddress(buildTimelockControllerName());
        }
        console.log("Staging timelock controller (required caller):", timelock);

        vm.prank(timelock);
        manager.updateBitFlag(basketTokenStables, newBitflag);
        console.log("Basket updated with new bitflag (pranked)");
    }

    function _registerAnchoredOracle() private {
        EulerRouter router = eulerRouter;
        console.log("\n==== Registering Anchored Oracle in EulerRouter ====");

        require(address(anchoredOracle) != address(0), "Anchored oracle not deployed");

        address governor = router.governor();
        console.log("EulerRouter governor:", governor);

        // NOTE: On mainnet staging this call MUST be executed by the EulerRouter governor multisig.
        //       vm.prank impersonates the governor for local fork simulations only.
        vm.prank(governor);
        router.govSetConfig(address(compounder), USD, address(anchoredOracle));
        console.log("Anchored oracle registered for compounder/USD pair (pranked)");

        address registeredOracle = router.getConfiguredOracle(address(compounder), USD);
        require(registeredOracle == address(anchoredOracle), "Anchored oracle not registered correctly");

        console.log(unicode"\n✅ Staging AutoUSD Compounder deployment script completed");
    }

    function _deployAnchoredOracle() private {
        console.log("\n==== Deploying Anchored Oracle (Compounder/USD) ====");

        EulerRouter router = eulerRouter;
        address usdcOracle = router.getConfiguredOracle(ETH_USDC, USD);
        require(usdcOracle != address(0), "USDC/USD oracle not found");

        address usdcPrimaryOracle = AnchoredOracle(usdcOracle).primaryOracle();
        address usdcAnchorOracle = AnchoredOracle(usdcOracle).anchorOracle();

        compounderUsdAdapterPyth = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(address(compounder), ETH_USDC, USD, "AutoPoolCompounder", "Pyth"),
            address(compounder),
            ETH_USDC,
            USD,
            address(oracle),
            usdcPrimaryOracle
        );
        console.log("Primary CrossAdapter (Compounder/USD) deployed at:", address(compounderUsdAdapterPyth));

        compounderUsdAdapterChainlink = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(address(compounder), ETH_USDC, USD, "AutoPoolCompounder", "Chainlink"),
            address(compounder),
            ETH_USDC,
            USD,
            address(oracle),
            usdcAnchorOracle
        );
        console.log("Anchor CrossAdapter (Compounder/USD) deployed at:", address(compounderUsdAdapterChainlink));

        anchoredOracle = deployer.deploy_AnchoredOracle(
            buildAnchoredOracleName(address(compounder), USD),
            address(compounderUsdAdapterPyth),
            address(compounderUsdAdapterChainlink),
            0.01e18 // 1% max divergence
        );
        console.log("AnchoredOracle deployed at:", address(anchoredOracle));
        console.log("Anchored oracle registration scheduled in multisig section (no state change yet)");
    }

    function _verifyDeployment() private view {
        console.log("\n==== Verifying Deployment ====");

        require(ITokenizedStrategy(address(compounder)).asset() == TOKEMAK_AUTOUSD, "Invalid autopool");
        require(address(compounder.rewarder()) == TOKEMAK_AUTOUSD_REWARDER, "Invalid rewarder");
        require(address(compounder.milkman()) == TOKEMAK_MILKMAN, "Invalid milkman");
        console.log(unicode"✅", " Compounder configuration verified");

        require(oracle.base() == address(compounder), "Invalid oracle base");
        require(oracle.quote() == ETH_USDC, "Invalid oracle quote");
        require(address(oracle.autopool()) == TOKEMAK_AUTOUSD, "Invalid oracle autopool");
        console.log(unicode"✅", " AutoPoolCompounderOracle configuration verified");

        require(
            address(compounderUsdAdapterPyth) != address(0) && address(compounderUsdAdapterChainlink) != address(0),
            "Compounder/USD adapters not deployed"
        );
        require(address(anchoredOracle) != address(0), "Anchored oracle not deployed");
        console.log(unicode"✅", " Anchored oracle components deployed");

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

        console.log(unicode"\nℹ️ Pre-multisig verification complete; proceeding to simulated multisig steps");
    }
}

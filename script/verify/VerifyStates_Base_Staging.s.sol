// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";

import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

import { BuildDeploymentJsonNames } from "../utils/BuildDeploymentJsonNames.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract VerifyStatesBaseStaging is Script, Constants, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    Deployer public deployer;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function verifyDeployment() public {
        deployer = Deployer(msg.sender);
        console.log("===== Verifying Base Staging Deployment =====");

        // Verify core contracts deployment
        _verifyBasketManager();
        _verifyFeeCollector();
        _verifyAssetRegistry();
        _verifyStrategyRegistry();
        _verifyBasicRetryOperator();

        // Verify oracles
        _verifyOracles();

        // Verify strategy
        _verifyManagedWeightStrategy();

        // Verify basket token
        _verifyBasketToken();

        console.log("===== Base Staging Deployment Verification Complete =====");
    }

    function _verifyBasketManager() internal view {
        console.log("Verifying BasketManager...");
        address basketManager = deployer.getAddress(buildBasketManagerName());
        require(basketManager != address(0), "BasketManager not deployed");

        BasketManager bm = BasketManager(basketManager);

        // Verify roles were transferred (deployer should not have roles)
        require(!bm.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS), "BasketManager: Deployer still has admin role");
        require(bm.hasRole(DEFAULT_ADMIN_ROLE, BASE_STAGING_COMMUNITY_MULTISIG), "BasketManager: Admin role not set");
        require(bm.hasRole(MANAGER_ROLE, BASE_STAGING_OPS_MULTISIG), "BasketManager: Manager role not set");

        // Get timelock address and verify it has the role
        address timelockAddr = deployer.getAddress(buildTimelockControllerName());
        require(timelockAddr != address(0), "TimelockController not deployed");
        require(bm.hasRole(TIMELOCK_ROLE, timelockAddr), "BasketManager: Timelock role not set");

        // Verify fee collector is set
        require(address(bm.feeCollector()) != address(0), "BasketManager: FeeCollector not set");

        console.log("  [OK] BasketManager verified");
    }

    function _verifyFeeCollector() internal view {
        console.log("Verifying FeeCollector...");
        address feeCollector = deployer.getAddress(buildFeeCollectorName());
        require(feeCollector != address(0), "FeeCollector not deployed");

        FeeCollector fc = FeeCollector(feeCollector);

        // Verify admin role was transferred
        require(!fc.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS), "FeeCollector: Deployer still has admin role");
        require(fc.hasRole(DEFAULT_ADMIN_ROLE, BASE_STAGING_COMMUNITY_MULTISIG), "FeeCollector: Admin role not set");

        console.log("  [OK] FeeCollector verified");
    }

    function _verifyAssetRegistry() internal view {
        console.log("Verifying AssetRegistry...");
        address assetRegistry = deployer.getAddress(buildAssetRegistryName());
        require(assetRegistry != address(0), "AssetRegistry not deployed");

        AssetRegistry ar = AssetRegistry(assetRegistry);

        // Verify Base assets are registered
        require(ar.getAssetStatus(BASE_USDC) == AssetRegistry.AssetStatus.ENABLED, "AssetRegistry: USDC not enabled");
        require(
            ar.getAssetStatus(BASE_BASEUSD) == AssetRegistry.AssetStatus.ENABLED, "AssetRegistry: baseUSD not enabled"
        );
        require(
            ar.getAssetStatus(BASE_SUPERUSDC) == AssetRegistry.AssetStatus.ENABLED,
            "AssetRegistry: superUSDC not enabled"
        );
        require(
            ar.getAssetStatus(BASE_SPARKUSDC) == AssetRegistry.AssetStatus.ENABLED,
            "AssetRegistry: sparkUSDC not enabled"
        );

        console.log("  [OK] AssetRegistry verified");
    }

    function _verifyStrategyRegistry() internal view {
        console.log("Verifying StrategyRegistry...");
        address strategyRegistry = deployer.getAddress(buildStrategyRegistryName());
        require(strategyRegistry != address(0), "StrategyRegistry not deployed");

        StrategyRegistry sr = StrategyRegistry(strategyRegistry);

        // Verify strategy is registered
        address strategy = deployer.getAddress(buildManagedWeightStrategyName("Gauntlet V1 Base Staging"));
        require(strategy != address(0), "ManagedWeightStrategy not deployed");
        require(sr.hasRole(keccak256("WEIGHT_STRATEGY_ROLE"), strategy), "Strategy not registered");

        console.log("  [OK] StrategyRegistry verified");
    }

    function _verifyBasicRetryOperator() internal view {
        console.log("Verifying BasicRetryOperator...");
        address basicRetryOperator = deployer.getAddress(buildBasicRetryOperatorName());
        require(basicRetryOperator != address(0), "BasicRetryOperator not deployed");

        BasicRetryOperator bro = BasicRetryOperator(basicRetryOperator);

        // Verify admin role was transferred
        require(
            !bro.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS), "BasicRetryOperator: Deployer still has admin role"
        );
        require(
            bro.hasRole(DEFAULT_ADMIN_ROLE, BASE_STAGING_COMMUNITY_MULTISIG), "BasicRetryOperator: Admin role not set"
        );

        console.log("  [OK] BasicRetryOperator verified");
    }

    function _verifyOracles() internal view {
        console.log("Verifying Oracles...");

        // Verify USDC oracle
        address usdcOracle = deployer.getAddress(buildAnchoredOracleName(BASE_USDC, USD));
        require(usdcOracle != address(0), "USDC Anchored Oracle not deployed");

        // Verify baseUSD oracle
        address baseUsdOracle = deployer.getAddress(buildAnchoredOracleName(BASE_BASEUSD, USD));
        require(baseUsdOracle != address(0), "baseUSD Anchored Oracle not deployed");

        // Verify superUSDC oracle
        address superUsdcOracle = deployer.getAddress(buildAnchoredOracleName(BASE_SUPERUSDC, USD));
        require(superUsdcOracle != address(0), "superUSDC Anchored Oracle not deployed");

        // Verify sparkUSDC oracle
        address sparkUsdcOracle = deployer.getAddress(buildAnchoredOracleName(BASE_SPARKUSDC, USD));
        require(sparkUsdcOracle != address(0), "sparkUSDC Anchored Oracle not deployed");

        console.log("  [OK] All oracles verified");
    }

    function _verifyManagedWeightStrategy() internal view {
        console.log("Verifying ManagedWeightStrategy...");

        address strategy = deployer.getAddress(buildManagedWeightStrategyName("Gauntlet V1 Base Staging"));
        require(strategy != address(0), "ManagedWeightStrategy not deployed");

        ManagedWeightStrategy mws = ManagedWeightStrategy(strategy);

        // Verify roles were transferred
        require(!mws.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS), "Strategy: Deployer still has admin role");
        require(mws.hasRole(DEFAULT_ADMIN_ROLE, BASE_STAGING_COMMUNITY_MULTISIG), "Strategy: Admin role not set");
        require(mws.hasRole(MANAGER_ROLE, BASE_STAGING_AWS_KEEPER), "Strategy: Manager role not set to AWS Keeper");

        console.log("  [OK] ManagedWeightStrategy verified");
    }

    function _verifyBasketToken() internal view {
        console.log("Verifying BasketToken...");

        address basketToken = deployer.getAddress(buildBasketTokenName("bcoveUSD-staging"));
        require(basketToken != address(0), "BasketToken not deployed");

        BasketToken bt = BasketToken(basketToken);

        // Verify basic properties
        require(keccak256(bytes(bt.name())) == keccak256(bytes("Cove bcoveUSD-staging")), "BasketToken: Incorrect name");
        require(keccak256(bytes(bt.symbol())) == keccak256(bytes("bcoveUSDstg")), "BasketToken: Incorrect symbol");

        // Verify root asset
        require(bt.asset() == BASE_USDC, "BasketToken: Incorrect root asset");

        // Verify bitFlag includes all assets
        uint256 bitFlag = bt.bitFlag();
        AssetRegistry ar = AssetRegistry(deployer.getAddress(buildAssetRegistryName()));
        address[] memory assets = ar.getAssets(bitFlag);

        require(assets.length == 4, "BasketToken: Incorrect number of assets");

        // Verify all expected assets are included
        bool hasUsdc = false;
        bool hasBaseUsd = false;
        bool hasSuperUsdc = false;
        bool hasSparkUsdc = false;

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == BASE_USDC) hasUsdc = true;
            if (assets[i] == BASE_BASEUSD) hasBaseUsd = true;
            if (assets[i] == BASE_SUPERUSDC) hasSuperUsdc = true;
            if (assets[i] == BASE_SPARKUSDC) hasSparkUsdc = true;
        }

        require(hasUsdc, "BasketToken: USDC not in basket");
        require(hasBaseUsd, "BasketToken: baseUSD not in basket");
        require(hasSuperUsdc, "BasketToken: superUSDC not in basket");
        require(hasSparkUsdc, "BasketToken: sparkUSDC not in basket");

        // Verify management fee
        BasketManager bm = BasketManager(deployer.getAddress(buildBasketManagerName()));
        require(bm.managementFee(basketToken) == 100, "BasketToken: Incorrect management fee");

        // Verify fee collector split
        FeeCollector fc = FeeCollector(deployer.getAddress(buildFeeCollectorName()));
        require(fc.basketTokenSponsorSplits(basketToken) == 4000, "BasketToken: Incorrect sponsor split");

        console.log("  [OK] BasketToken verified");
    }
}

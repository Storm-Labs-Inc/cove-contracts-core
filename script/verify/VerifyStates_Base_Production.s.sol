// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { console } from "forge-std/console.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";

import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { VerifyStatesCommon } from "script/verify/utils/VerifyStates_Common.s.sol";

import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

contract VerifyStatesBaseProduction is DeployScript, VerifyStatesCommon {
    using DeployerFunctions for Deployer;
    using BasketManagerValidationLib for BasketManager;

    IMasterRegistry public masterRegistry;
    BasketManager public basketManager;
    AssetRegistry public assetRegistry;
    EulerRouter public eulerRouter;
    FeeCollector public feeCollector;
    StrategyRegistry public strategyRegistry;
    BasicRetryOperator public basicRetryOperator;
    TimelockController public timelockController;

    function _getDeployer() internal view override returns (Deployer) {
        return deployer;
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    // Due to using DeployScript, we use the deploy() function instead of run()
    function deploy() public virtual {
        verifyDeployment();
    }

    function verifyDeployment() public {
        console.log("===== Verifying Base Production Deployment =====");

        _resolveCoreContracts();

        _verifyBasketManager();
        _verifyFeeCollector();
        _verifyAssetRegistry();
        _verifyStrategyRegistry();
        _verifyBasicRetryOperator();

        _verifyOracles();

        _verifyManagedWeightStrategy();
        _verifyBasketToken();

        console.log("===== Base Production Deployment Verification Complete =====");
    }

    function _resolveCoreContracts() internal {
        address masterRegistryAddr = deployer.getAddress(buildMasterRegistryName());
        require(masterRegistryAddr != address(0), "MasterRegistry not deployed");
        masterRegistry = IMasterRegistry(masterRegistryAddr);
        console.log(
            string.concat("\nMasterRegistry: ", vm.toString(masterRegistryAddr), " (", buildMasterRegistryName(), ")")
        );

        basketManager = BasketManager(_resolveAndConfirm("BasketManager", buildBasketManagerName()));
        eulerRouter = EulerRouter(_resolveAndConfirm("EulerRouter", buildEulerRouterName()));
        assetRegistry = AssetRegistry(_resolveAndConfirm("AssetRegistry", buildAssetRegistryName()));
        feeCollector = FeeCollector(_resolveAndConfirm("FeeCollector", buildFeeCollectorName()));
        strategyRegistry = StrategyRegistry(_resolveAndConfirm("StrategyRegistry", buildStrategyRegistryName()));
        basicRetryOperator = BasicRetryOperator(_resolveAndConfirm("BasicRetryOperator", buildBasicRetryOperatorName()));

        address timelockAddr = masterRegistry.resolveNameToLatestAddress("TimelockController");
        address timelockFromDeployments = deployer.getAddress(buildTimelockControllerName());
        string memory matchStatus = timelockAddr == timelockFromDeployments ? unicode"✅" : unicode"❌";
        console.log(
            string.concat(
                "TimelockController: ",
                vm.toString(timelockAddr),
                " (registry) | ",
                vm.toString(timelockFromDeployments),
                " (deployments) ",
                matchStatus
            )
        );
        require(timelockAddr != address(0), "TimelockController address missing");
        timelockController = TimelockController(payable(timelockAddr));
    }

    function _resolveAndConfirm(
        string memory registryName,
        string memory deploymentName
    )
        internal
        view
        returns (address)
    {
        bytes32 registryKey = bytes32(bytes(registryName));
        address registryAddr = masterRegistry.resolveNameToLatestAddress(registryKey);
        require(registryAddr != address(0), string.concat(registryName, " not registered in MasterRegistry"));
        address deploymentAddr = deployer.getAddress(deploymentName);
        require(deploymentAddr != address(0), string.concat(deploymentName, " not found in deployments"));
        string memory status = registryAddr == deploymentAddr ? unicode"✅" : unicode"❌";
        console.log(
            string.concat(
                registryName,
                ": ",
                vm.toString(registryAddr),
                " (registry) | ",
                vm.toString(deploymentAddr),
                " (deployments) ",
                status
            )
        );
        require(
            registryAddr == deploymentAddr,
            string.concat(registryName, " mismatch between MasterRegistry and deployments")
        );
        return registryAddr;
    }

    function _verifyBasketManager() internal view {
        console.log("\nVerifying BasketManager roles and configuration...");

        _logRoleCheck(
            "DEFAULT_ADMIN_ROLE",
            basketManager.hasRole(DEFAULT_ADMIN_ROLE, BASE_COMMUNITY_MULTISIG),
            BASE_COMMUNITY_MULTISIG
        );
        _logRoleCheck("MANAGER_ROLE", basketManager.hasRole(MANAGER_ROLE, BASE_OPS_MULTISIG), BASE_OPS_MULTISIG);
        _logRoleCheck(
            "TIMELOCK_ROLE",
            basketManager.hasRole(TIMELOCK_ROLE, address(timelockController)),
            address(timelockController)
        );

        require(address(basketManager.feeCollector()) == address(feeCollector), "BasketManager: FeeCollector mismatch");
        console.log(string.concat("  FeeCollector configured: ", vm.toString(address(feeCollector)), unicode" ✅"));
    }

    function _verifyFeeCollector() internal view {
        console.log("\nVerifying FeeCollector roles...");
        _logRoleCheck(
            "DEFAULT_ADMIN_ROLE",
            feeCollector.hasRole(DEFAULT_ADMIN_ROLE, BASE_COMMUNITY_MULTISIG),
            BASE_COMMUNITY_MULTISIG
        );
    }

    function _verifyAssetRegistry() internal view {
        console.log("\nVerifying AssetRegistry contents...");

        _assertAssetEnabled("BASE_USDC", BASE_USDC);
        _assertAssetEnabled("BASE_SUPERUSDC", BASE_SUPERUSDC);
        _assertAssetEnabled("BASE_SPARKUSDC", BASE_SPARKUSDC);

        address[] memory allAssets = assetRegistry.getAllAssets();
        console.log(string.concat("  Total registered assets: ", vm.toString(allAssets.length)));
    }

    function _verifyStrategyRegistry() internal view {
        console.log("\nVerifying StrategyRegistry configuration...");

        bytes32 weightRole = keccak256("WEIGHT_STRATEGY_ROLE");
        address strategyAddr = deployer.getAddress(buildManagedWeightStrategyName("Gauntlet V1 Base"));
        require(strategyAddr != address(0), "ManagedWeightStrategy not deployed");
        require(strategyRegistry.hasRole(weightRole, strategyAddr), "StrategyRegistry: strategy not registered");

        console.log(
            string.concat(
                "  ManagedWeightStrategy registered: ",
                vm.toString(strategyAddr),
                " (",
                buildManagedWeightStrategyName("Gauntlet V1 Base"),
                ")"
            )
        );
    }

    function _verifyBasicRetryOperator() internal view {
        console.log("\nVerifying BasicRetryOperator roles...");
        _logRoleCheck(
            "DEFAULT_ADMIN_ROLE",
            basicRetryOperator.hasRole(DEFAULT_ADMIN_ROLE, BASE_COMMUNITY_MULTISIG),
            BASE_COMMUNITY_MULTISIG
        );
    }

    function _verifyOracles() internal {
        console.log("\nVerifying oracle configuration...");

        basketManager.testLib_validateConfiguredOracles();
        console.log(unicode"  ✓ BasketManager oracle configuration passes validation library checks");

        basketManager.testLib_updateOracleTimestamps();

        address[] memory assets = assetRegistry.getAllAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            _logOracleDetails(assets[i]);
        }
    }

    function _verifyManagedWeightStrategy() internal view {
        console.log("\nVerifying ManagedWeightStrategy permissions...");

        address strategyAddr = deployer.getAddress(buildManagedWeightStrategyName("Gauntlet V1 Base"));
        require(strategyAddr != address(0), "ManagedWeightStrategy not deployed");

        ManagedWeightStrategy mws = ManagedWeightStrategy(strategyAddr);

        _logRoleCheck(
            "DEFAULT_ADMIN_ROLE", mws.hasRole(DEFAULT_ADMIN_ROLE, BASE_COMMUNITY_MULTISIG), BASE_COMMUNITY_MULTISIG
        );
        _logRoleCheck("MANAGER_ROLE", mws.hasRole(MANAGER_ROLE, BASE_GAUNTLET_SPONSOR), BASE_GAUNTLET_SPONSOR);
        require(
            !mws.hasRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS),
            "ManagedWeightStrategy: deployer should not retain manager role"
        );
    }

    function _verifyBasketToken() internal view {
        console.log("\nVerifying BasketToken configuration...");

        address basketTokenAddr = deployer.getAddress(buildBasketTokenName("USD"));
        require(basketTokenAddr != address(0), "BasketToken not deployed");

        BasketToken basketToken = BasketToken(basketTokenAddr);

        console.log(string.concat("  BasketToken address: ", vm.toString(basketTokenAddr)));
        console.log(string.concat("  Name  : ", basketToken.name()));
        console.log(string.concat("  Symbol: ", basketToken.symbol()));

        require(basketToken.asset() == BASE_USDC, "BasketToken: incorrect root asset");

        uint64[] memory weights = basketToken.getTargetWeights();
        address[] memory assets = basketToken.getAssets();
        console.log(string.concat("  Assets in basket: ", vm.toString(assets.length)));

        for (uint256 i = 0; i < assets.length; i++) {
            console.log(
                string.concat(
                    "    - ",
                    _getSymbol(assets[i]),
                    " (",
                    vm.toString(assets[i]),
                    ") weight: ",
                    _formatEther(weights[i])
                )
            );
        }

        require(assets.length == 3, "BasketToken: expected three assets");
        require(_containsAsset(assets, BASE_USDC), "BasketToken: USDC missing");
        require(_containsAsset(assets, BASE_SUPERUSDC), "BasketToken: superUSDC missing");
        require(_containsAsset(assets, BASE_SPARKUSDC), "BasketToken: sparkUSDC missing");

        require(basketManager.managementFee(basketTokenAddr) == 100, "BasketToken: incorrect management fee");
        require(feeCollector.basketTokenSponsorSplits(basketTokenAddr) == 4000, "BasketToken: incorrect sponsor split");
    }

    function _logOracleDetails(address asset) internal view {
        address oracleAddr = eulerRouter.getConfiguredOracle(asset, USD);
        string memory symbol = _getSymbol(asset);

        if (oracleAddr == address(0)) {
            console.log(string.concat("  [WARN] No oracle configured for ", symbol, " (", vm.toString(asset), ")"));
            return;
        }

        string memory oracleName = _safeOracleName(oracleAddr);
        console.log(
            string.concat(
                "  Asset ",
                symbol,
                " (",
                vm.toString(asset),
                ") -> Oracle ",
                vm.toString(oracleAddr),
                " (",
                oracleName,
                ")"
            )
        );

        uint256 amount = _oneUnit(asset);
        _logPrice("    EulerRouter price", oracleAddr, amount, asset, true);

        if (_equals(oracleName, "AnchoredOracle")) {
            AnchoredOracle anchored = AnchoredOracle(oracleAddr);
            address primary = anchored.primaryOracle();
            address anchor = anchored.anchorOracle();

            console.log(
                string.concat("    Primary Oracle: ", vm.toString(primary), " (", _safeOracleName(primary), ")")
            );
            _printBaseAndQuote(primary, "      ");
            _logPrice("      Primary price", primary, amount, asset, false);

            console.log(string.concat("    Anchor Oracle : ", vm.toString(anchor), " (", _safeOracleName(anchor), ")"));
            _printBaseAndQuote(anchor, "      ");
            _logPrice("      Anchor price", anchor, amount, asset, false);
        } else {
            _printBaseAndQuote(oracleAddr, "    ");
        }

        console.log("    Oracle structure:");
        _traverseOracles(oracleAddr, "    ");
    }

    function _logRoleCheck(string memory roleName, bool condition, address expected) internal view {
        console.log(
            string.concat("  ", roleName, ": ", vm.toString(expected), condition ? unicode" ✅" : unicode" ❌")
        );
        require(condition, string.concat("Role check failed for ", roleName));
    }

    function _assertAssetEnabled(string memory label, address asset) internal view {
        require(
            assetRegistry.getAssetStatus(asset) == AssetRegistry.AssetStatus.ENABLED,
            string.concat("AssetRegistry: ", label, " not enabled")
        );
        console.log(string.concat("  ", label, " enabled: ", vm.toString(asset), unicode" ✅"));
    }

    function _containsAsset(address[] memory assets, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == target) {
                return true;
            }
        }
        return false;
    }

    function _logPrice(
        string memory label,
        address oracle,
        uint256 amount,
        address asset,
        bool useRouter
    )
        internal
        view
    {
        if (useRouter) {
            try eulerRouter.getQuote(amount, asset, USD) returns (uint256 quote) {
                console.log(string.concat(label, ": $", _formatEther(quote)));
            } catch {
                console.log(string.concat(label, ": <quote reverted>"));
            }
        } else {
            try IPriceOracle(oracle).getQuote(amount, asset, USD) returns (uint256 quote) {
                console.log(string.concat(label, ": $", _formatEther(quote)));
            } catch {
                console.log(string.concat(label, ": <quote reverted>"));
            }
        }
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _oneUnit(address asset) internal view returns (uint256) {
        try IERC20Metadata(asset).decimals() returns (uint8 decimals) {
            return 10 ** decimals;
        } catch {
            return 1e18;
        }
    }
}

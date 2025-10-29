// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";

import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";

import { DynamicSlippageChecker } from "src/deps/milkman/pricecheckers/DynamicSlippageChecker.sol";
import { UniV2ExpectedOutCalculator } from "src/deps/milkman/pricecheckers/UniV2ExpectedOutCalculator.sol";
import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { Constants } from "test/utils/Constants.t.sol";

abstract contract AutoUSDCompounderIntegrationBase is
    DeployScript,
    Constants,
    StdAssertions,
    BuildDeploymentJsonNames
{
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    string internal constant _COMPOUNDER_SUFFIX = "AutopoolCompounder_autoUSD";
    string internal constant _PRICE_CHECKER_SUFFIX = "DynamicSlippageChecker_TOKE-USDC";
    string internal constant _EXPECTED_OUT_SUFFIX = "UniV2ExpectedOutCalculator_SushiSwap";

    string internal constant _AUTOCOMPOUNDER_ARTIFACT = "AutopoolCompounder.sol:AutopoolCompounder";
    string internal constant _PRICE_CHECKER_ARTIFACT = "DynamicSlippageChecker.sol:DynamicSlippageChecker";
    string internal constant _EXPECTED_OUT_ARTIFACT = "UniV2ExpectedOutCalculator.sol:UniV2ExpectedOutCalculator";

    string internal constant _SHARED_PREFIX = "Production_";

    address internal constant _SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    AutopoolCompounder public compounder;
    AutoPoolCompounderOracle public compounderOracle;
    DynamicSlippageChecker public priceChecker;
    UniV2ExpectedOutCalculator public expectedOutCalculator;
    CrossAdapter public compounderUsdAdapterPrimary;
    CrossAdapter public compounderUsdAdapterAnchor;
    AnchoredOracle public anchoredOracle;

    IMasterRegistry public masterRegistry;
    AssetRegistry public assetRegistry;
    BasketManager public basketManager;
    EulerRouter public eulerRouter;
    address public basketToken;

    function integrate() public {
        deployer.setAutoBroadcast(true);

        console.log("\n==== AutoUSD Compounder Integration ====");
        console.log("Environment prefix:", _buildPrefix());

        _loadCoreContracts();
        _loadCompounder();
        _checkAutoUSDDebtFreshness();
        _ensureExpectedOutCalculator();
        _ensurePriceChecker();
        _configureCompounder();
        _ensureCompounderOracle();
        _deployAnchoredOracleStack();
        _addToAssetRegistry();
        _updateBasketBitflag();
        _registerAnchoredOracle();
        _verifyIntegration();

        console.log(unicode"\n✅ Integration complete. Compounder:", address(compounder));
    }

    function _sharedName(string memory suffix) internal pure returns (string memory) {
        return string.concat(_SHARED_PREFIX, suffix);
    }

    function _localName(string memory suffix) internal view returns (string memory) {
        return string.concat(_buildPrefix(), suffix);
    }

    function _loadCoreContracts() internal {
        masterRegistry = IMasterRegistry(deployer.getAddress(buildMasterRegistryName()));
        require(address(masterRegistry) != address(0), "MasterRegistry not found");

        address assetRegistryAddr = masterRegistry.resolveNameToLatestAddress("AssetRegistry");
        if (assetRegistryAddr == address(0)) {
            assetRegistryAddr = deployer.getAddress(buildAssetRegistryName());
        }
        require(assetRegistryAddr != address(0), "AssetRegistry not resolved");
        assetRegistry = AssetRegistry(assetRegistryAddr);

        address basketManagerAddr = masterRegistry.resolveNameToLatestAddress("BasketManager");
        if (basketManagerAddr == address(0)) {
            basketManagerAddr = deployer.getAddress(buildBasketManagerName());
        }
        require(basketManagerAddr != address(0), "BasketManager not resolved");
        basketManager = BasketManager(basketManagerAddr);

        address eulerRouterAddr = masterRegistry.resolveNameToLatestAddress("EulerRouter");
        if (eulerRouterAddr == address(0)) {
            eulerRouterAddr = deployer.getAddress(buildEulerRouterName());
        }
        require(eulerRouterAddr != address(0), "EulerRouter not resolved");
        eulerRouter = EulerRouter(eulerRouterAddr);

        basketToken = _resolveBasketToken();
        require(basketToken != address(0), "Basket token not found");

        console.log("MasterRegistry:", address(masterRegistry));
        console.log("AssetRegistry:", address(assetRegistry));
        console.log("BasketManager:", address(basketManager));
        console.log("EulerRouter:", address(eulerRouter));
        console.log("BasketToken target:", basketToken);
        console.log("SushiSwap Router:", _SUSHISWAP_ROUTER);
    }

    function _loadCompounder() internal {
        string memory localKey = _localName(_COMPOUNDER_SUFFIX);
        string memory sharedKey = _sharedName(_COMPOUNDER_SUFFIX);

        address compounderAddr = deployer.getAddress(localKey);
        if (compounderAddr == address(0)) {
            compounderAddr = deployer.getAddress(sharedKey);
            require(compounderAddr != address(0), "AutopoolCompounder not deployed");
            if (!_stringsEqual(localKey, sharedKey)) {
                deployer.save(localKey, compounderAddr, _AUTOCOMPOUNDER_ARTIFACT);
            }
        }

        compounder = AutopoolCompounder(compounderAddr);
        console.log("AutopoolCompounder:", compounderAddr);
    }

    function _checkAutoUSDDebtFreshness() internal view {
        IAutopool autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        uint256 oldestDebtReporting = autoUSD.oldestDebtReporting();
        console.log("\n==== AutoUSD Debt Reporting ====");
        console.log("Oldest debt timestamp:", oldestDebtReporting);
        console.log("Current timestamp:", block.timestamp);
        if (oldestDebtReporting > 0) {
            uint256 debtAge = block.timestamp - oldestDebtReporting;
            console.log("Debt age (hours):", debtAge / 1 hours);
            require(debtAge <= 24 hours, "AutoUSD debt reporting stale (>24h)");
        } else {
            console.log("AutoUSD has no debt reporting history");
        }
    }

    function _ensureExpectedOutCalculator() internal {
        string memory sharedKey = _sharedName(_EXPECTED_OUT_SUFFIX);
        string memory localKey = _localName(_EXPECTED_OUT_SUFFIX);

        address expectedOut = deployer.getAddress(sharedKey);
        if (expectedOut == address(0)) {
            expectedOut = address(
                deployer.deploy_UniV2ExpectedOutCalculator(sharedKey, "SushiSwap UniV2 ExpectedOut", _SUSHISWAP_ROUTER)
            );
        }

        if (!_stringsEqual(sharedKey, localKey) && deployer.getAddress(localKey) == address(0)) {
            deployer.save(localKey, expectedOut, _EXPECTED_OUT_ARTIFACT);
        }

        expectedOutCalculator = UniV2ExpectedOutCalculator(expectedOut);
        console.log("\n==== Price Checker Stack ====");
        console.log("UniV2ExpectedOutCalculator:", expectedOut);
    }

    function _ensurePriceChecker() internal {
        string memory sharedKey = _sharedName(_PRICE_CHECKER_SUFFIX);
        string memory localKey = _localName(_PRICE_CHECKER_SUFFIX);

        address checker = deployer.getAddress(sharedKey);
        if (checker == address(0)) {
            checker = address(
                deployer.deploy_DynamicSlippageChecker(
                    sharedKey, "SushiSwap TOKE->USDC Dynamic Slippage", address(expectedOutCalculator)
                )
            );
        }

        if (!_stringsEqual(sharedKey, localKey) && deployer.getAddress(localKey) == address(0)) {
            deployer.save(localKey, checker, _PRICE_CHECKER_ARTIFACT);
        }

        priceChecker = DynamicSlippageChecker(checker);
        console.log("DynamicSlippageChecker:", checker);
    }

    function _configureCompounder() internal {
        console.log("\n==== Configuring Compounder ====");

        vm.broadcast(msg.sender);
        compounder.updatePriceChecker(TOKEMAK_TOKE, address(priceChecker));
        console.log("Price checker set for TOKE via Milkman");

        vm.broadcast(msg.sender);
        ITokenizedStrategy(address(compounder)).setKeeper(_keeperAccount());
        console.log("Keeper assigned:", _keeperAccount());
        console.log("Max price deviation (bps):", compounder.maxPriceDeviationBps());
    }

    function _ensureCompounderOracle() internal {
        console.log("\n==== Compounder Oracle Deployment ====");
        string memory oracleName = buildAutoPoolCompounderOracleName(address(compounder), ETH_USDC);
        address oracleAddr = deployer.getAddress(oracleName);
        if (oracleAddr == address(0)) {
            compounderOracle = deployer.deploy_AutoPoolCompounderOracle(oracleName, IERC4626(address(compounder)));
            console.log("AutoPoolCompounderOracle deployed:", address(compounderOracle));
        } else {
            compounderOracle = AutoPoolCompounderOracle(oracleAddr);
            console.log("AutoPoolCompounderOracle reused:", oracleAddr);
        }
    }

    function _deployAnchoredOracleStack() internal {
        console.log("\n==== Anchored Oracle Stack ====");
        address usdcOracle = eulerRouter.getConfiguredOracle(ETH_USDC, USD);
        require(usdcOracle != address(0), "USDC/USD oracle missing");

        address usdcPrimaryOracle = AnchoredOracle(usdcOracle).primaryOracle();
        address usdcAnchorOracle = AnchoredOracle(usdcOracle).anchorOracle();

        string memory primaryName =
            buildCrossAdapterName(address(compounder), ETH_USDC, USD, "AutoPoolCompounder", "Pyth");
        address primaryAddr = deployer.getAddress(primaryName);
        if (primaryAddr == address(0)) {
            compounderUsdAdapterPrimary = deployer.deploy_CrossAdapter(
                primaryName, address(compounder), ETH_USDC, USD, address(compounderOracle), usdcPrimaryOracle
            );
            console.log("Primary CrossAdapter deployed:", address(compounderUsdAdapterPrimary));
        } else {
            compounderUsdAdapterPrimary = CrossAdapter(primaryAddr);
            console.log("Primary CrossAdapter reused:", primaryAddr);
        }

        string memory anchorName =
            buildCrossAdapterName(address(compounder), ETH_USDC, USD, "AutoPoolCompounder", "Chainlink");
        address anchorAddr = deployer.getAddress(anchorName);
        if (anchorAddr == address(0)) {
            compounderUsdAdapterAnchor = deployer.deploy_CrossAdapter(
                anchorName, address(compounder), ETH_USDC, USD, address(compounderOracle), usdcAnchorOracle
            );
            console.log("Anchor CrossAdapter deployed:", address(compounderUsdAdapterAnchor));
        } else {
            compounderUsdAdapterAnchor = CrossAdapter(anchorAddr);
            console.log("Anchor CrossAdapter reused:", anchorAddr);
        }

        string memory anchoredName = buildAnchoredOracleName(address(compounder), USD);
        address anchoredAddr = deployer.getAddress(anchoredName);
        if (anchoredAddr == address(0)) {
            anchoredOracle = deployer.deploy_AnchoredOracle(
                anchoredName, address(compounderUsdAdapterPrimary), address(compounderUsdAdapterAnchor), 0.01e18
            );
            console.log("AnchoredOracle deployed:", address(anchoredOracle));
        } else {
            anchoredOracle = AnchoredOracle(anchoredAddr);
            console.log("AnchoredOracle reused:", anchoredAddr);
        }
    }

    function _addToAssetRegistry() internal {
        console.log("\n==== Asset Registry Integration ====");
        try assetRegistry.getAssetStatus(address(compounder)) returns (AssetRegistry.AssetStatus currentStatus) {
            if (currentStatus != AssetRegistry.AssetStatus.DISABLED) {
                console.log("Compounder already enabled (status):", uint256(currentStatus));
                return;
            }
        } catch {
            // Asset not found, proceed with add
        }

        vm.prank(_opsMultisig());
        assetRegistry.addAsset(address(compounder));
        console.log("Compounder added via ops multisig:", _opsMultisig());

        AssetRegistry.AssetStatus finalStatus = assetRegistry.getAssetStatus(address(compounder));
        require(finalStatus == AssetRegistry.AssetStatus.ENABLED, "Asset registry enable failed");
    }

    function _updateBasketBitflag() internal {
        console.log("\n==== Basket Manager Update ====");
        address[] memory currentAssets = basketManager.basketAssets(basketToken);
        uint256 currentBitflag = BasketToken(basketToken).bitFlag();

        uint256 newBitflag = currentBitflag | (1 << currentAssets.length);
        console.log("Existing assets count:", currentAssets.length);
        console.log("Existing bitflag:", currentBitflag);
        console.log("New bitflag:", newBitflag);
        console.log("Compounder index:", currentAssets.length);

        address timelock = masterRegistry.resolveNameToLatestAddress("TimelockController");
        if (timelock == address(0)) {
            timelock = deployer.getAddress(buildTimelockControllerName());
        }
        require(timelock != address(0), "Timelock not resolved");

        vm.prank(timelock);
        basketManager.updateBitFlag(basketToken, newBitflag);
        console.log("Basket bitflag updated via timelock:", timelock);
    }

    function _registerAnchoredOracle() internal {
        console.log("\n==== Euler Router Registration ====");
        address governor = eulerRouter.governor();
        require(governor != address(0), "Euler governor not set");

        vm.prank(governor);
        eulerRouter.govSetConfig(address(compounder), USD, address(anchoredOracle));
        console.log("Anchored oracle registered with EulerRouter");

        address registered = eulerRouter.getConfiguredOracle(address(compounder), USD);
        require(registered == address(anchoredOracle), "Anchored oracle registration failed");
    }

    function _verifyIntegration() internal view {
        console.log("\n==== Post-Integration Verification ====");

        require(address(compounder.rewarder()) == TOKEMAK_AUTOUSD_REWARDER, "Invalid rewarder");
        require(address(compounder.milkman()) == TOKEMAK_MILKMAN, "Invalid Milkman");
        require(ITokenizedStrategy(address(compounder)).asset() == TOKEMAK_AUTOUSD, "Invalid AutoUSD vault");

        require(bytes(priceChecker.NAME()).length != 0, "Price checker not initialised");
        require(address(expectedOutCalculator.UNIV2_ROUTER()) == _SUSHISWAP_ROUTER, "Unexpected router");

        uint256 reportTimestamp = IAutopool(TOKEMAK_AUTOUSD).oldestDebtReporting();
        if (reportTimestamp > 0 && block.timestamp - reportTimestamp <= 24 hours) {
            uint256 quote = compounderOracle.getQuote(1e18, address(compounder), ETH_USDC);
            console.log("Compounder oracle quote (1 share -> USDC):", quote);
            require(quote > 0, "Oracle quote invalid");
        } else {
            console.log(unicode"⚠️ Oracle quote skipped due to stale debt reporting");
        }
    }

    function _resolveBasketToken() internal view returns (address) {
        bytes32 registryKey = _basketTokenRegistryKey();
        address basketFromRegistry = masterRegistry.resolveNameToLatestAddress(registryKey);
        if (basketFromRegistry != address(0)) {
            return basketFromRegistry;
        }
        return deployer.getAddress(buildBasketTokenName(_basketTokenLocalLabel()));
    }

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _keeperAccount() internal view virtual returns (address);

    function _opsMultisig() internal view virtual returns (address);

    function _basketTokenRegistryKey() internal view virtual returns (bytes32);

    function _basketTokenLocalLabel() internal view virtual returns (string memory);
}

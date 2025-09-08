// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { console } from "forge-std/console.sol";

import { IPriceOracleWithBaseAndQuote } from "src/interfaces/deps/IPriceOracleWithBaseAndQuote.sol";

import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";
import { CurveEMAOracleUnderlying } from "src/oracles/CurveEMAOracleUnderlying.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";

import { BasketToken } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";

import { FarmingPluginFactory } from "src/rewards/FarmingPluginFactory.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Constants } from "test/utils/Constants.t.sol";

// solhint-disable contract-name-capwords
contract VerifyStates_Production is DeployScript, Constants, BuildDeploymentJsonNames {
    using BasketManagerValidationLib for BasketManager;
    using Strings for string;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _getAddressOrRevert(string memory name) internal view returns (address addr) {
        addr = deployer.getAddress(name);
        require(addr != address(0), string.concat("Address for ", name, " not found"));
    }

    // Due to using DeployScript, we use the deploy() function instead of run()
    function deploy() public virtual {
        verifyDeployment();
    }

    function verifyDeployment() public {
        // Get the MasterRegistry address from environment
        address masterRegistryAddr = _getAddressOrRevert(buildMasterRegistryName());

        // Get the MasterRegistry contract
        IMasterRegistry masterRegistry = IMasterRegistry(masterRegistryAddr);
        console.log("\n=== Master Registry ===");
        console.log(
            string.concat("Address: ", vm.toString(address(masterRegistry)), " (", buildMasterRegistryName(), ")")
        );

        // Get the BasketManager address
        address basketManagerAddr = masterRegistry.resolveNameToLatestAddress("BasketManager");
        require(basketManagerAddr != address(0), "BasketManager not registered");
        console.log("\n=== Basket Manager ===");
        console.log("MR Registered Address:", basketManagerAddr);
        console.log(
            string.concat(
                "Matches deployment json: ",
                basketManagerAddr == deployer.getAddress(buildBasketManagerName()) ? unicode"✅" : unicode"❌",
                " (",
                buildBasketManagerName(),
                ")"
            )
        );
        BasketManager basketManager = BasketManager(basketManagerAddr);

        // Get the EulerRouter
        address eulerRouterAddr = masterRegistry.resolveNameToLatestAddress("EulerRouter");
        require(eulerRouterAddr != address(0), "EulerRouter not registered");
        console.log("\n=== Euler Router ===");
        console.log("MR Registered Address:", eulerRouterAddr);
        console.log(
            string.concat(
                "Matches deployment json: ",
                eulerRouterAddr == deployer.getAddress(buildEulerRouterName()) ? unicode"✅" : unicode"❌",
                " (",
                buildEulerRouterName(),
                ")"
            )
        );
        console.log(
            string.concat(
                "Matches basketManager.eulerRouter(): ",
                eulerRouterAddr == basketManager.eulerRouter() ? unicode"✅" : unicode"❌"
            )
        );
        EulerRouter eulerRouter = EulerRouter(eulerRouterAddr);

        // Get the AssetRegistry
        address assetRegistryAddr = masterRegistry.resolveNameToLatestAddress("AssetRegistry");
        require(assetRegistryAddr != address(0), "AssetRegistry not registered");
        console.log("\n=== Asset Registry ===");
        console.log("MR Registered Address:", assetRegistryAddr);
        console.log(
            string.concat(
                "Matches deployment json: ",
                assetRegistryAddr == deployer.getAddress(buildAssetRegistryName()) ? unicode"✅" : unicode"❌",
                " (",
                buildAssetRegistryName(),
                ")"
            )
        );
        console.log(
            string.concat(
                "Matches basketManager.assetRegistry(): ",
                assetRegistryAddr == basketManager.assetRegistry() ? unicode"✅" : unicode"❌"
            )
        );
        AssetRegistry assetRegistry = AssetRegistry(assetRegistryAddr);

        // Check for FeeCollector
        address feeCollectorAddr = masterRegistry.resolveNameToLatestAddress("FeeCollector");
        require(feeCollectorAddr != address(0), "FeeCollector not registered");
        console.log("\n=== Fee Collector ===");
        console.log("MR Registered Address:", feeCollectorAddr);
        console.log(
            string.concat(
                "Matches deployment json: ",
                feeCollectorAddr == deployer.getAddress(buildFeeCollectorName()) ? unicode"✅" : unicode"❌",
                " (",
                buildFeeCollectorName(),
                ")"
            )
        );
        console.log(
            string.concat(
                "Matches basketManager.feeCollector(): ",
                feeCollectorAddr == basketManager.feeCollector() ? unicode"✅" : unicode"❌"
            )
        );

        // Check for StrategyRegistry
        address strategyRegistryAddr = masterRegistry.resolveNameToLatestAddress("StrategyRegistry");
        require(strategyRegistryAddr != address(0), "StrategyRegistry not registered");
        console.log("\n=== Strategy Registry ===");
        console.log("MR Registered Address:", strategyRegistryAddr);
        console.log(
            string.concat(
                "Matches deployment json: ",
                strategyRegistryAddr == deployer.getAddress(buildStrategyRegistryName()) ? unicode"✅" : unicode"❌",
                " (",
                buildStrategyRegistryName(),
                ")"
            )
        );
        console.log(
            string.concat(
                "Matches basketManager.strategyRegistry(): ",
                strategyRegistryAddr == basketManager.strategyRegistry() ? unicode"✅" : unicode"❌"
            )
        );

        // Check for TokenSwapAdapter (CoWSwapAdapter)
        address tokenSwapAdapterAddr = masterRegistry.resolveNameToLatestAddress("CowSwapAdapter");
        require(tokenSwapAdapterAddr != address(0), "CowSwapAdapter not registered");
        console.log("\n=== CowSwapAdapter ===");
        console.log("MR Registered Address:", tokenSwapAdapterAddr);
        console.log(
            string.concat(
                "Matches deployment json: ",
                tokenSwapAdapterAddr == deployer.getAddress(buildCowSwapAdapterName()) ? unicode"✅" : unicode"❌",
                " (",
                buildCowSwapAdapterName(),
                ")"
            )
        );
        console.log(
            string.concat(
                "Matches basketManager.tokenSwapAdapter(): ",
                tokenSwapAdapterAddr == basketManager.tokenSwapAdapter() ? unicode"✅" : unicode"❌"
            )
        );

        // Validate all configured oracles
        console.log("\n=== Validating Oracle Configurations ===");
        basketManager.testLib_validateConfiguredOracles();
        console.log(unicode"✓ All oracle configurations are valid");

        // Get all basket tokens
        address[] memory baskets = basketManager.basketTokens();
        console.log("\n=== Analyzing Basket Tokens ===");
        console.log("Number of baskets:", baskets.length);

        // For each basket, get its assets and analyze oracle paths
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            address[] memory assets = basketManager.basketAssets(basket);
            string memory assetList = "[";
            for (uint256 j = 0; j < assets.length; j++) {
                if (j > 0) {
                    assetList = string.concat(assetList, ", ");
                }
                assetList = string.concat(assetList, _getSymbol(assets[j]));
            }
            assetList = string.concat(assetList, "]");

            console.log(
                string.concat("\nBasket ", vm.toString(i + 1), ": ", vm.toString(basket), " (", _getSymbol(basket), ")")
            );
            console.log("Number of assets:", assets.length);
            console.log("Assets:", assetList);
        }

        console.log("\n=== Analyzing Assets and Oracles ===");
        // Get the list of registered assets
        address[] memory allAssets = assetRegistry.getAllAssets();
        // Update oracle timestamps and check for prices (could be stale since last update)
        basketManager.testLib_updateOracleTimestamps();
        // For each asset, get and analyze its oracle path
        for (uint256 j = 0; j < allAssets.length; j++) {
            address asset = allAssets[j];
            address oracleAddr = eulerRouter.getConfiguredOracle(asset, USD);

            console.log(
                string.concat("\nAsset ", vm.toString(j + 1), ": ", vm.toString(asset), " (", _getSymbol(asset), ")")
            );
            string memory oracleName = IPriceOracle(oracleAddr).name();
            console.log(string.concat("Registered Oracle: ", vm.toString(oracleAddr), " (", oracleName, ")"));

            // Use single unit of asset to measure the price
            uint256 amount = 10 ** IERC20Metadata(asset).decimals();

            // Get primary and anchor oracles
            AnchoredOracle anchoredOracle = AnchoredOracle(oracleAddr);
            address primaryOracle = anchoredOracle.primaryOracle();
            address anchorOracle = anchoredOracle.anchorOracle();

            // Get prices from primary and anchor oracle prices
            uint256 primaryPrice = IPriceOracle(primaryOracle).getQuote(amount, asset, USD);
            uint256 anchorPrice = IPriceOracle(anchorOracle).getQuote(amount, asset, USD);

            console.log(string.concat("Primary Oracle Price: $", _formatEther(primaryPrice)));
            console.log(string.concat("Anchor Oracle Price : $", _formatEther(anchorPrice)));

            uint256 eulerRouterPrice = eulerRouter.getQuote(amount, asset, USD);
            console.log(string.concat("EulerRouter Price   : $", _formatEther(eulerRouterPrice)));

            // Print primary oracle details
            console.log("\nPrimary Oracle (Pyth sourced):", primaryOracle);
            _traverseOracles(primaryOracle, "");

            // Print anchor oracle details
            console.log("\nAnchor Oracle (Chainlink sourced):", anchorOracle);
            _traverseOracles(anchorOracle, "");
        }

        // Verify permissions
        _verifyPermissions();
    }

    /// @notice Traverses the oracle path recursively, printing details for each oracle encountered.
    /// @param oracle The address of the oracle to start traversal from.
    /// @param indent The indentation string to use for logging (e.g., "  ").
    function _traverseOracles(address oracle, string memory indent) internal view {
        string memory currentIndent = string.concat(indent, "  ");

        // Get name of the oracle
        string memory oracleName;
        try IPriceOracle(oracle).name() returns (string memory name) {
            oracleName = name;
        } catch {
            console.log(string.concat(currentIndent, unicode"❌ Oracle without name() function: ", vm.toString(oracle)));
            return;
        }

        console.log(string.concat(indent, "Oracle: ", vm.toString(oracle), " (", oracleName, ")"));

        if (oracleName.equal("PythOracle")) {
            _printPythOracleDetails(oracle, currentIndent);
        } else if (oracleName.equal("ChainlinkOracle")) {
            _printChainlinkOracleDetails(oracle, currentIndent);
        } else if (oracleName.equal("CrossAdapter")) {
            _printCrossAdapterDetails(oracle, currentIndent);
        } else if (oracleName.equal("ERC4626Oracle")) {
            _printERC4626OracleDetails(oracle, currentIndent);
        } else if (oracleName.equal("CurveEMAOracleUnderlying")) {
            _printCurveEMAOracleUnderlyingDetails(oracle, currentIndent);
        } else if (oracleName.equal("ChainedERC4626Oracle")) {
            _printChainedERC4626OracleDetails(oracle, currentIndent);
        } else if (oracleName.equal("AutoPoolCompounderOracle")) {
            _printAutoPoolCompounderOracleDetails(oracle, currentIndent);
        } else {
            console.log(string.concat(currentIndent, unicode"⚠️ Unknown Oracle Implementation: ", oracleName));
            // We cannot reliably determine base/quote for unknown types via IPriceOracle
        }
    }

    // =========================================================================
    // Internal Helper Functions for Oracle Details
    // =========================================================================

    function _printPythOracleDetails(address oracle, string memory indent) internal view {
        PythOracle pythOracle = PythOracle(oracle);
        bytes32 feedId = pythOracle.feedId();
        uint256 staleness = pythOracle.maxStaleness();

        console.log(string.concat(indent, "Type: Pyth"));
        console.log(string.concat(indent, "Feed ID: ", vm.toString(feedId)));
        console.log(string.concat(indent, "Max Staleness: ", vm.toString(staleness), "s"));
        string memory deploymentJsonName = buildPythOracleName(pythOracle.base(), pythOracle.quote());
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printChainlinkOracleDetails(address oracle, string memory indent) internal view {
        ChainlinkOracle clOracle = ChainlinkOracle(oracle);
        address feed = clOracle.feed();
        uint256 staleness = clOracle.maxStaleness();

        console.log(string.concat(indent, "Type: Chainlink"));
        console.log(string.concat(indent, "Feed: ", vm.toString(feed)));
        console.log(string.concat(indent, "Max Staleness: ", vm.toString(staleness), "s"));
        string memory deploymentJsonName = buildChainlinkOracleName(clOracle.base(), clOracle.quote());
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printCrossAdapterDetails(address oracle, string memory indent) internal view {
        CrossAdapter crossAdapter = CrossAdapter(oracle);
        address oracleBaseCross = crossAdapter.oracleBaseCross();
        address oracleCrossQuote = crossAdapter.oracleCrossQuote();

        console.log(string.concat(indent, "Type: CrossAdapter"));
        string memory deploymentJsonName = buildCrossAdapterName(
            crossAdapter.base(),
            crossAdapter.cross(),
            crossAdapter.quote(),
            _getCrossAdapterOracleType(IPriceOracle(crossAdapter.oracleBaseCross()).name()),
            _getCrossAdapterOracleType(IPriceOracle(crossAdapter.oracleCrossQuote()).name())
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        console.log(string.concat(indent, "Oracle Base Cross Path:"));
        _traverseOracles(oracleBaseCross, indent); // Recurse with same indent level for clarity
        console.log(string.concat(indent, "Oracle Cross Quote Path:"));
        _traverseOracles(oracleCrossQuote, indent); // Recurse with same indent level
    }

    function _printERC4626OracleDetails(address oracle, string memory indent) internal view {
        console.log(string.concat(indent, "Type: ERC4626Oracle"));
        string memory deploymentJsonName = buildERC4626OracleName(
            IPriceOracleWithBaseAndQuote(oracle).base(), IPriceOracleWithBaseAndQuote(oracle).quote()
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printCurveEMAOracleUnderlyingDetails(address oracle, string memory indent) internal view {
        CurveEMAOracleUnderlying curveOracle = CurveEMAOracleUnderlying(oracle);
        address pool = curveOracle.pool();

        console.log(string.concat(indent, "Type: CurveEMAOracleUnderlying"));
        console.log(string.concat(indent, "Curve Pool: ", vm.toString(pool)));
        string memory deploymentJsonName = buildCurveEMAOracleUnderlyingName(
            IPriceOracleWithBaseAndQuote(oracle).base(), IPriceOracleWithBaseAndQuote(oracle).quote()
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printChainedERC4626OracleDetails(address oracle, string memory indent) internal view {
        console.log(string.concat(indent, "Type: ChainedERC4626Oracle"));
        string memory deploymentJsonName = buildChainedERC4626OracleName(
            IPriceOracleWithBaseAndQuote(oracle).base(), IPriceOracleWithBaseAndQuote(oracle).quote()
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printAutoPoolCompounderOracleDetails(address oracle, string memory indent) internal view {
        console.log(string.concat(indent, "Type: AutoPoolCompounderOracle"));
        AutoPoolCompounderOracle apco = AutoPoolCompounderOracle(oracle);

        // Print the autopool address
        console.log(string.concat(indent, "Autopool: ", vm.toString(address(apco.autopool()))));

        // Print key vaults in the chain (compounder and autopool)
        // We know the chain is typically 2 vaults: compounder -> autopool
        address vault0 = apco.vaults(0); // Compounder
        address vault1 = apco.vaults(1); // Autopool

        console.log(string.concat(indent, "Vault Chain:"));
        console.log(string.concat(indent, "  Compounder (Vault 0): ", vm.toString(vault0)));
        console.log(string.concat(indent, "  Autopool (Vault 1): ", vm.toString(vault1)));

        string memory deploymentJsonName = buildAutoPoolCompounderOracleName(
            IPriceOracleWithBaseAndQuote(oracle).base(), IPriceOracleWithBaseAndQuote(oracle).quote()
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printBaseAndQuote(address oracle, string memory indent) internal view {
        if (IPriceOracleWithBaseAndQuote(oracle).base() != address(0)) {
            console.log(
                string.concat(
                    indent,
                    "Base Asset: ",
                    vm.toString(IPriceOracleWithBaseAndQuote(oracle).base()),
                    " (",
                    _getSymbol(IPriceOracleWithBaseAndQuote(oracle).base()),
                    ")"
                )
            );
        }
        if (IPriceOracleWithBaseAndQuote(oracle).quote() != address(0)) {
            console.log(
                string.concat(
                    indent,
                    "Quote Asset: ",
                    vm.toString(IPriceOracleWithBaseAndQuote(oracle).quote()),
                    " (",
                    _getSymbol(IPriceOracleWithBaseAndQuote(oracle).quote()),
                    ")"
                )
            );
        }
    }

    function _printDeploymentJsonMatch(
        address oracle,
        string memory indent,
        string memory deploymentJsonName
    )
        internal
        view
    {
        console.log(
            string.concat(
                indent,
                "Matches deployment json: ",
                oracle == deployer.getAddress(deploymentJsonName) ? unicode"✅" : unicode"❌",
                " (",
                deploymentJsonName,
                ")"
            )
        );
    }

    function _getCrossAdapterOracleType(string memory oracleName) internal pure returns (string memory) {
        if (oracleName.equal("PythOracle")) {
            return "Pyth";
        } else if (oracleName.equal("ChainlinkOracle")) {
            return "Chainlink";
        } else if (oracleName.equal("CrossAdapter")) {
            return "CrossAdapter";
        } else if (oracleName.equal("ERC4626Oracle")) {
            return "4626";
        } else if (oracleName.equal("CurveEMAOracleUnderlying")) {
            return "CurveEMAUnderlying";
        } else if (oracleName.equal("ChainedERC4626Oracle")) {
            return "ChainedERC4626";
        } else if (oracleName.equal("AutoPoolCompounderOracle")) {
            return "AutoPoolCompounder";
        } else {
            return "Unknown";
        }
    }

    /// @notice Helper function to get the symbol of an ERC20 token or return "USD".
    function _getSymbol(address asset) internal view returns (string memory) {
        if (asset == USD) {
            return "USD";
        }
        return IERC20Metadata(asset).symbol();
    }

    /// @notice Helper function to format a value in ether (1e18)
    function _formatEther(uint256 value) internal pure returns (string memory) {
        if (value >= 1e18) {
            uint256 whole = value / 1e18;
            uint256 fraction = value % 1e18;

            // Format the fractional part to ensure it has leading zeros
            string memory fractionStr = vm.toString(fraction);
            uint256 fractionLength = bytes(fractionStr).length;

            // Pad with leading zeros
            string memory padding = "";
            for (uint256 i = 0; i < 18 - fractionLength; i++) {
                padding = string.concat(padding, "0");
            }

            return string.concat(vm.toString(whole), ".", padding, fractionStr);
        } else {
            // Format the fractional part to ensure it has leading zeros
            string memory fractionStr = vm.toString(value);
            uint256 fractionLength = bytes(fractionStr).length;

            // Pad with leading zeros
            string memory padding = "";
            for (uint256 i = 0; i < 18 - fractionLength; i++) {
                padding = string.concat(padding, "0");
            }

            return string.concat("0.", padding, fractionStr);
        }
    }

    function _verifyPermissions() internal {
        console.log("\n\n=== Permission Checks ===");

        // --- MasterRegistry ---
        address masterRegistryAddr = _getAddressOrRevert(buildMasterRegistryName());
        _verifyMasterRegistryPermissions(IMasterRegistry(masterRegistryAddr));

        // --- BasketManager ---
        address basketManagerAddr = IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("BasketManager");
        _verifyBasketManagerPermissions(BasketManager(basketManagerAddr));

        // --- EulerRouter ---
        address eulerRouterAddr = IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("EulerRouter");
        _verifyEulerRouterPermissions(EulerRouter(eulerRouterAddr));

        // --- AssetRegistry ---
        address assetRegistryAddr = IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("AssetRegistry");
        _verifyAssetRegistryPermissions(AssetRegistry(assetRegistryAddr));

        // --- StrategyRegistry ---
        address strategyRegistryAddr =
            IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("StrategyRegistry");
        _verifyStrategyRegistryPermissions(StrategyRegistry(strategyRegistryAddr));

        // --- FeeCollector ---
        address feeCollectorAddr = IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("FeeCollector");
        _verifyFeeCollectorPermissions(FeeCollector(feeCollectorAddr), BasketManager(basketManagerAddr));

        // --- TimelockController ---
        address timelockControllerAddr =
            IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("TimelockController");
        if (timelockControllerAddr == address(0)) {
            console.log(unicode"❌ TimelockController not found in MasterRegistry. Fetching from deployments.json...");
            timelockControllerAddr = _getAddressOrRevert(buildTimelockControllerName());
        }
        _verifyTimelockControllerPermissions(TimelockController(payable(timelockControllerAddr)));

        // --- ManagedWeightStrategy Instances ---
        // Need to iterate or get known instances. For production, there's "Gauntlet V1"
        address gauntletStrategyAddr = _getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1"));
        _verifyManagedWeightStrategyPermissions(ManagedWeightStrategy(gauntletStrategyAddr), "Gauntlet V1");

        // --- BasketToken Instances ---
        BasketManager bm = BasketManager(basketManagerAddr);
        address[] memory basketTokens = bm.basketTokens();
        for (uint256 i = 0; i < basketTokens.length; i++) {
            _verifyBasketTokenPermissions(BasketToken(basketTokens[i]), bm);
        }

        // --- FarmingPluginFactory ---
        address farmingPluginFactoryAddr =
            IMasterRegistry(masterRegistryAddr).resolveNameToLatestAddress("FarmingPluginFactory");
        _verifyFarmingPluginFactoryPermissions(FarmingPluginFactory(farmingPluginFactoryAddr));
    }

    // Helper to print contract header
    function _printContractHeader(string memory contractName, address contractAddr) private pure {
        console.log(string.concat("\n--- ", contractName, " (", vm.toString(contractAddr), ") ---"));
    }

    // Helper to check and log a single address configuration
    function _checkAndLogAddress(
        string memory label,
        address actual,
        address expected,
        string memory expectedName
    )
        private
        pure
    {
        string memory checkMark = actual == expected ? unicode"✅" : unicode"❌";
        console.log(
            string.concat("  ", label, ": ", vm.toString(actual), " (Expected: ", expectedName, " ", checkMark, ")")
        );
    }

    function _checkAndLogRoleMembers(
        AccessControl target,
        bytes32 role,
        string memory roleName,
        address[] memory expectedMembers,
        string[] memory expectedMemberNames
    )
        private
        view
    {
        console.log(string.concat("  ", roleName, ":"));
        for (uint256 i = 0; i < expectedMembers.length; i++) {
            if (target.hasRole(role, expectedMembers[i])) {
                console.log(
                    string.concat(
                        "    - Member: ",
                        vm.toString(expectedMembers[i]),
                        " (Is ",
                        expectedMemberNames[i],
                        unicode" ✅ )"
                    )
                );
            } else {
                console.log(string.concat("    - NOT a Member: ", vm.toString(expectedMembers[i]), unicode" ❌"));
            }
        }
    }

    // Helper to check and log role members
    function _checkAndLogRoleMembersEnumerable(
        AccessControlEnumerable target,
        bytes32 role,
        string memory roleName,
        address[] memory expectedMembers,
        string[] memory expectedMemberNames
    )
        private
        view
    {
        console.log(string.concat("  ", roleName, ":"));
        uint256 memberCount = target.getRoleMemberCount(role);
        bool[] memory foundExpected = new bool[](expectedMembers.length);

        for (uint256 j = 0; j < memberCount; j++) {
            address member = target.getRoleMember(role, j);
            string memory memberMatchStatus = unicode" (Is unrecognized ⚠️)";
            for (uint256 k = 0; k < expectedMembers.length; k++) {
                if (member == expectedMembers[k]) {
                    memberMatchStatus = string.concat(" (Is ", expectedMemberNames[k], unicode" ✅ )");
                    foundExpected[k] = true;
                    break;
                }
            }
            console.log(string.concat("    - Member: ", vm.toString(member), memberMatchStatus));
        }

        for (uint256 k = 0; k < expectedMembers.length; k++) {
            require(
                foundExpected[k],
                string.concat(
                    "Expected member ",
                    expectedMemberNames[k],
                    " (",
                    vm.toString(expectedMembers[k]),
                    ") not found in role ",
                    roleName
                )
            );
            if (!foundExpected[k]) {
                console.log(
                    string.concat(
                        "    Missing expected member: ",
                        vm.toString(expectedMembers[k]),
                        " (",
                        expectedMemberNames[k],
                        unicode") ❌"
                    )
                );
            }
        }
        // Optionally, check if memberCount equals expectedMembers.length if the role should be exclusive
        // For now, just ensuring all expected members are present.
    }

    function _verifyMasterRegistryPermissions(IMasterRegistry target) private view {
        _printContractHeader("MasterRegistry", address(target));
        address[] memory expectedAdmins = new address[](1);
        expectedAdmins[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedAdminNames = new string[](1);
        expectedAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            AccessControlEnumerable(payable(address(target))),
            DEFAULT_ADMIN_ROLE,
            "DEFAULT_ADMIN_ROLE",
            expectedAdmins,
            expectedAdminNames
        );
    }

    function _verifyBasketManagerPermissions(BasketManager target) private view {
        _printContractHeader("BasketManager", address(target));

        address[] memory expectedDefaultAdmins = new address[](1);
        expectedDefaultAdmins[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedDefaultAdminNames = new string[](1);
        expectedDefaultAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", expectedDefaultAdmins, expectedDefaultAdminNames
        );

        address[] memory expectedManagers = new address[](1);
        expectedManagers[0] = COVE_OPS_MULTISIG;
        string[] memory expectedManagerNames = new string[](1);
        expectedManagerNames[0] = "COVE_OPS_MULTISIG";
        _checkAndLogRoleMembersEnumerable(target, MANAGER_ROLE, "MANAGER_ROLE", expectedManagers, expectedManagerNames);

        address[] memory expectedPausers = new address[](4);
        expectedPausers[0] = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        expectedPausers[1] = COVE_COMMUNITY_MULTISIG;
        expectedPausers[2] = COVE_OPS_MULTISIG;
        expectedPausers[3] = COVE_DEPLOYER_ADDRESS;
        string[] memory expectedPauserNames = new string[](4);
        expectedPauserNames[0] = "PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT";
        expectedPauserNames[1] = "COVE_COMMUNITY_MULTISIG";
        expectedPauserNames[2] = "COVE_OPS_MULTISIG";
        expectedPauserNames[3] = "COVE_DEPLOYER_ADDRESS";
        _checkAndLogRoleMembersEnumerable(target, PAUSER_ROLE, "PAUSER_ROLE", expectedPausers, expectedPauserNames);

        address[] memory expectedRebalanceProposers = new address[](1);
        expectedRebalanceProposers[0] = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        string[] memory expectedRebalanceProposerNames = new string[](1);
        expectedRebalanceProposerNames[0] = "PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT";
        _checkAndLogRoleMembersEnumerable(
            target,
            REBALANCE_PROPOSER_ROLE,
            "REBALANCE_PROPOSER_ROLE",
            expectedRebalanceProposers,
            expectedRebalanceProposerNames
        );
        _checkAndLogRoleMembersEnumerable(
            target,
            TOKENSWAP_PROPOSER_ROLE,
            "TOKENSWAP_PROPOSER_ROLE",
            expectedRebalanceProposers,
            expectedRebalanceProposerNames
        ); // Same as rebalance proposer
        _checkAndLogRoleMembersEnumerable(
            target,
            TOKENSWAP_EXECUTOR_ROLE,
            "TOKENSWAP_EXECUTOR_ROLE",
            expectedRebalanceProposers,
            expectedRebalanceProposerNames
        ); // Same as rebalance proposer

        address expectedTimelockAddr = _getAddressOrRevert(buildTimelockControllerName());
        address[] memory expectedTimelocks = new address[](1);
        expectedTimelocks[0] = expectedTimelockAddr;
        string[] memory expectedTimelockNames = new string[](1);
        expectedTimelockNames[0] = buildTimelockControllerName();
        _checkAndLogRoleMembersEnumerable(
            target, TIMELOCK_ROLE, "TIMELOCK_ROLE", expectedTimelocks, expectedTimelockNames
        );

        _checkAndLogAddress(
            "feeCollector()",
            target.feeCollector(),
            _getAddressOrRevert(buildFeeCollectorName()),
            buildFeeCollectorName()
        );
        _checkAndLogAddress(
            "tokenSwapAdapter()",
            target.tokenSwapAdapter(),
            _getAddressOrRevert(buildCowSwapAdapterName()),
            buildCowSwapAdapterName()
        );
        _checkAndLogAddress(
            "assetRegistry()",
            address(target.assetRegistry()),
            _getAddressOrRevert(buildAssetRegistryName()),
            buildAssetRegistryName()
        );
        _checkAndLogAddress(
            "strategyRegistry()",
            address(target.strategyRegistry()),
            _getAddressOrRevert(buildStrategyRegistryName()),
            buildStrategyRegistryName()
        );
        _checkAndLogAddress(
            "eulerRouter()",
            address(target.eulerRouter()),
            _getAddressOrRevert(buildEulerRouterName()),
            buildEulerRouterName()
        );
        console.log(string.concat("  swapFee(): ", vm.toString(target.swapFee())));
        console.log(string.concat("  retryLimit(): ", vm.toString(target.retryLimit())));
        console.log(string.concat("  stepDelay(): ", vm.toString(target.stepDelay())));
        console.log(string.concat("  slippageLimit(): ", vm.toString(target.slippageLimit())));
        console.log(string.concat("  weightDeviationLimit(): ", vm.toString(target.weightDeviationLimit())));
    }

    function _verifyEulerRouterPermissions(EulerRouter target) private view {
        _printContractHeader(buildEulerRouterName(), address(target));
        _checkAndLogAddress("governor()", target.governor(), COVE_COMMUNITY_MULTISIG, "COVE_COMMUNITY_MULTISIG");
    }

    function _verifyAssetRegistryPermissions(AssetRegistry target) private view {
        _printContractHeader(buildAssetRegistryName(), address(target));
        address[] memory expectedDefaultAdmins = new address[](1);
        expectedDefaultAdmins[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedDefaultAdminNames = new string[](1);
        expectedDefaultAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", expectedDefaultAdmins, expectedDefaultAdminNames
        );

        address[] memory expectedManagers = new address[](1);
        expectedManagers[0] = COVE_OPS_MULTISIG;
        string[] memory expectedManagerNames = new string[](1);
        expectedManagerNames[0] = "COVE_OPS_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, keccak256("MANAGER_ROLE"), "MANAGER_ROLE", expectedManagers, expectedManagerNames
        );
    }

    function _verifyStrategyRegistryPermissions(StrategyRegistry target) private view {
        _printContractHeader(buildStrategyRegistryName(), address(target));
        address[] memory expectedDefaultAdmins = new address[](1);
        expectedDefaultAdmins[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedDefaultAdminNames = new string[](1);
        expectedDefaultAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", expectedDefaultAdmins, expectedDefaultAdminNames
        );

        // Check known strategies have WEIGHT_STRATEGY_ROLE
        address gauntletStrategyAddr = _getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1"));
        address[] memory expectedStrategies = new address[](1);
        expectedStrategies[0] = gauntletStrategyAddr;
        string[] memory expectedStrategyNames = new string[](1);
        expectedStrategyNames[0] = buildManagedWeightStrategyName("Gauntlet V1");
        _checkAndLogRoleMembersEnumerable(
            target, keccak256("WEIGHT_STRATEGY_ROLE"), "WEIGHT_STRATEGY_ROLE", expectedStrategies, expectedStrategyNames
        );
    }

    function _verifyFeeCollectorPermissions(FeeCollector target, BasketManager bm) private view {
        _printContractHeader(buildFeeCollectorName(), address(target));
        address[] memory expectedDefaultAdmins = new address[](1);
        expectedDefaultAdmins[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedDefaultAdminNames = new string[](1);
        expectedDefaultAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", expectedDefaultAdmins, expectedDefaultAdminNames
        );
        _checkAndLogAddress(
            "protocolTreasury()", target.protocolTreasury(), COVE_COMMUNITY_MULTISIG, "COVE_COMMUNITY_MULTISIG"
        );

        // Check sponsor for deployed basket token (if any)
        address[] memory basketTokens = bm.basketTokens();
        if (basketTokens.length > 0) {
            for (uint256 i = 0; i < basketTokens.length; i++) {
                address basketToken = basketTokens[i];
                address expectedSponsor = SPONSOR_GAUNTLET;
                // This needs to be explicitly set in a deployment script for FeeCollector for a given basket.
                // The default if not set is address(0). For the "Stables" basket, let's assume it's set to OPS.
                _checkAndLogAddress(
                    string.concat("basketTokenSponsors(", vm.toString(basketToken), ")"),
                    target.basketTokenSponsors(basketToken),
                    expectedSponsor,
                    "GUANTLET MULTISIG (or as configured)"
                );
                // Sponsor split might also be default (0) or a configured value.
                console.log(
                    string.concat(
                        "  basketTokenSponsorSplits(",
                        vm.toString(basketToken),
                        "): ",
                        vm.toString(target.basketTokenSponsorSplits(basketToken))
                    )
                );
            }
        }
    }

    function _verifyTimelockControllerPermissions(TimelockController target) private view {
        _printContractHeader(buildTimelockControllerName(), address(target));

        address[] memory expectedProposers = new address[](1);
        expectedProposers[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedProposerNames = new string[](1);
        expectedProposerNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembers(
            AccessControl(payable(address(target))),
            target.PROPOSER_ROLE(),
            "PROPOSER_ROLE",
            expectedProposers,
            expectedProposerNames
        );

        // Expect the same proposers to be cancellers
        _checkAndLogRoleMembers(
            AccessControl(payable(address(target))),
            target.CANCELLER_ROLE(),
            "CANCELLER_ROLE",
            expectedProposers,
            expectedProposerNames
        );

        address[] memory expectedExecutors = new address[](1);
        expectedExecutors[0] = COVE_DEPLOYER_ADDRESS;
        string[] memory expectedExecutorNames = new string[](1);
        expectedExecutorNames[0] = "COVE_DEPLOYER_ADDRESS";
        _checkAndLogRoleMembers(
            AccessControl(payable(address(target))),
            target.EXECUTOR_ROLE(),
            "EXECUTOR_ROLE",
            expectedExecutors,
            expectedExecutorNames
        );

        // TIMELOCK_ADMIN_ROLE is the DEFAULT_ADMIN_ROLE for TimelockController
        address[] memory expectedTimelockAdmins = new address[](1);
        expectedTimelockAdmins[0] = address(target);
        string[] memory expectedTimelockAdminNames = new string[](1);
        expectedTimelockAdminNames[0] = "TimelockController (itself)";
        _checkAndLogRoleMembers(
            AccessControl(payable(address(target))),
            target.DEFAULT_ADMIN_ROLE(),
            "DEFAULT_ADMIN_ROLE",
            expectedTimelockAdmins,
            expectedTimelockAdminNames
        );
    }

    function _verifyManagedWeightStrategyPermissions(
        ManagedWeightStrategy target,
        string memory strategyName
    )
        private
    {
        _printContractHeader(string.concat("ManagedWeightStrategy: ", strategyName), address(target));
        address[] memory expectedDefaultAdmins = new address[](1);
        expectedDefaultAdmins[0] = COVE_COMMUNITY_MULTISIG; // After _cleanPermissions
        string[] memory expectedDefaultAdminNames = new string[](1);
        expectedDefaultAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", expectedDefaultAdmins, expectedDefaultAdminNames
        );

        // And admin (COVE_COMMUNITY_MULTISIG) is granted DEFAULT_ADMIN_ROLE for the strategy.
        // The deployer's DEFAULT_ADMIN_ROLE on strategy is revoked.
        // So, manager of strategy should be PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT.
        address[] memory expectedManagers = new address[](1);
        expectedManagers[0] = PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
        string[] memory expectedManagerNames = new string[](1);
        expectedManagerNames[0] = "PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT";
        _checkAndLogRoleMembersEnumerable(
            target, keccak256("MANAGER_ROLE"), "MANAGER_ROLE", expectedManagers, expectedManagerNames
        );
    }

    function _verifyBasketTokenPermissions(BasketToken target, BasketManager bm) private view {
        _printContractHeader(string.concat("BasketToken: ", target.name()), address(target));
        _checkAndLogAddress("basketManager()", target.basketManager(), address(bm), buildBasketManagerName());
        _checkAndLogAddress(
            "assetRegistry()", target.assetRegistry(), address(bm.assetRegistry()), buildAssetRegistryName()
        );
        _checkAndLogAddress(
            "strategy()",
            target.strategy(),
            _getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1")),
            buildManagedWeightStrategyName("Gauntlet V1")
        );
        console.log(
            string.concat(
                "  managementFee(): ", vm.toString(BasketManager(target.basketManager()).managementFee(address(target)))
            )
        );
    }

    function _verifyFarmingPluginFactoryPermissions(FarmingPluginFactory target) private view {
        _printContractHeader(buildFarmingPluginFactoryName(), address(target));
        address[] memory expectedDefaultAdmins = new address[](1);
        expectedDefaultAdmins[0] = COVE_COMMUNITY_MULTISIG;
        string[] memory expectedDefaultAdminNames = new string[](1);
        expectedDefaultAdminNames[0] = "COVE_COMMUNITY_MULTISIG";
        _checkAndLogRoleMembersEnumerable(
            target, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", expectedDefaultAdmins, expectedDefaultAdminNames
        );
        address[] memory expectedManagers = new address[](1);
        expectedManagers[0] = COVE_OPS_MULTISIG;
        string[] memory expectedManagerNames = new string[](1);
        expectedManagerNames[0] = "COVE_OPS_MULTISIG";
        _checkAndLogRoleMembersEnumerable(target, MANAGER_ROLE, "MANAGER_ROLE", expectedManagers, expectedManagerNames);
        _checkAndLogAddress(
            "defaultPluginOwner()", target.defaultPluginOwner(), COVE_COMMUNITY_MULTISIG, "COVE_COMMUNITY_MULTISIG"
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { console } from "forge-std/console.sol";

import { IPriceOracleWithBaseAndQuote } from "src/interfaces/deps/IPriceOracleWithBaseAndQuote.sol";
import { CurveEMAOracleUnderlying } from "src/oracles/CurveEMAOracleUnderlying.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Constants } from "test/utils/Constants.t.sol";

// solhint-disable contract-name-capwords
contract VerifyOracles_Staging is DeployScript, Constants, BuildDeploymentJsonNames {
    using BasketManagerValidationLib for BasketManager;
    using Strings for string;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function _getAddressOrRevert(string memory name) internal view returns (address addr) {
        addr = deployer.getAddress(name);
        require(addr != address(0), string.concat("Address for ", name, " not found"));
    }

    // Due to using DeployScript, we use the deploy() function instead of run()
    function deploy() external {
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
            uint256 eulerRouterPrice = eulerRouter.getQuote(amount, asset, USD);

            // Get primary and anchor oracles
            AnchoredOracle anchoredOracle = AnchoredOracle(oracleAddr);
            address primaryOracle = anchoredOracle.primaryOracle();
            address anchorOracle = anchoredOracle.anchorOracle();

            // Get prices from primary and anchor oracle prices
            uint256 primaryPrice = IPriceOracle(primaryOracle).getQuote(amount, asset, USD);
            uint256 anchorPrice = IPriceOracle(anchorOracle).getQuote(amount, asset, USD);

            console.log(string.concat("EulerRouter Price   : $", _formatEther(eulerRouterPrice)));
            console.log(string.concat("Primary Oracle Price: $", _formatEther(primaryPrice)));
            console.log(string.concat("Anchor Oracle Price : $", _formatEther(anchorPrice)));

            // Print primary oracle details
            console.log("\nPrimary Oracle (Pyth sourced):", primaryOracle);
            _traverseOracles(primaryOracle, "");

            // Print anchor oracle details
            console.log("\nAnchor Oracle (Chainlink sourced):", anchorOracle);
            _traverseOracles(anchorOracle, "");
        }
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
}

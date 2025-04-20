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
import { CurveEMAOracleUnderlying } from "src/oracles/CurveEMAOracleUnderlying.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Constants } from "test/utils/Constants.t.sol";

interface IPriceOracleWithBaseAndQuote is IPriceOracle {
    function base() external view returns (address);
    function quote() external view returns (address);
}

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
    function deploy() external view {
        // Get the MasterRegistry address from environment
        address masterRegistryAddr = _getAddressOrRevert(buildMasterRegistryName());

        // Get the MasterRegistry contract
        IMasterRegistry masterRegistry = IMasterRegistry(masterRegistryAddr);
        console.log("\n=== Master Registry ===");
        console.log("Address:", address(masterRegistry));

        // Get the BasketManager address
        address basketManagerAddr = masterRegistry.resolveNameToLatestAddress("BasketManager");
        require(basketManagerAddr != address(0), "BasketManager not registered");
        console.log("\n=== Basket Manager ===");
        console.log("Address:", basketManagerAddr);
        BasketManager basketManager = BasketManager(basketManagerAddr);

        // Get the EulerRouter
        address eulerRouterAddr = masterRegistry.resolveNameToLatestAddress("EulerRouter");
        require(eulerRouterAddr != address(0), "EulerRouter not registered");
        require(eulerRouterAddr == basketManager.eulerRouter(), "EulerRouter address mismatch");
        console.log("\n=== Euler Router ===");
        console.log("Address:", eulerRouterAddr);
        EulerRouter eulerRouter = EulerRouter(eulerRouterAddr);

        // Get the AssetRegistry
        address assetRegistryAddr = masterRegistry.resolveNameToLatestAddress("AssetRegistry");
        require(assetRegistryAddr != address(0), "AssetRegistry not registered");
        require(assetRegistryAddr == basketManager.assetRegistry(), "AssetRegistry address mismatch");
        console.log("\n=== Asset Registry ===");
        console.log("Address:", assetRegistryAddr);
        AssetRegistry assetRegistry = AssetRegistry(assetRegistryAddr);

        // Validate all configured oracles
        console.log("\n=== Validating Oracle Configurations ===");
        basketManager.testLib_validateConfiguredOracles();
        console.log(unicode"✓ All oracle configurations are valid");

        // Get all basket tokens
        address[] memory baskets = basketManager.basketTokens();
        console.log("\n=== Analyzing Oracle Paths ===");
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

        // Get the list of registered assets
        address[] memory allAssets = assetRegistry.getAllAssets();

        // For each asset, get and analyze its oracle path
        for (uint256 j = 0; j < allAssets.length; j++) {
            address asset = allAssets[j];
            address oracleAddr = eulerRouter.getConfiguredOracle(asset, USD);

            console.log(
                string.concat(
                    "\nAsset ", vm.toString(j + 1), ": ", vm.toString(asset), " (", IERC20Metadata(asset).symbol(), ")"
                )
            );
            string memory oracleName = IPriceOracle(oracleAddr).name();
            console.log(string.concat("Registered Oracle: ", vm.toString(oracleAddr), " (", oracleName, ")"));

            // Get primary and anchor oracles
            AnchoredOracle anchoredOracle = AnchoredOracle(oracleAddr);
            address primaryOracle = anchoredOracle.primaryOracle();
            address anchorOracle = anchoredOracle.anchorOracle();

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
            console.log(string.concat(currentIndent, unicode"⚠️ Unknown Oracle Type at Address: ", vm.toString(oracle)));
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
        _printBaseAndQuote(oracle, indent);
    }

    function _printChainlinkOracleDetails(address oracle, string memory indent) internal view {
        ChainlinkOracle clOracle = ChainlinkOracle(oracle);
        address feed = clOracle.feed();
        uint256 staleness = clOracle.maxStaleness();

        console.log(string.concat(indent, "Type: Chainlink"));
        console.log(string.concat(indent, "Feed: ", vm.toString(feed)));
        console.log(string.concat(indent, "Max Staleness: ", vm.toString(staleness), "s"));
        _printBaseAndQuote(oracle, indent);
    }

    function _printCrossAdapterDetails(address oracle, string memory indent) internal view {
        CrossAdapter crossAdapter = CrossAdapter(oracle);
        address oracleBaseCross = crossAdapter.oracleBaseCross();
        address oracleCrossQuote = crossAdapter.oracleCrossQuote();

        console.log(string.concat(indent, "Type: CrossAdapter"));
        console.log(string.concat(indent, "Oracle Base Cross Path:"));
        _traverseOracles(oracleBaseCross, indent); // Recurse with same indent level for clarity
        console.log(string.concat(indent, "Oracle Cross Quote Path:"));
        _traverseOracles(oracleCrossQuote, indent); // Recurse with same indent level
    }

    function _printERC4626OracleDetails(address oracle, string memory indent) internal view {
        console.log(string.concat(indent, "Type: ERC4626Oracle"));
        _printBaseAndQuote(oracle, indent);
    }

    function _printCurveEMAOracleUnderlyingDetails(address oracle, string memory indent) internal view {
        CurveEMAOracleUnderlying curveOracle = CurveEMAOracleUnderlying(oracle);
        address pool = curveOracle.pool();

        console.log(string.concat(indent, "Type: CurveEMAOracleUnderlying"));
        console.log(string.concat(indent, "Curve Pool: ", vm.toString(pool)));
        _printBaseAndQuote(oracle, indent);
    }

    function _printChainedERC4626OracleDetails(address oracle, string memory indent) internal view {
        console.log(string.concat(indent, "Type: ChainedERC4626Oracle"));
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

    /// @notice Helper function to get the symbol of an ERC20 token or return "USD".
    function _getSymbol(address asset) internal view returns (string memory) {
        if (asset == USD) {
            return "USD";
        }
        return IERC20Metadata(asset).symbol();
    }
}

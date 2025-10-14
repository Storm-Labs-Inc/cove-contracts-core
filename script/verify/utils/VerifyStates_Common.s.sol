// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { console } from "forge-std/console.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";

import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";
import { IPriceOracleWithBaseAndQuote } from "src/interfaces/deps/IPriceOracleWithBaseAndQuote.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";
import { AutopoolOracle } from "src/oracles/AutopoolOracle.sol";
import { CurveEMAOracleUnderlying } from "src/oracles/CurveEMAOracleUnderlying.sol";

import { Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { Constants } from "test/utils/Constants.t.sol";

abstract contract VerifyStatesCommon is Constants, BuildDeploymentJsonNames {
    using Strings for string;

    function _getDeployer() internal view virtual returns (Deployer);

    function _traverseOracles(address oracle, string memory indent) internal view {
        string memory currentIndent = string.concat(indent, "  ");

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
        } else if (oracleName.equal("AutopoolOracle")) {
            _printAutopoolOracleDetails(oracle, currentIndent);
        } else if (oracleName.equal("AnchoredOracle")) {
            _printAnchoredOracleDetails(oracle, currentIndent);
        } else {
            console.log(string.concat(currentIndent, unicode"⚠️ Unknown Oracle Implementation: ", oracleName));
        }
    }

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
            _getCrossAdapterOracleType(_safeOracleName(oracleBaseCross)),
            _getCrossAdapterOracleType(_safeOracleName(oracleCrossQuote))
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        console.log(string.concat(indent, "Oracle Base Cross Path:"));
        _traverseOracles(oracleBaseCross, indent);
        console.log(string.concat(indent, "Oracle Cross Quote Path:"));
        _traverseOracles(oracleCrossQuote, indent);
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
        console.log(string.concat(indent, "Autopool: ", vm.toString(address(apco.autopool()))));

        address vault0 = apco.vaults(0);
        address vault1 = apco.vaults(1);

        console.log(string.concat(indent, "Vault Chain:"));
        console.log(string.concat(indent, "  Compounder (Vault 0): ", vm.toString(vault0)));
        console.log(string.concat(indent, "  Autopool (Vault 1): ", vm.toString(vault1)));

        string memory deploymentJsonName = buildAutoPoolCompounderOracleName(
            IPriceOracleWithBaseAndQuote(oracle).base(), IPriceOracleWithBaseAndQuote(oracle).quote()
        );
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printAutopoolOracleDetails(address oracle, string memory indent) internal view {
        console.log(string.concat(indent, "Type: AutopoolOracle"));
        AutopoolOracle autoOracle = AutopoolOracle(oracle);
        console.log(string.concat(indent, "Autopool: ", vm.toString(address(autoOracle.autopool()))));
        string memory deploymentJsonName = buildAutopoolOracleName(autoOracle.base(), autoOracle.quote());
        _printDeploymentJsonMatch(oracle, indent, deploymentJsonName);
        _printBaseAndQuote(oracle, indent);
    }

    function _printAnchoredOracleDetails(address oracle, string memory indent) internal view {
        AnchoredOracle anchored = AnchoredOracle(oracle);
        console.log(string.concat(indent, "Type: AnchoredOracle"));
        _printBaseAndQuote(oracle, indent);
        console.log(string.concat(indent, "Primary Oracle:"));
        _traverseOracles(anchored.primaryOracle(), indent);
        console.log(string.concat(indent, "Anchor Oracle:"));
        _traverseOracles(anchored.anchorOracle(), indent);
    }

    function _printDeploymentJsonMatch(
        address oracle,
        string memory indent,
        string memory deploymentJsonName
    )
        internal
        view
    {
        Deployer deployer_ = _getDeployer();
        console.log(
            string.concat(
                indent,
                "Matches deployment json: ",
                oracle == deployer_.getAddress(deploymentJsonName) ? unicode"✅" : unicode"❌",
                " (",
                deploymentJsonName,
                ")"
            )
        );
    }

    function _printBaseAndQuote(address oracle, string memory indent) internal view {
        try IPriceOracleWithBaseAndQuote(oracle).base() returns (address baseAsset) {
            if (baseAsset != address(0)) {
                console.log(
                    string.concat(indent, "Base Asset : ", vm.toString(baseAsset), " (", _getSymbol(baseAsset), ")")
                );
            }
        } catch { }

        try IPriceOracleWithBaseAndQuote(oracle).quote() returns (address quoteAsset) {
            if (quoteAsset != address(0)) {
                console.log(
                    string.concat(indent, "Quote Asset: ", vm.toString(quoteAsset), " (", _getSymbol(quoteAsset), ")")
                );
            }
        } catch { }
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
        } else if (oracleName.equal("AutopoolOracle")) {
            return "Autopool";
        } else if (oracleName.equal("AutoPoolCompounderOracle")) {
            return "AutoPoolCompounder";
        } else if (oracleName.equal("AnchoredOracle")) {
            return "Anchored";
        } else {
            return "Unknown";
        }
    }

    function _safeOracleName(address oracle) internal view returns (string memory) {
        if (oracle == address(0)) {
            return "";
        }
        try IPriceOracle(oracle).name() returns (string memory name) {
            return name;
        } catch {
            return "";
        }
    }

    function _getSymbol(address asset) internal view returns (string memory) {
        if (asset == USD) {
            return "USD";
        }
        try IERC20Metadata(asset).symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            return "???";
        }
    }

    function _formatEther(uint256 value) internal view returns (string memory) {
        if (value == 0) {
            return "0";
        }
        if (value >= 1e18) {
            uint256 whole = value / 1e18;
            uint256 fraction = value % 1e18;
            return string.concat(vm.toString(whole), ".", _formatFraction(fraction));
        }
        return string.concat("0.", _formatFraction(value));
    }

    function _formatFraction(uint256 fraction) private view returns (string memory) {
        string memory fractionStr = vm.toString(fraction);
        uint256 fractionLength = bytes(fractionStr).length;
        if (fractionLength >= 18) {
            return fractionStr;
        }
        string memory padding = "";
        for (uint256 i = fractionLength; i < 18; i++) {
            padding = string.concat(padding, "0");
        }
        return string.concat(padding, fractionStr);
    }
}

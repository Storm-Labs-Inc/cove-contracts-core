// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Constants } from "test/utils/Constants.t.sol";

/// @title BuildDeploymentJsonNames
/// @notice Utility contract for building deployment json names
/// @dev The naming format is as follows:
/// <prefix><contract name>_<description>
/// <prefix> is determined by the DeployScript
/// <contract name> is the name of the contract
/// <description> is a description of the contract, mostly derived from the constructor arguments
/// Examples:
/// - Staging_AnchoredOracle_ETH-USD
/// - Staging_FarmingPlugin_stgUSD_ERC20MRewards
/// - Test_AssetRegistry
abstract contract BuildDeploymentJsonNames is Constants {
    /// @dev Implement this function to return the prefix for the deployment json names
    /// This can be dynamic based on the configured environment or static if the prefix is the same for all uses such as
    /// in testing or in one time scripts
    function _buildPrefix() internal view virtual returns (string memory);

    function buildAssetRegistryName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "AssetRegistry");
    }

    function buildStrategyRegistryName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "StrategyRegistry");
    }

    function buildEulerRouterName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "EulerRouter");
    }

    function buildBasketManagerName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "BasketManager");
    }

    function buildBasketTokenImplementationName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "BasketTokenImplementation");
    }

    function buildBasketTokenName(string memory name) public view returns (string memory) {
        return string.concat(_buildPrefix(), "BasketToken_", name);
    }

    function buildFeeCollectorName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "FeeCollector");
    }

    function buildTimelockControllerName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "TimelockController");
    }

    function buildCoWSwapCloneImplementationName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "CoWSwapCloneImplementation");
    }

    function buildCowSwapAdapterName() public view returns (string memory) {
        return string.concat(_buildPrefix(), "CowSwapAdapter");
    }

    function _getOracleAssetSymbol(address asset) internal view returns (string memory) {
        return asset == USD ? "USD" : (asset == ETH ? "ETH" : IERC20Metadata(asset).symbol());
    }

    function buildPythOracleName(address base, address quote) public view returns (string memory) {
        string memory baseSymbol = _getOracleAssetSymbol(base);
        string memory quoteSymbol = _getOracleAssetSymbol(quote);
        return string.concat(_buildPrefix(), "PythOracle_", baseSymbol, "-", quoteSymbol);
    }

    function buildChainlinkOracleName(address base, address quote) public view returns (string memory) {
        string memory baseSymbol = _getOracleAssetSymbol(base);
        string memory quoteSymbol = _getOracleAssetSymbol(quote);
        return string.concat(_buildPrefix(), "ChainlinkOracle_", baseSymbol, "-", quoteSymbol);
    }

    function buildERC4626OracleName(address asset, address quote) public view returns (string memory) {
        string memory assetSymbol = _getOracleAssetSymbol(asset);
        string memory quoteSymbol = _getOracleAssetSymbol(quote);
        return string.concat(_buildPrefix(), "ERC4626Oracle_", assetSymbol, "-", quoteSymbol);
    }

    function buildAnchoredOracleName(address base, address quote) public view returns (string memory) {
        string memory baseSymbol = _getOracleAssetSymbol(base);
        string memory quoteSymbol = _getOracleAssetSymbol(quote);
        return string.concat(_buildPrefix(), "AnchoredOracle_", baseSymbol, "-", quoteSymbol);
    }

    function buildManagedWeightStrategyName(string memory strategyName) public view returns (string memory) {
        return string.concat(_buildPrefix(), "ManagedWeightStrategy_", strategyName);
    }

    function buildFarmingPluginName(address asset, address rewardToken) public view returns (string memory) {
        string memory assetSymbol = _getOracleAssetSymbol(asset);
        string memory rewardTokenSymbol = _getOracleAssetSymbol(rewardToken);
        return string.concat(_buildPrefix(), "FarmingPlugin_", assetSymbol, "_", rewardTokenSymbol, "Rewards");
    }

    function buildCrossAdapterName(
        address base,
        address crossAsset,
        address quote,
        string memory baseOracleType,
        string memory crossOracleType
    )
        public
        view
        returns (string memory)
    {
        string memory baseSymbol = _getOracleAssetSymbol(base);
        string memory crossAssetSymbol = _getOracleAssetSymbol(crossAsset);
        string memory quoteSymbol = _getOracleAssetSymbol(quote);
        return string.concat(
            _buildPrefix(),
            "CrossAdapter_",
            baseSymbol,
            "-",
            crossAssetSymbol,
            "-",
            quoteSymbol,
            "_",
            baseOracleType,
            "_",
            crossOracleType
        );
    }
}

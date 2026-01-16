// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { RedstoneCoreOracle } from "euler-price-oracle/src/adapter/redstone/RedstoneCoreOracle.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { PythOracleMarketHours } from "src/oracles/PythOracleMarketHours.sol";
import { Constants } from "test/utils/Constants.t.sol";

abstract contract Mag7DeploymentUtils is Constants {
    function _isPythOnlyAsset(address asset) internal pure returns (bool) {
        return asset == ETH_AAPLON || asset == ETH_MSFTON;
    }

    function _assertPythOracleMarketHoursConfig(
        address oracle,
        address base,
        address quote,
        bytes32 feedId,
        uint256 maxStaleness,
        uint256 maxConfWidth
    )
        internal
        view
    {
        PythOracleMarketHours pythOracle = PythOracleMarketHours(oracle);
        require(pythOracle.base() == base, "Pyth base mismatch");
        require(pythOracle.quote() == quote, "Pyth quote mismatch");
        require(pythOracle.feedId() == feedId, "Pyth feedId mismatch");
        require(pythOracle.maxStaleness() == maxStaleness, "Pyth staleness mismatch");
        require(pythOracle.maxConfWidth() == maxConfWidth, "Pyth confWidth mismatch");
    }

    function _assertRedstoneCoreOracleConfig(
        address oracle,
        address base,
        address quote,
        bytes32 feedId,
        uint8 feedDecimals,
        uint256 maxStaleness
    )
        internal
        view
    {
        RedstoneCoreOracle redstoneOracle = RedstoneCoreOracle(oracle);
        require(redstoneOracle.base() == base, "Redstone base mismatch");
        require(redstoneOracle.quote() == quote, "Redstone quote mismatch");
        require(redstoneOracle.feedId() == feedId, "Redstone feedId mismatch");
        require(redstoneOracle.feedDecimals() == feedDecimals, "Redstone decimals mismatch");
        require(redstoneOracle.maxStaleness() == maxStaleness, "Redstone staleness mismatch");
    }

    function _assertAnchoredOracleConfig(
        address oracle,
        address primary,
        address anchor,
        uint256 maxDivergence
    )
        internal
        view
    {
        AnchoredOracle anchoredOracle = AnchoredOracle(oracle);
        require(anchoredOracle.primaryOracle() == primary, "Anchor primary mismatch");
        require(anchoredOracle.anchorOracle() == anchor, "Anchor anchor mismatch");
        require(anchoredOracle.maxDivergence() == maxDivergence, "Anchor divergence mismatch");
    }
}

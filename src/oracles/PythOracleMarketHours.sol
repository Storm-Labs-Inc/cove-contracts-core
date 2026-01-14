// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPyth } from "@pyth/IPyth.sol";
import { PythStructs } from "@pyth/PythStructs.sol";
import { BaseAdapter, Errors, IPriceOracle } from "euler-price-oracle/src/adapter/BaseAdapter.sol";
import { Scale, ScaleUtils } from "euler-price-oracle/src/lib/ScaleUtils.sol";

import { UsEquityMarketHours } from "src/libraries/UsEquityMarketHours.sol";

/// @title PythOracleMarketHours
/// @notice Pyth oracle adapter with US equity market hours guard.
/// @dev Uses publishTime from Pyth and rejects prices outside 09:30-16:00 ET, Mon-Fri (DST-aware).
contract PythOracleMarketHours is BaseAdapter {
    /// @notice The maximum length of time that a price can be in the future.
    uint256 internal constant _MAX_AHEADNESS = 1 minutes;
    /// @notice The maximum permitted value for `maxStaleness`.
    uint256 internal constant _MAX_STALENESS_UPPER_BOUND = 15 minutes;
    /// @notice The minimum permitted value for `maxConfWidth`.
    /// @dev Equal to 0.1%.
    uint256 internal constant _MAX_CONF_WIDTH_LOWER_BOUND = 10;
    /// @notice The maximum permitted value for `maxConfWidth`.
    /// @dev Equal to 5%.
    uint256 internal constant _MAX_CONF_WIDTH_UPPER_BOUND = 500;
    /// @dev The smallest PythStruct exponent that the oracle can handle.
    int256 internal constant _MIN_EXPONENT = -20;
    /// @dev The largest PythStruct exponent that the oracle can handle.
    int256 internal constant _MAX_EXPONENT = 12;
    /// @dev The denominator for basis points values (maxConfWidth).
    uint256 internal constant _BASIS_POINTS = 10_000;
    /// @inheritdoc IPriceOracle
    // solhint-disable-next-line const-name-snakecase
    string public constant name = "PythOracleMarketHours";
    /// @notice The address of the Pyth oracle proxy.
    address public immutable pyth;
    /// @notice The address of the base asset corresponding to the feed.
    address public immutable base;
    /// @notice The address of the quote asset corresponding to the feed.
    address public immutable quote;
    /// @notice The id of the feed in the Pyth network.
    bytes32 public immutable feedId;
    /// @notice The maximum allowed age of the price.
    uint256 public immutable maxStaleness;
    /// @notice The maximum allowed width of the confidence interval.
    uint256 public immutable maxConfWidth;
    /// @dev Used for correcting for the decimals of base and quote.
    uint8 internal immutable _baseDecimals;
    /// @dev Used for correcting for the decimals of base and quote.
    uint8 internal immutable _quoteDecimals;

    constructor(
        address _pyth,
        address _base,
        address _quote,
        bytes32 _feedId,
        uint256 _maxStaleness,
        uint256 _maxConfWidth
    ) {
        if (_maxStaleness > _MAX_STALENESS_UPPER_BOUND) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }
        if (_maxConfWidth < _MAX_CONF_WIDTH_LOWER_BOUND || _maxConfWidth > _MAX_CONF_WIDTH_UPPER_BOUND) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }

        pyth = _pyth;
        base = _base;
        quote = _quote;
        feedId = _feedId;
        maxStaleness = _maxStaleness;
        maxConfWidth = _maxConfWidth;
        _baseDecimals = _getDecimals(base);
        _quoteDecimals = _getDecimals(quote);
    }

    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);

        PythStructs.Price memory priceStruct = _fetchPriceStruct();

        uint256 price = uint256(uint64(priceStruct.price));
        int8 feedExponent = int8(_baseDecimals) - int8(priceStruct.expo);

        Scale scale;
        if (feedExponent > 0) {
            scale = ScaleUtils.from(_quoteDecimals, uint8(feedExponent));
        } else {
            scale = ScaleUtils.from(_quoteDecimals + uint8(-feedExponent), 0);
        }
        return ScaleUtils.calcOutAmount(inAmount, price, scale, inverse);
    }

    function _fetchPriceStruct() internal view returns (PythStructs.Price memory) {
        PythStructs.Price memory p = IPyth(pyth).getPriceUnsafe(feedId);

        if (p.publishTime < block.timestamp) {
            uint256 staleness = block.timestamp - p.publishTime;
            if (staleness > maxStaleness) revert Errors.PriceOracle_InvalidAnswer();
        } else {
            uint256 aheadness = p.publishTime - block.timestamp;
            if (aheadness > _MAX_AHEADNESS) revert Errors.PriceOracle_InvalidAnswer();
        }

        if (!UsEquityMarketHours.isWithinUsEquityHours(p.publishTime)) {
            revert Errors.PriceOracle_InvalidAnswer();
        }

        if (p.price <= 0 || p.conf > uint64(p.price) * maxConfWidth / _BASIS_POINTS) {
            revert Errors.PriceOracle_InvalidAnswer();
        }

        if (p.expo < _MIN_EXPONENT || p.expo > _MAX_EXPONENT) {
            revert Errors.PriceOracle_InvalidAnswer();
        }
        return p;
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { BaseAdapter, Errors, IPriceOracle } from "euler-price-oracle-1/src/adapter/BaseAdapter.sol";
import { ICurvePool } from "euler-price-oracle-1/src/adapter/curve/ICurvePool.sol";
import { Scale, ScaleUtils } from "euler-price-oracle-1/src/lib/ScaleUtils.sol";

/// @title CurveEMAOracleUnderlying
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Adapter utilizing the EMA price oracle in Curve pools.
contract CurveEMAOracleUnderlying is BaseAdapter {
    /// @inheritdoc IPriceOracle
    // solhint-disable-next-line const-name-snakecase
    string public constant name = "CurveEMAOracle";
    /// @notice The address of the Curve pool.
    address public immutable pool;
    /// @notice The address of the base asset.
    address public immutable base;
    /// @notice The address of the quote asset, must be `pool.coins[0]`.
    address public immutable quote;
    /// @notice The index in `price_oracle` corresponding to the base asset.
    /// @dev Note that indices in `price_oracle` are shifted by 1, i.e. `0` corresponds to `coins[1]`.
    /// @dev If type(uint256).max, then the adapter will call `price_oracle()`.
    /// @dev Else the adapter will call the indexed price method `price_oracle(priceOracleIndex)`.
    uint256 public immutable priceOracleIndex;
    /// @notice The scale factors used for decimal conversions.
    Scale internal immutable _scale;

    error BaseAssetMismatch();
    error QuoteAssetMismatch();

    /// @notice Deploy a CurveEMAOracle.
    /// @param _pool The address of the Curve pool.
    /// @param _base The address of the base asset.
    /// @param _quote The address of the quote asset.
    /// @param _priceOracleIndex The index in `price_oracle` corresponding to the base asset.
    /// @param isBaseUnderlying Whether the price oracle returns the price of the base asset in the underlying asset.
    /// @param isQuoteUnderlying Whether the price oracle returns the price of the quote asset in the underlying asset.
    /// @dev The quote is always `pool.coins[0]`.
    /// If `priceOracleIndex` is `type(uint256).max`, then the adapter will call the non-indexed price method
    /// `price_oracle()`
    /// WARNING: Some StableSwap-NG pools deployed before Dec-12-2023 have a known oracle vulnerability.
    /// See (https://docs.curve.fi/stableswap-exchange/stableswap-ng/pools/oracles/#price-oracles) for more details.
    /// Additionally, verify that the pool has enough liquidity before deploying this adapter.
    constructor(
        address _pool,
        address _base,
        address _quote,
        uint256 _priceOracleIndex,
        bool isBaseUnderlying,
        bool isQuoteUnderlying
    )
        payable
    {
        if (_pool == address(0)) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }
        if (_base == address(0)) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }
        if (_quote == address(0)) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }
        // The EMA oracle returns a price quoted in `coins[0]`.
        uint256 baseIndex = 0;
        if (_priceOracleIndex == type(uint256).max) {
            baseIndex = 1;
        } else {
            baseIndex = _priceOracleIndex + 1;
        }
        address baseCoin = ICurvePool(_pool).coins(baseIndex);
        address quoteCoin = ICurvePool(_pool).coins(0);

        if (isBaseUnderlying) {
            if (IERC4626(baseCoin).asset() != _base) revert BaseAssetMismatch();
        } else if (baseCoin != _base) {
            revert BaseAssetMismatch();
        }

        if (isQuoteUnderlying) {
            if (IERC4626(quoteCoin).asset() != _quote) revert QuoteAssetMismatch();
        } else if (quoteCoin != _quote) {
            revert QuoteAssetMismatch();
        }

        uint8 baseDecimals = _getDecimals(_base);
        uint8 quoteDecimals = _getDecimals(_quote);
        pool = _pool;
        base = _base;
        quote = _quote;
        priceOracleIndex = _priceOracleIndex;
        _scale = ScaleUtils.calcScale(baseDecimals, quoteDecimals, 18);
    }

    /// @notice Get a quote by calling the Curve oracle.
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The converted amount using the Curve EMA oracle.
    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);

        uint256 unitPrice;
        if (priceOracleIndex == type(uint256).max) {
            unitPrice = ICurvePool(pool).price_oracle();
        } else {
            unitPrice = ICurvePool(pool).price_oracle(priceOracleIndex);
        }

        return ScaleUtils.calcOutAmount(inAmount, unitPrice, _scale, inverse);
    }
}

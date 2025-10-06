// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPriceOracle } from "euler-price-oracle-1/src/interfaces/IPriceOracle.sol";
import { IPriceChecker } from "src/interfaces/deps/milkman/IPriceChecker.sol";

/// @title OraclePriceChecker
/// @notice Price checker that validates swap prices using IPriceOracle implementations
/// @dev This allows reusing existing oracle infrastructure (ChainlinkOracle, CurveEMAOracle, CrossAdapter, etc.)
contract OraclePriceChecker is IPriceChecker {
    /// @notice The price oracle to use for validation
    IPriceOracle public immutable oracle;

    /// @notice Maximum allowed price deviation in basis points
    uint256 public immutable defaultMaxDeviationBps;

    /// ERRORS ///
    error InvalidDeviationBps();
    error PriceBelowMinimum();

    /// @notice Constructor
    /// @param _oracle The IPriceOracle implementation to use
    /// @param _defaultMaxDeviationBps Maximum allowed deviation in basis points (e.g., 500 = 5%)
    constructor(IPriceOracle _oracle, uint256 _defaultMaxDeviationBps) payable {
        if (_defaultMaxDeviationBps > 10_000) {
            revert InvalidDeviationBps();
        }
        oracle = _oracle;
        defaultMaxDeviationBps = _defaultMaxDeviationBps;
    }

    /// @notice Check if a swap price meets the oracle requirements
    /// @param amountIn The amount of input tokens (including fee)
    /// @param fromToken The input token address
    /// @param toToken The output token address
    /// @param feeAmount The fee amount in input tokens
    /// @param minOut The minimum output amount from the solver
    /// @param data Additional data (used for max deviation bps)
    /// @return True if the price is acceptable
    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256 feeAmount,
        uint256 minOut,
        bytes calldata data
    )
        external
        view
        override
        returns (bool)
    {
        // Milkman forwards the gross sell amount (swap + solver fee); subtract fees to evaluate the net swap size.
        uint256 actualSwapAmount = amountIn - feeAmount;

        // Get expected output from oracle for the actual swap amount
        uint256 expectedOut = oracle.getQuote(actualSwapAmount, fromToken, toToken);

        // Get max deviation bps from data, if not provided, use default
        uint256 maxDeviationBps = data.length > 0 ? abi.decode(data, (uint256)) : defaultMaxDeviationBps;
        if (maxDeviationBps > 10_000) {
            revert InvalidDeviationBps();
        }

        // Calculate minimum acceptable output with deviation
        uint256 minAcceptableOut = (expectedOut * (10_000 - maxDeviationBps)) / 10_000;

        // Check if minOut meets the threshold, if not, return false
        return minOut >= minAcceptableOut;
    }
}

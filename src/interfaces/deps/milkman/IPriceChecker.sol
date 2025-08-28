// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title IPriceChecker
/// @notice Interface for price checker contracts used by Milkman to validate swaps
interface IPriceChecker {
    /// @notice Check if a swap price is acceptable
    /// @param amountIn The amount of input tokens
    /// @param fromToken The input token address
    /// @param toToken The output token address
    /// @param minOut The minimum output amount from the solver
    /// @param data Additional data for price checking
    /// @return True if the price is acceptable
    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256 minOut,
        bytes calldata data
    ) external view returns (bool);
}
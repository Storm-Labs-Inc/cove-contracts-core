// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IMilkman
/// @notice Interface for the Milkman contract that handles async swaps via CoW Protocol
/// @dev https://github.com/cowdao-grants/milkman/blob/3b02b80a512b30194efc1debe5fcf0747de6b561/src/Milkman.sol
interface IMilkman {
    /// @notice Event emitted when a swap is requested
    event SwapRequested(
        address orderContract,
        address orderCreator,
        uint256 amountIn,
        address fromToken,
        address toToken,
        address to,
        bytes32 appData,
        address priceChecker,
        bytes priceCheckerData
    );

    /// @notice Request an async swap of exact tokens for tokens
    /// @param amountIn The amount of input tokens to swap
    /// @param fromToken The token to swap from
    /// @param toToken The token to swap to
    /// @param to The recipient of the output tokens
    /// @param appData The app data to be used in the CoW Protocol order
    /// @param priceChecker The price checker contract to validate the swap
    /// @param priceCheckerData Data to pass to the price checker
    function requestSwapExactTokensForTokens(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;

    /// @notice Cancel a requested swap
    /// @param amountIn The amount that was to be swapped
    /// @param fromToken The from token
    /// @param toToken The to token
    /// @param to The recipient
    /// @param priceChecker The price checker that was used
    /// @param priceCheckerData The price checker data that was used
    function cancelSwap(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;
}
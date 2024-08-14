// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ExternalTrade } from "../types/Trades.sol";

/// @title TokenSwapAdapter
/// @notice Abstract contract for token swap adapters
abstract contract TokenSwapAdapter {
    /// @notice Executes series of token swaps and returns the hashes of the orders submitted/executed
    /// @param data The data needed to execute the token swap
    /// @return hashes The hashes of the orders submitted/executed
    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata data
    )
        external
        virtual
        returns (bytes32[] memory hashes);
}

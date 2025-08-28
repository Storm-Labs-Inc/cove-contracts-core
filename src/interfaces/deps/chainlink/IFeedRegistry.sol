// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title IFeedRegistry
/// @notice Interface for Chainlink Feed Registry
interface IFeedRegistry {
    /// @notice Get the latest round data for a base/quote pair
    /// @param base The base asset
    /// @param quote The quote asset
    /// @return roundId The round ID
    /// @return answer The price answer
    /// @return startedAt The timestamp the round started
    /// @return updatedAt The timestamp the round was updated
    /// @return answeredInRound The round ID in which the answer was computed
    function latestRoundData(
        address base,
        address quote
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Get the decimals for a base/quote pair
    /// @param base The base asset
    /// @param quote The quote asset
    /// @return The number of decimals
    function decimals(address base, address quote) external view returns (uint8);

    /// @notice Get the aggregator for a base/quote pair
    /// @param base The base asset
    /// @param quote The quote asset
    /// @return The aggregator address
    function getFeed(address base, address quote) external view returns (address);
}
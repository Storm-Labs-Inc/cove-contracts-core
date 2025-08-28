// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title IUniswapV3Pool
/// @notice Minimal interface for Uniswap V3 pools
interface IUniswapV3Pool {
    /// @notice The first token of the pool
    function token0() external view returns (address);
    
    /// @notice The second token of the pool
    function token1() external view returns (address);
    
    /// @notice The fee of the pool
    function fee() external view returns (uint24);
    
    /// @notice Get the current sqrt price and tick
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    
    /// @notice Returns data about a specific observation
    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );
    
    /// @notice Observe the tick and liquidity values
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}
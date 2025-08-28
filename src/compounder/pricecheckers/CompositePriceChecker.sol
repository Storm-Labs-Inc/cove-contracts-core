// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPriceChecker } from "src/interfaces/deps/milkman/IPriceChecker.sol";
import { IFeedRegistry } from "src/interfaces/deps/chainlink/IFeedRegistry.sol";
import { IUniswapV3Pool } from "src/interfaces/deps/uniswap/IUniswapV3Pool.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/// @title CompositePriceChecker
/// @notice Price checker that combines DEX TWAP with Chainlink oracles for tokens without direct feeds
/// @dev Useful for tokens like TOKE that don't have direct Chainlink USD feeds
contract CompositePriceChecker is IPriceChecker {
    using FixedPointMathLib for uint256;
    
    /// CONSTANTS ///
    
    /// @notice Chainlink Feed Registry on Ethereum mainnet
    IFeedRegistry public constant FEED_REGISTRY = IFeedRegistry(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    
    /// @notice USD quote currency for Chainlink
    address public constant USD = address(840);
    
    /// @notice ETH address for Chainlink
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    /// @notice WETH address on mainnet
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    /// @notice USDC address on mainnet
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    /// @notice Maximum staleness for Chainlink feeds (seconds)
    uint256 public constant MAX_STALENESS = 3600;
    
    /// @notice Default TWAP window (seconds)
    uint256 public constant DEFAULT_TWAP_WINDOW = 1800; // 30 minutes
    
    /// STRUCTS ///
    
    struct PriceCheckerData {
        uint256 maxDeviationBps;
        address uniV3Pool;      // Pool for token/WETH pair
        uint256 twapWindow;     // TWAP window in seconds
    }
    
    /// ERRORS ///
    
    error StalePrice();
    error InvalidPrice();
    error PriceBelowMinimum();
    error InvalidDeviationBps();
    error InvalidPool();
    error InsufficientLiquidity();
    
    /// @notice Check if a swap price meets the composite oracle requirements
    /// @param amountIn The amount of input tokens
    /// @param fromToken The input token address
    /// @param toToken The output token address
    /// @param minOut The minimum output amount from the solver
    /// @param data Encoded PriceCheckerData
    /// @return True if the price is acceptable
    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256 minOut,
        bytes calldata data
    ) external view override returns (bool) {
        PriceCheckerData memory params = abi.decode(data, (PriceCheckerData));
        
        if (params.maxDeviationBps > 10000) {
            revert InvalidDeviationBps();
        }
        
        // Get composite price for fromToken
        uint256 fromTokenPriceUSD = _getCompositePriceUSD(fromToken, params.uniV3Pool, params.twapWindow);
        
        // Get price for toToken (should be USDC in most cases)
        uint256 toTokenPriceUSD = _getDirectPriceUSD(toToken);
        
        // Calculate expected output
        uint8 fromDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toDecimals = IERC20Metadata(toToken).decimals();
        
        uint256 expectedOut = (amountIn * fromTokenPriceUSD * (10 ** toDecimals)) / 
                             (toTokenPriceUSD * (10 ** fromDecimals));
        
        // Calculate minimum acceptable output with deviation
        uint256 minAcceptableOut = (expectedOut * (10000 - params.maxDeviationBps)) / 10000;
        
        return minOut >= minAcceptableOut;
    }
    
    /// @notice Get composite price using DEX TWAP and Chainlink
    /// @param token The token to price
    /// @param pool The Uniswap V3 pool address
    /// @param twapWindow The TWAP window in seconds
    /// @return The price in USD with 8 decimals
    function _getCompositePriceUSD(
        address token,
        address pool,
        uint256 twapWindow
    ) internal view returns (uint256) {
        if (pool == address(0)) {
            revert InvalidPool();
        }
        
        // Get TWAP price of token in terms of WETH
        uint256 tokenPriceInWETH = _getTWAPPrice(pool, token, twapWindow);
        
        // Get ETH price in USD from Chainlink
        uint256 ethPriceUSD = _getETHPriceUSD();
        
        // Calculate token price in USD
        // tokenPriceUSD = tokenPriceInWETH * ethPriceUSD / 1e18
        uint256 tokenPriceUSD = (tokenPriceInWETH * ethPriceUSD) / 1e18;
        
        return tokenPriceUSD;
    }
    
    /// @notice Get TWAP price from Uniswap V3 pool
    /// @param pool The pool address
    /// @param token The token we're pricing
    /// @param twapWindow The TWAP window
    /// @return The price in WETH terms (18 decimals)
    function _getTWAPPrice(
        address pool,
        address token,
        uint256 twapWindow
    ) internal view returns (uint256) {
        IUniswapV3Pool uniPool = IUniswapV3Pool(pool);
        
        // Verify pool tokens
        address token0 = uniPool.token0();
        address token1 = uniPool.token1();
        
        bool isToken0 = token0 == token;
        bool isToken1 = token1 == token;
        
        if (!isToken0 && !isToken1) {
            revert InvalidPool();
        }
        
        // Ensure the other token is WETH
        address otherToken = isToken0 ? token1 : token0;
        if (otherToken != WETH) {
            revert InvalidPool();
        }
        
        // Get TWAP tick
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(twapWindow);
        secondsAgos[1] = 0;
        
        (int56[] memory tickCumulatives, ) = uniPool.observe(secondsAgos);
        
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int56(uint56(twapWindow)));
        
        // Ensure tick is valid (has sufficient liquidity)
        if (timeWeightedAverageTick < -887272 || timeWeightedAverageTick > 887272) {
            revert InsufficientLiquidity();
        }
        
        // Calculate price from tick
        // price = 1.0001^tick
        uint256 sqrtPriceX96 = _getSqrtPriceX96FromTick(timeWeightedAverageTick);
        
        // Convert to price with proper decimal handling
        uint256 price;
        if (isToken0) {
            // price = (sqrtPrice^2) / (2^192) * (10^decimal1 / 10^decimal0)
            uint256 decimal0 = IERC20Metadata(token0).decimals();
            uint256 decimal1 = IERC20Metadata(token1).decimals();
            price = (sqrtPriceX96 * sqrtPriceX96 * (10 ** decimal1)) / (2 ** 192) / (10 ** decimal0);
        } else {
            // price = (2^192) / (sqrtPrice^2) * (10^decimal0 / 10^decimal1)
            uint256 decimal0 = IERC20Metadata(token0).decimals();
            uint256 decimal1 = IERC20Metadata(token1).decimals();
            price = (2 ** 192 * (10 ** decimal0)) / (sqrtPriceX96 * sqrtPriceX96) / (10 ** decimal1);
        }
        
        // Normalize to 18 decimals
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        if (tokenDecimals != 18) {
            if (tokenDecimals > 18) {
                price = price / (10 ** (tokenDecimals - 18));
            } else {
                price = price * (10 ** (18 - tokenDecimals));
            }
        }
        
        return price;
    }
    
    /// @notice Calculate sqrtPriceX96 from tick
    /// @param tick The tick value
    /// @return The sqrtPriceX96
    function _getSqrtPriceX96FromTick(int24 tick) internal pure returns (uint160) {
        uint256 absTick = tick < 0 ? uint256(uint24(-tick)) : uint256(uint24(tick));
        
        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;
        
        if (tick > 0) ratio = type(uint256).max / ratio;
        
        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
    
    /// @notice Get ETH price in USD from Chainlink
    /// @return The price with 8 decimals
    function _getETHPriceUSD() internal view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = FEED_REGISTRY.latestRoundData(ETH, USD);
        
        if (block.timestamp - updatedAt > MAX_STALENESS) {
            revert StalePrice();
        }
        if (price <= 0) {
            revert InvalidPrice();
        }
        
        return uint256(price);
    }
    
    /// @notice Get direct price from Chainlink if available
    /// @param token The token address
    /// @return The price with 8 decimals
    function _getDirectPriceUSD(address token) internal view returns (uint256) {
        // Special handling for USDC
        if (token == USDC) {
            return 1e8;
        }
        
        try FEED_REGISTRY.latestRoundData(token, USD) returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (block.timestamp - updatedAt > MAX_STALENESS) {
                revert StalePrice();
            }
            if (answer <= 0) {
                revert InvalidPrice();
            }
            return uint256(answer);
        } catch {
            revert InvalidPrice();
        }
    }
}
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPriceChecker } from "src/interfaces/deps/milkman/IPriceChecker.sol";
import { IFeedRegistry } from "src/interfaces/deps/chainlink/IFeedRegistry.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title ChainlinkPriceChecker
/// @notice Price checker that validates swap prices using Chainlink oracles
contract ChainlinkPriceChecker is IPriceChecker {
    /// CONSTANTS ///
    
    /// @notice Chainlink Feed Registry on Ethereum mainnet
    IFeedRegistry public constant FEED_REGISTRY = IFeedRegistry(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    
    /// @notice USD quote currency for Chainlink
    address public constant USD = address(840); // Chainlink's USD identifier
    
    /// @notice Maximum staleness allowed for price feeds (in seconds)
    uint256 public constant MAX_STALENESS = 3600; // 1 hour
    
    /// @notice USDC address on mainnet
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    /// ERRORS ///
    
    error StalePrice();
    error InvalidPrice();
    error PriceBelowMinimum();
    error InvalidDeviationBps();
    
    /// @notice Check if a swap price meets the oracle requirements
    /// @param amountIn The amount of input tokens
    /// @param fromToken The input token address
    /// @param toToken The output token address  
    /// @param minOut The minimum output amount from the solver
    /// @param data Encoded max deviation in basis points
    /// @return True if the price is acceptable
    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256 minOut,
        bytes calldata data
    ) external view override returns (bool) {
        // Decode max deviation from data
        uint256 maxDeviationBps = abi.decode(data, (uint256));
        if (maxDeviationBps > 10000) {
            revert InvalidDeviationBps();
        }
        
        // Get oracle prices
        uint256 fromTokenPriceUSD = _getTokenPriceUSD(fromToken);
        uint256 toTokenPriceUSD = _getTokenPriceUSD(toToken);
        
        // Calculate expected output based on oracle prices
        // expectedOut = (amountIn * fromTokenPriceUSD / toTokenPriceUSD) * (10^toDecimals / 10^fromDecimals)
        uint8 fromDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toDecimals = IERC20Metadata(toToken).decimals();
        
        uint256 expectedOut = (amountIn * fromTokenPriceUSD * (10 ** toDecimals)) / 
                             (toTokenPriceUSD * (10 ** fromDecimals));
        
        // Calculate minimum acceptable output with deviation
        uint256 minAcceptableOut = (expectedOut * (10000 - maxDeviationBps)) / 10000;
        
        // Check if minOut meets the threshold
        return minOut >= minAcceptableOut;
    }
    
    /// @notice Get the USD price for a token
    /// @param token The token address
    /// @return The price in USD with 8 decimals
    function _getTokenPriceUSD(address token) internal view returns (uint256) {
        // Special handling for USDC - treat as $1
        if (token == USDC) {
            return 1e8; // $1 with 8 decimals
        }
        
        try FEED_REGISTRY.latestRoundData(token, USD) returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // Check staleness
            if (block.timestamp - updatedAt > MAX_STALENESS) {
                revert StalePrice();
            }
            
            // Check valid price
            if (answer <= 0) {
                revert InvalidPrice();
            }
            
            return uint256(answer);
        } catch {
            // If direct USD feed doesn't exist, try ETH as intermediate
            return _getPriceViaETH(token);
        }
    }
    
    /// @notice Get USD price via ETH as intermediate
    /// @param token The token address
    /// @return The price in USD with 8 decimals
    function _getPriceViaETH(address token) internal view returns (uint256) {
        address ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        
        // Get token/ETH price
        (uint80 roundId1, int256 tokenETHPrice, , uint256 updatedAt1, ) = 
            FEED_REGISTRY.latestRoundData(token, ETH);
            
        if (block.timestamp - updatedAt1 > MAX_STALENESS) {
            revert StalePrice();
        }
        if (tokenETHPrice <= 0) {
            revert InvalidPrice();
        }
        
        // Get ETH/USD price
        (uint80 roundId2, int256 ethUSDPrice, , uint256 updatedAt2, ) = 
            FEED_REGISTRY.latestRoundData(ETH, USD);
            
        if (block.timestamp - updatedAt2 > MAX_STALENESS) {
            revert StalePrice();
        }
        if (ethUSDPrice <= 0) {
            revert InvalidPrice();
        }
        
        // Get decimals for proper calculation
        uint8 tokenETHDecimals = FEED_REGISTRY.decimals(token, ETH);
        uint8 ethUSDDecimals = FEED_REGISTRY.decimals(ETH, USD);
        
        // Calculate token/USD price
        // Price = (token/ETH * ETH/USD) with decimal adjustment
        uint256 price = (uint256(tokenETHPrice) * uint256(ethUSDPrice)) / (10 ** tokenETHDecimals);
        
        // Adjust to 8 decimals if needed
        if (ethUSDDecimals != 8) {
            if (ethUSDDecimals > 8) {
                price = price / (10 ** (ethUSDDecimals - 8));
            } else {
                price = price * (10 ** (8 - ethUSDDecimals));
            }
        }
        
        return price;
    }
}
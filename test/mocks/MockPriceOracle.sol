// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPriceOracle } from "euler-price-oracle-1/src/interfaces/IPriceOracle.sol";

/// @title MockPriceOracle
/// @notice Mock implementation of IPriceOracle for testing
contract MockPriceOracle is IPriceOracle {
    string public constant name = "MockPriceOracle";
    
    /// @notice Configurable exchange rates for testing
    mapping(address => mapping(address => uint256)) public exchangeRates;
    
    /// @notice Set an exchange rate between two tokens
    /// @param base The base token
    /// @param quote The quote token
    /// @param rate The exchange rate (amount of quote per 1 unit of base, scaled by token decimals)
    function setExchangeRate(address base, address quote, uint256 rate) external {
        exchangeRates[base][quote] = rate;
    }
    
    /// @notice Get a quote for converting base to quote
    /// @param inAmount The amount of base to convert
    /// @param base The token being converted from
    /// @param quote The token being converted to
    /// @return outAmount The amount of quote tokens
    function getQuote(uint256 inAmount, address base, address quote) external view override returns (uint256 outAmount) {
        uint256 rate = exchangeRates[base][quote];
        if (rate == 0) {
            // Try inverse rate
            uint256 inverseRate = exchangeRates[quote][base];
            if (inverseRate > 0) {
                // Calculate using inverse rate
                outAmount = (inAmount * 1e18) / inverseRate;
            } else {
                // Default to 1:1 if no rate set
                outAmount = inAmount;
            }
        } else {
            // Direct rate calculation
            outAmount = (inAmount * rate) / 1e18;
        }
    }
    
    /// @notice Get both bid and ask quotes (returns same value for both in mock)
    /// @param inAmount The amount of base to convert
    /// @param base The token being converted from
    /// @param quote The token being converted to
    /// @return bidOutAmount The bid amount (same as ask in mock)
    /// @return askOutAmount The ask amount (same as bid in mock)
    function getQuotes(uint256 inAmount, address base, address quote)
        external
        view
        override
        returns (uint256 bidOutAmount, uint256 askOutAmount)
    {
        uint256 amount = this.getQuote(inAmount, base, quote);
        return (amount, amount);
    }
}
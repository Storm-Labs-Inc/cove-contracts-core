// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

contract MockPriceOracle {
    mapping(address => mapping(address => uint256)) internal prices;

    // require for OracleHandler
    address[] public _all_assets;
    mapping(address => bool) _assets_seen;

    error UndefinedPriceInMockOracle(address, address);

    function setPrice(address base, address quote, uint256 price) external {
        prices[base][quote] = price;

        if (!_assets_seen[base]) {
            _assets_seen[base] = true;
            _all_assets.push(base);
        }
        if (!_assets_seen[quote]) {
            _assets_seen[quote] = true;
            _all_assets.push(quote);
        }
    }

    function getPrice(address base, address quote) public view returns (uint256) {
        return prices[base][quote];
    }

    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256) {
        return _calcQuote(inAmount, base, quote);
    }

    function getQuotes(uint256 inAmount, address base, address quote) external view returns (uint256, uint256) {
        return (_calcQuote(inAmount, base, quote), _calcQuote(inAmount, base, quote));
    }

    function _calcQuote(uint256 inAmount, address base, address quote) internal view returns (uint256) {
        // Can happen in invariant_ERC4626_totalAssets
        // When we sum up the value of all assets with regards to the base asset, including the base asset itself
        if (base == quote) {
            return inAmount;
        }

        if (prices[base][quote] == 0) {
            revert UndefinedPriceInMockOracle(base, quote);
        }
        return FixedPointMathLib.fullMulDiv(inAmount, prices[base][quote], 1e18);
    }

    // require for _getPrimaryOracleQuote in BasketManagerValidationLib
    function getConfiguredOracle(address, address) public view returns (address) {
        return address(this);
    }

    // require for _getPrimaryOracleQuote in BasketManagerValidationLib
    function primaryOracle() public view returns (address) {
        return address(this);
    }

    // require for OracleHandler
    function all_assets() public view returns (address[] memory) {
        return _all_assets;
    }
}

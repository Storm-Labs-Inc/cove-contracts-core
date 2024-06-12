// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

// TODO: remove after slither is fixed, ref: https://github.com/crytic/slither/issues/2483

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title IPriceOracle
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Common PriceOracle interface.
interface IPriceOracle {
    /// @notice Get the name of the oracle.
    /// @return The name of the oracle.
    function name() external view returns (string memory);

    /// @notice One-sided price: How much quote token you would get for inAmount of base token, assuming no price spread.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced.
    /// @param quote The token that is the unit of account.
    /// @return outAmount The amount of `quote` that is equivalent to `inAmount` of `base`.
    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256 outAmount);

    /// @notice Two-sided price: How much quote token you would get/spend for selling/buying inAmount of base token.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced.
    /// @param quote The token that is the unit of account.
    /// @return bidOutAmount The amount of `quote` you would get for selling `inAmount` of `base`.
    /// @return askOutAmount The amount of `quote` you would spend for buying `inAmount` of `base`.
    function getQuotes(uint256 inAmount, address base, address quote)
        external
        view
        returns (uint256 bidOutAmount, uint256 askOutAmount);
}

/// @title Errors
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Collects common errors in PriceOracles.
library Errors {
    /// @notice The external feed returned an invalid answer.
    error PriceOracle_InvalidAnswer();
    /// @notice The configuration parameters for the PriceOracle are invalid.
    error PriceOracle_InvalidConfiguration();
    /// @notice The base/quote path is not supported.
    /// @param base The address of the base asset.
    /// @param quote The address of the quote asset.
    error PriceOracle_NotSupported(address base, address quote);
    /// @notice The quote cannot be completed due to overflow.
    error PriceOracle_Overflow();
    /// @notice The price is too stale.
    /// @param staleness The time elapsed since the price was updated.
    /// @param maxStaleness The maximum time elapsed since the last price update.
    error PriceOracle_TooStale(uint256 staleness, uint256 maxStaleness);
    /// @notice The method can only be called by the governor.
    error Governance_CallerNotGovernor();
}

/// @title BaseAdapter
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Abstract adapter with virtual bid/ask pricing.
abstract contract BaseAdapter is IPriceOracle {
    /// @inheritdoc IPriceOracle
    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256) {
        return _getQuote(inAmount, base, quote);
    }

    /// @inheritdoc IPriceOracle
    /// @dev Does not support true bid/ask pricing.
    function getQuotes(uint256 inAmount, address base, address quote) external view returns (uint256, uint256) {
        uint256 outAmount = _getQuote(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    /// @notice Call `decimals()`, falling back to 18 decimals.
    /// @param asset ERC20 token address or other asset.
    /// @dev Oracles can use ERC-7535, ISO 4217 or other conventions to represent non-ERC20 assets as addresses.
    /// Integrator Note: `_getDecimals` will return 18 if `asset` is:
    /// - an EOA or a to-be-deployed contract (which may implement `decimals()` after deployment).
    /// - a contract that does not implement `decimals()`.
    /// @return The decimals of the asset.
    function _getDecimals(address asset) internal view returns (uint8) {
        (bool success, bytes memory data) = asset.staticcall(abi.encodeCall(IERC20.decimals, ()));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    /// @notice Return the quote for the given price query.
    /// @dev Must be overridden in the inheriting contract.
    function _getQuote(uint256, address, address) internal view virtual returns (uint256);
}

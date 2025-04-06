// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { BaseAdapter } from "euler-price-oracle/src/adapter/BaseAdapter.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";
import { Errors } from "euler-price-oracle/src/lib/Errors.sol";

/// @title AnchoredOracle
/// @author Storm Labs (https://storm-labs.xyz/)
/// @dev Euler's experimental implementation was used as a reference:
/// https://github.com/euler-xyz/euler-price-oracle/blob/experiments/src/aggregator/AnchoredOracle.sol
/// @notice PriceOracle that chains two PriceOracles.
contract AnchoredOracle is BaseAdapter {
    /// @notice The lower bound for `maxDivergence`, 0.1%.
    uint256 internal constant _MAX_DIVERGENCE_LOWER_BOUND = 0.001e18;
    /// @notice The upper bound for `maxDivergence`, 50%.
    uint256 internal constant _MAX_DIVERGENCE_UPPER_BOUND = 0.5e18;
    /// @notice The denominator for `maxDivergence`.
    uint256 internal constant _WAD = 1e18;
    /// @notice The name of the oracle.
    // solhint-disable-next-line const-name-snakecase
    string public constant name = "AnchoredOracle";
    /// @notice The address of the primary oracle.
    address public immutable primaryOracle;
    /// @notice The address of the anchor oracle.
    address public immutable anchorOracle;
    /// @notice The maximum divergence allowed, denominated in _WAD.
    uint256 public immutable maxDivergence;

    /// @notice Reverts when the input amount is too large to scale without overflow.
    error AnchoredOracle_ScalingOverflow();

    /// @notice Deploys an AnchoredOracle contract.
    /// @param _primaryOracle The address of the primary oracle used for obtaining price quotes.
    /// @param _anchorOracle The address of the anchor oracle used for validating price quotes.
    /// @param _maxDivergence The maximum allowed divergence between the primary and anchor oracle prices, denominated
    /// in _WAD.
    // slither-disable-next-line locked-ether
    constructor(address _primaryOracle, address _anchorOracle, uint256 _maxDivergence) payable {
        if (_primaryOracle == address(0)) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }
        if (_anchorOracle == address(0)) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }
        if (_maxDivergence < _MAX_DIVERGENCE_LOWER_BOUND || _maxDivergence > _MAX_DIVERGENCE_UPPER_BOUND) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }

        primaryOracle = _primaryOracle;
        anchorOracle = _anchorOracle;
        maxDivergence = _maxDivergence;
    }

    /// @dev Retrieves a price quote from the `primaryOracle` and ensures that `anchorOracle` price does not diverge by
    /// more than +/- the percent threshold.  For example with a 50% threshold, a primary quote of 10 would check that
    /// the anchor is between 5 and 15.
    /// @param inAmount The amount of `base` token to be converted.
    /// @param base The token for which the price is being determined.
    /// @param quote The token against which the price is measured.
    /// @return The price quote from the `primaryOracle`.
    function _getQuote(uint256 inAmount, address base, address quote) internal view override returns (uint256) {
        // Get the initial quote from the primary oracle
        uint256 originalPrimaryOutAmount = IPriceOracle(primaryOracle).getQuote(inAmount, base, quote);

        uint256 primaryToCheck;
        uint256 anchorToCheck;

        // If the initial primary output is very small, scale the input to get better precision for the check
        if (originalPrimaryOutAmount < _WAD) {
            // Prevent overflow when scaling the input amount
            if (inAmount > type(uint256).max / _WAD) {
                revert AnchoredOracle_ScalingOverflow();
            }
            uint256 scaledInAmount = inAmount * _WAD;

            // Get quotes using the scaled input amount
            primaryToCheck = IPriceOracle(primaryOracle).getQuote(scaledInAmount, base, quote);
            anchorToCheck = IPriceOracle(anchorOracle).getQuote(scaledInAmount, base, quote);
        } else {
            // If the initial primary output is large enough, use original amounts for the check
            primaryToCheck = originalPrimaryOutAmount;
            anchorToCheck = IPriceOracle(anchorOracle).getQuote(inAmount, base, quote);
        }

        // Perform the bounds check using the potentially scaled values
        uint256 lowerBound = FixedPointMathLib.fullMulDivUp(primaryToCheck, _WAD - maxDivergence, _WAD);
        uint256 upperBound = FixedPointMathLib.fullMulDiv(primaryToCheck, _WAD + maxDivergence, _WAD);

        if (anchorToCheck < lowerBound || anchorToCheck > upperBound) {
            revert Errors.PriceOracle_InvalidAnswer();
        }

        // Return the original output amount
        return originalPrimaryOutAmount;
    }
}

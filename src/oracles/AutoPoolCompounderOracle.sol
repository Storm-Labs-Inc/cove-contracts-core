// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ChainedERC4626Oracle } from "./ChainedERC4626Oracle.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";

/// @title AutoPoolCompounderOracle
/// @author Storm Labs (https://storm-labs.xyz/)
/// @notice A price oracle adapter for Autopool Compounder tokens that provides pricing relative to the base asset
/// @dev Extends ChainedERC4626Oracle to handle the AutopoolCompounder -> Autopool -> BaseAsset chain
/// with additional validation for the Autopool's debt reporting staleness.
///
/// The oracle validates that the Autopool's oldestDebtReporting timestamp is within 24 hours
/// to ensure accurate pricing. If the debt reporting is stale, the oracle will revert.
///
/// Chain structure:
/// 1. AutopoolCompounder (Yearn V3 Strategy, ERC4626) holds Autopool tokens
/// 2. Autopool (Tokemak Vault, ERC4626) holds base asset (e.g., USDC)
/// 3. Base Asset (e.g., USDC)
contract AutoPoolCompounderOracle is ChainedERC4626Oracle {
    /// @notice Maximum allowed age for debt reporting (24 hours in seconds)
    uint256 public constant MAX_DEBT_REPORTING_AGE = 24 hours;

    /// @notice The Autopool contract for debt reporting validation
    IAutopool public immutable autopool;

    /// @notice Thrown when the Autopool's debt reporting is stale (older than 24 hours)
    error StaleDebtReporting(uint256 oldestTimestamp, uint256 currentTimestamp);
    /// @notice Thrown when the vault chain length is invalid
    error InvalidChainLength();

    /// @notice Constructor for the AutoPoolCompounderOracle contract
    /// @param _compounder The AutopoolCompounder (Yearn V3 Strategy) contract
    /// @dev The constructor automatically discovers the chain from compounder to base asset
    /// and validates that the autopool's debt reporting is fresh
    constructor(IERC4626 _compounder) payable ChainedERC4626Oracle(_compounder, _getBaseAsset(_compounder)) {
        // The second vault in the chain should be the Autopool
        // vaults[0] is the compounder, vaults[1] is the autopool
        if (vaults.length < 2) revert InvalidChainLength();
        autopool = IAutopool(vaults[1]);

        // Validate debt reporting is fresh at deployment
        _validateDebtReporting();
    }

    /// @notice Internal function to get quote with debt reporting validation
    /// @param inAmount The input amount to convert
    /// @param _base The base asset address
    /// @param _quote The quote asset address
    /// @return The converted amount
    function _getQuote(
        uint256 inAmount,
        address _base,
        address _quote
    )
        internal
        view
        virtual
        override
        returns (uint256)
    {
        // Validate that debt reporting is fresh before providing a quote
        _validateDebtReporting();

        // Use the parent implementation for the actual conversion
        return super._getQuote(inAmount, _base, _quote);
    }

    /// @notice Validates that the Autopool's debt reporting is not stale
    /// @dev Reverts if the oldest debt reporting timestamp is more than 24 hours old
    function _validateDebtReporting() internal view {
        uint256 oldestDebtTimestamp = autopool.oldestDebtReporting();
        uint256 currentTimestamp = block.timestamp;

        // If oldestDebtTimestamp is 0, it means no debt reporting has been set yet
        // In this case, we can skip validation
        if (oldestDebtTimestamp == 0) {
            return;
        }

        // Check if debt reporting is stale (older than 24 hours)
        // Only check if currentTimestamp is greater than oldestDebtTimestamp to avoid underflow
        if (currentTimestamp > oldestDebtTimestamp) {
            uint256 debtAge = currentTimestamp - oldestDebtTimestamp;
            if (debtAge > MAX_DEBT_REPORTING_AGE) {
                revert StaleDebtReporting(oldestDebtTimestamp, currentTimestamp);
            }
        }
    }

    /// @notice Helper function to extract the base asset from the compounder chain
    /// @param _compounder The AutopoolCompounder contract
    /// @return The base asset address (e.g., USDC)
    function _getBaseAsset(IERC4626 _compounder) private view returns (address) {
        // Get the autopool from the compounder
        address autopoolAddress = _compounder.asset();
        // Get the base asset from the autopool
        return IERC4626(autopoolAddress).asset();
    }
}

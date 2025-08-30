// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title IAutopool
/// @notice Interface for Tokemak Autopool vault contracts
/// @dev Autopools are ERC4626 vaults with a base asset (like USDC) that mint autopool tokens
interface IAutopool is IERC4626, IERC20Permit {
    /// @notice Returns the oldest debt reporting timestamp
    /// @dev If this timestamp is older than 1 day, the basket value may be inaccurate
    /// @return The oldest debt timestamp
    function oldestDebtReporting() external view returns (uint256);
}
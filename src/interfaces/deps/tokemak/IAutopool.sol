// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title IAutopool
/// @notice Interface for Tokemak Autopool vault contracts
/// @dev Autopools are ERC4626 vaults with a base asset (like USDC) that mint autopool tokens
interface IAutopool is IERC4626, IERC20Permit {
    /// @notice Returns the base asset of the autopool
    /// @dev For example, USDC for autoUSD
    /// @return The base asset address
    function baseAsset() external view returns (address);

    /// @notice Returns the debt reporting value
    /// @return The debt value
    function getDebt() external view returns (uint256);

    /// @notice Returns the idle amount in the vault
    /// @return The idle amount
    function getIdle() external view returns (uint256);

    /// @notice Returns whether the vault is shutdown
    /// @return True if shutdown
    function isShutdown() external view returns (bool);

    /// @notice Pauses the vault
    function pause() external;

    /// @notice Unpauses the vault
    function unpause() external;
}
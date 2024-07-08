// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { Errors } from "src/libraries/Errors.sol";

/**
 * @title AssetRegistry
 * @dev Manages the registration and status of assets in the system.
 * @notice This contract provides functionality to add, enable, pause, and manage assets, with role-based access
 * control.
 * @dev Utilizes OpenZeppelin's AccessControlEnumerable for granular permission management.
 * @dev Supports three asset states: DISABLED -> ENABLED <-> PAUSED.
 */
contract AssetRegistry is AccessControlEnumerable {
    /**
     * Enums
     */
    enum AssetState {
        /// @notice Asset is disabled and cannot be used in the system
        DISABLED,
        /// @notice Asset is enabled and can be used normally in the system
        ENABLED,
        /// @notice Asset is paused and cannot be used until unpaused
        PAUSED
    }

    /**
     * Structs
     */
    struct AssetStatus {
        /// @dev Indicates the current state of the asset in the registry.
        AssetState state;
    }

    /**
     * Constants
     */
    /// @notice Role responsible for managing assets in the registry.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /**
     * State variables
     */
    // slither-disable-next-line uninitialized-state
    /// @dev Mapping from asset address to its status in the registry.
    mapping(address => AssetStatus) private _assetRegistry;

    /**
     * Events
     */
    /// @dev Emitted when a new asset is added to the registry.
    event AddAsset(address indexed asset);
    /// @dev Emitted when an asset's state is updated.
    event SetAssetState(address indexed asset, AssetState state);

    /**
     * Errors
     */
    /// @notice Thrown when attempting to add an asset that is already enabled in the registry.
    error AssetAlreadyEnabled();
    /// @notice Thrown when attempting to perform an operation on an asset that is not enabled in the registry.
    error AssetNotEnabled();
    /// @notice Thrown when attempting to set the asset state to an invalid state.
    error AssetInvalidStateUpdate();

    /**
     * @notice Initializes the AssetRegistry contract
     * @dev Sets up initial roles for admin and manager
     * @param admin The address to be granted the DEFAULT_ADMIN_ROLE
     * @dev Reverts if:
     *      - The admin address is zero (Errors.ZeroAddress)
     */
    // slither-disable-next-line locked-ether
    constructor(address admin) payable {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_MANAGER_ROLE, admin);
    }

    /**
     * @notice Adds a new asset to the registry
     * @dev Only callable by accounts with the MANAGER_ROLE
     * @param asset The address of the asset to be added
     * @dev Reverts if:
     *      - The caller doesn't have the MANAGER_ROLE (OpenZeppelin's AccessControl)
     *      - The asset address is zero (Errors.ZeroAddress)
     *      - The asset is already enabled (AssetAlreadyEnabled)
     */
    function addAsset(address asset) external onlyRole(_MANAGER_ROLE) {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (_assetRegistry[asset].state != AssetState.DISABLED) revert AssetAlreadyEnabled();

        _assetRegistry[asset] = AssetStatus({ state: AssetState.ENABLED });
        emit AddAsset(asset);
    }

    /**
     * @notice Sets the state of an asset in the registry
     * @dev Only callable by accounts with the MANAGER_ROLE
     * @param asset The address of the asset to update
     * @param newState The new state to set (ENABLED or PAUSED)
     * @dev Reverts if:
     *      - The caller doesn't have the MANAGER_ROLE (OpenZeppelin's AccessControl)
     *      - The asset address is zero (Errors.ZeroAddress)
     *      - The asset is not enabled in the registry (AssetNotEnabled)
     *      - The new state is invalid (AssetInvalidStateUpdate)
     */
    function setAssetState(address asset, AssetState newState) external onlyRole(_MANAGER_ROLE) {
        if (asset == address(0)) revert Errors.ZeroAddress();
        AssetStatus memory status = _assetRegistry[asset];
        if (status.state == AssetState.DISABLED) revert AssetNotEnabled();
        if (newState == AssetState.DISABLED || newState == status.state) revert AssetInvalidStateUpdate();

        status.state = newState;
        _assetRegistry[asset] = status;
        emit SetAssetState(asset, newState);
    }

    /**
     * @notice Retrieves the status of an asset
     * @dev Returns the status of the asset. For non-existent assets, returns state as DISABLED
     * @param asset The address of the asset to query
     * @return AssetStatus The status of the asset
     */
    function getAssetStatus(address asset) external view returns (AssetStatus memory) {
        return _assetRegistry[asset];
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { Errors } from "src/libraries/Errors.sol";

/**
 * @title AssetRegistry
 * @dev Manages the registration and status of assets in the system.
 * @notice This contract provides functionality to add and pause assets, with role-based access control.
 */
contract AssetRegistry is AccessControlEnumerable {
    /**
     * Structs
     */
    struct AssetStatus {
        /// @dev Indicates whether the asset is enabled in the registry.
        bool enabled;
        /// @dev Indicates whether the asset is currently paused.
        bool paused;
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

    /// @dev Emitted when an asset is paused in the registry.
    event PauseAsset(address indexed asset);

    /**
     * Errors
     */
    /// @notice Thrown when attempting to add an asset that is already enabled in the registry.
    error AssetAlreadyEnabled();
    /// @notice Thrown when attempting to perform an operation on an asset that is not enabled in the registry.
    error AssetNotEnabled();
    /// @notice Thrown when attempting to pause an asset that is already in a paused state.
    error AssetAlreadyPaused();

    /**
     * @notice Initializes the AssetRegistry contract
     * @dev Sets up initial roles for admin and manager
     * @param admin The address to be granted the DEFAULT_ADMIN_ROLE
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
     */
    function addAsset(address asset) external onlyRole(_MANAGER_ROLE) {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (_assetRegistry[asset].enabled) revert AssetAlreadyEnabled();

        _assetRegistry[asset] = AssetStatus({ enabled: true, paused: false });
        emit AddAsset(asset);
    }

    /**
     * @notice Pauses an asset in the registry
     * @dev Only callable by accounts with the MANAGER_ROLE
     * @param asset The address of the asset to be paused
     */
    function pauseAsset(address asset) external onlyRole(_MANAGER_ROLE) {
        if (asset == address(0)) revert Errors.ZeroAddress();
        AssetStatus storage status = _assetRegistry[asset];
        if (!status.enabled) revert AssetNotEnabled();
        if (status.paused) revert AssetAlreadyPaused();

        status.paused = true;
        emit PauseAsset(asset);
    }

    /**
     * @notice Retrieves the status of an asset
     * @dev Returns default values (false, false) for non-existent assets
     * @param asset The address of the asset to query
     * @return enabled Whether the asset is enabled in the registry
     * @return paused Whether the asset is currently paused
     */
    function getAssetStatus(address asset) external view returns (bool enabled, bool paused) {
        AssetStatus memory status = _assetRegistry[asset];
        return (status.enabled, status.paused);
    }
}

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
    enum AssetStatus {
        /// @notice Asset is disabled and cannot be used in the system
        DISABLED,
        /// @notice Asset is enabled and can be used normally in the system
        ENABLED,
        /// @notice Asset is paused and cannot be used until unpaused
        PAUSED
    }

    /// Structs
    struct AssetData {
        uint32 indexPlusOne;
        AssetStatus status;
    }

    /**
     * Constants
     */
    /// @dev Role responsible for managing assets in the registry.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev Maximum number of assets that can be registered in the system.
    uint256 private constant _MAX_ASSETS = 255;

    /**
     * State variables
     */
    /// @dev Array of assets registered in the system.
    address[] private _assetList;
    /// @dev Mapping from asset address to AssetData struct containing the asset's index and status.
    mapping(address asset => AssetData) private _assetRegistry;

    /**
     * Events
     */
    /// @dev Emitted when a new asset is added to the registry.
    event AddAsset(address indexed asset);
    /// @dev Emitted when an asset's status is updated.
    event SetAssetStatus(address indexed asset, AssetStatus status);

    /**
     * Errors
     */
    /// @notice Thrown when attempting to add an asset that is already enabled in the registry.
    error AssetAlreadyEnabled();
    /// @notice Thrown when attempting to perform an operation on an asset that is not enabled in the registry.
    error AssetNotEnabled();
    /// @notice Thrown when attempting to set the asset status to an invalid status.
    error AssetInvalidStatusUpdate();
    /// @notice Thrown when attempting to add an asset when the maximum number of assets has been reached.
    error MaxAssetsReached();

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
        AssetData storage assetData = _assetRegistry[asset];
        if (assetData.indexPlusOne > 0) revert AssetAlreadyEnabled();
        uint256 assetLength = _assetList.length;
        if (assetLength == _MAX_ASSETS) revert MaxAssetsReached();

        _assetList.push(asset);
        assetData.indexPlusOne = uint32(assetLength + 1);
        assetData.status = AssetStatus.ENABLED;
        emit AddAsset(asset);
    }

    /**
     * @notice Sets the status of an asset in the registry
     * @dev Only callable by accounts with the MANAGER_ROLE
     * @param asset The address of the asset to update
     * @param newStatus The new status to set (ENABLED or PAUSED)
     * @dev Reverts if:
     *      - The caller doesn't have the MANAGER_ROLE (OpenZeppelin's AccessControl)
     *      - The asset address is zero (Errors.ZeroAddress)
     *      - The asset is not enabled in the registry (AssetNotEnabled)
     *      - The new status is invalid (AssetInvalidStatusUpdate)
     */
    function setAssetStatus(address asset, AssetStatus newStatus) external onlyRole(_MANAGER_ROLE) {
        if (asset == address(0)) revert Errors.ZeroAddress();
        AssetData storage assetData = _assetRegistry[asset];
        if (assetData.indexPlusOne == 0) revert AssetNotEnabled();
        if (newStatus == AssetStatus.DISABLED || assetData.status == newStatus) revert AssetInvalidStatusUpdate();

        assetData.status = newStatus;
        emit SetAssetStatus(asset, newStatus);
    }

    /**
     * @notice Retrieves the status of an asset
     * @dev Returns the status of the asset. For non-existent assets, returns status as DISABLED
     * @param asset The address of the asset to query
     * @return AssetStatus The status of the asset
     */
    function getAssetStatus(address asset) external view returns (AssetStatus) {
        AssetData storage assetData = _assetRegistry[asset];
        if (assetData.indexPlusOne == 0) return AssetStatus.DISABLED;
        return assetData.status;
    }

    /// @notice Counts the number of set bits in a bit flag using Brian Kernighan's algorithm.
    /// @param bitFlag The bit flag to count the number of set bits.
    /// @return count The number of set bits in the bit flag.
    function _popCount(uint256 bitFlag) private pure returns (uint256 count) {
        unchecked {
            for (; bitFlag != 0; ++count) {
                bitFlag &= bitFlag - 1;
            }
        }
    }

    /// @notice Retrieves the list of assets in the registry. Parameter bitFlag is used to filter the assets.
    /// @param bitFlag The bit flag to filter the assets.
    /// @return assets The list of assets in the registry.
    function getAssets(uint256 bitFlag) external view returns (address[] memory assets) {
        uint256 maxLength = _assetList.length;
        // If the bit flag is longer than the number of assets, truncate it
        bitFlag = bitFlag & ((1 << maxLength) - 1);

        // Initialize the return array
        assets = new address[](_popCount(bitFlag));
        uint256 index = 0;

        // Iterate through the assets and populate the return array
        for (uint256 i; i < maxLength && bitFlag != 0;) {
            if (bitFlag & 1 != 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                assets[index++] = _assetList[i];
            }
            bitFlag >>= 1;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Retrieves the addresses of all assets in the registry without any filtering.
    /// @return assets The list of addresses of all assets in the registry.
    function getAllAssets() external view returns (address[] memory) {
        return _assetList;
    }
}

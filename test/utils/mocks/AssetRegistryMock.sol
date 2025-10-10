// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AssetRegistryMock
/// @notice Mock implementation of AssetRegistry for testing
/// @dev This mock provides the getAssets and hasPausedAssets functionality used by Cove contracts
contract AssetRegistryMock {
    // Mock assets for different bit flags
    mapping(uint256 => address[]) public mockAssets;

    // Mock paused assets
    mapping(address => bool) public mockPausedAssets;

    // Mock asset metadata
    mapping(address => bytes) public mockAssetMetadata;

    // Mock asset decimals
    mapping(address => uint8) public mockAssetDecimals;

    address[] all_assets;

    event MockAssetsSet(uint256 indexed bitFlag, address[] assets);
    event MockPausedAssetSet(address indexed asset, bool paused);

    /// @notice Set mock assets for a bit flag
    /// @param bitFlag The bit flag
    /// @param assets The assets array
    function setMockAssets(uint256 bitFlag, address[] memory assets) external {
        mockAssets[bitFlag] = assets;
        emit MockAssetsSet(bitFlag, assets);
    }

    /// @notice Set mock paused asset
    /// @param asset The asset address
    /// @param paused The paused status
    function setMockPausedAsset(address asset, bool paused) external {
        mockPausedAssets[asset] = paused;
        emit MockPausedAssetSet(asset, paused);
    }

    /// @notice Set mock asset metadata
    /// @param asset The asset address
    /// @param metadata The asset metadata
    function setMockAssetMetadata(address asset, bytes memory metadata) external {
        mockAssetMetadata[asset] = metadata;
    }

    /// @notice Set mock asset decimals
    /// @param asset The asset address
    /// @param decimals The number of decimals
    function setMockAssetDecimals(address asset, uint8 decimals) external {
        mockAssetDecimals[asset] = decimals;
    }

    function addAsset(address asset, uint256 bitFlag, bytes memory metadata, uint8 decimals) external {
        mockAssets[bitFlag].push(asset);
        mockAssetMetadata[asset] = metadata;
        mockAssetDecimals[asset] = decimals;
        all_assets.push(asset);
    }

    /// @notice Get assets for a bit flag
    /// @param bitFlag The bit flag
    /// @return The assets array
    function getAssets(uint256 bitFlag) external view returns (address[] memory) {
        address[] memory assets = mockAssets[bitFlag];
        require(assets.length > 0, "No assets set for bit flag");
        return assets;
    }

    /// @notice Retrieves the addresses of all assets in the registry without any filtering.
    /// @return assets The list of addresses of all assets in the registry.
    function getAllAssets() external view returns (address[] memory) {
        return all_assets;
    }

    /// @notice Check if any assets are paused for a bit flag
    /// @param bitFlag The bit flag
    /// @return True if any assets are paused
    function hasPausedAssets(uint256 bitFlag) external view returns (bool) {
        address[] memory assets = mockAssets[bitFlag];
        for (uint256 i = 0; i < assets.length; i++) {
            if (mockPausedAssets[assets[i]]) {
                return true;
            }
        }
        return false;
    }

    /// @notice Check if a specific asset is paused
    /// @param asset The asset address
    /// @return True if the asset is paused
    function isAssetPaused(address asset) external view returns (bool) {
        return mockPausedAssets[asset];
    }

    /// @notice Get asset metadata
    /// @param asset The asset address
    /// @return The asset metadata
    function getAssetMetadata(address asset) external view returns (bytes memory) {
        return mockAssetMetadata[asset];
    }

    /// @notice Get asset decimals
    /// @param asset The asset address
    /// @return The number of decimals
    function getAssetDecimals(address asset) external view returns (uint8) {
        return mockAssetDecimals[asset];
    }

    /// @notice Get asset count for a bit flag
    /// @param bitFlag The bit flag
    /// @return The number of assets
    function getAssetCount(uint256 bitFlag) external view returns (uint256) {
        address[] memory assets = mockAssets[bitFlag];
        return assets.length;
    }

    /// @notice Get asset at index for a bit flag
    /// @param bitFlag The bit flag
    /// @param index The asset index
    /// @return The asset address
    function getAssetAtIndex(uint256 bitFlag, uint256 index) external view returns (address) {
        address[] memory assets = mockAssets[bitFlag];
        require(index < assets.length, "Asset index out of bounds");
        return assets[index];
    }

    /// @notice Check if asset is registered for a bit flag
    /// @param bitFlag The bit flag
    /// @param asset The asset address
    /// @return True if asset is registered
    function isAssetRegistered(uint256 bitFlag, address asset) external view returns (bool) {
        address[] memory assets = mockAssets[bitFlag];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == asset) {
                return true;
            }
        }
        return false;
    }

    /// @notice Get all paused assets for a bit flag
    /// @param bitFlag The bit flag
    /// @return The array of paused asset addresses
    function getPausedAssets(uint256 bitFlag) external view returns (address[] memory) {
        address[] memory assets = mockAssets[bitFlag];
        address[] memory pausedAssets = new address[](assets.length);
        uint256 pausedCount = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            if (mockPausedAssets[assets[i]]) {
                pausedAssets[pausedCount] = assets[i];
                pausedCount++;
            }
        }

        // Resize array to actual paused count
        address[] memory result = new address[](pausedCount);
        for (uint256 i = 0; i < pausedCount; i++) {
            result[i] = pausedAssets[i];
        }

        return result;
    }
}

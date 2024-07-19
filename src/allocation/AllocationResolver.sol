// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AssetRegistry } from "src/AssetRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";

abstract contract AllocationResolver {
    address public immutable assetRegistry;

    constructor(address assetRegistry_) {
        if (assetRegistry_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        assetRegistry = assetRegistry_;
    }

    /// @notice Returns the target weights of the assets in the basket. The sum of the weights should be 1e18.
    /// @param basket The address of the basket.
    /// @return The target weights of the assets in the basket.
    function getTargetWeights(address basket) public view virtual returns (uint256[] memory) { }

    /// @notice Returns whether the resolver supports the given bit flag, representing a list of assets.
    /// @param bitFlag The bit flag representing a list of assets.
    /// @return Whether the resolver supports the given bit flag.
    function supportsBitFlag(uint256 bitFlag) public view virtual returns (bool) { }

    /// @notice Returns whether the resolver supports the given assets. The order of the assets should be preserved.
    /// @dev On-chain usage of this function is discouraged due to the gas cost related to looking up the assets.
    /// @param assets The addresses of the assets.
    /// @return Whether the resolver supports the given assets.
    function supportsAssets(address[] memory assets) public view virtual returns (bool) {
        return supportsBitFlag(AssetRegistry(assetRegistry).getAssetsBitFlag(assets));
    }
}

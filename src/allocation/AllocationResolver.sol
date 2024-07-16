// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

abstract contract AllocationResolver {
    /// @notice Returns the target weights of the assets in the basket. The sum of the weights should be 1e18.
    /// @param basket The address of the basket.
    /// @return The target weights of the assets in the basket.
    function getTargetWeights(address basket) public view virtual returns (uint256[] memory) { }

    /// @notice Returns whether the resolver supports the given assets. The order of the assets should be preserved.
    /// @param assets The addresses of the assets.
    /// @return Whether the resolver supports the given assets.
    function supportsAssets(address[] memory assets) public view virtual returns (bool) { }
}

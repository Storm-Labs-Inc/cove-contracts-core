// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/// @title WeightStrategy
/// @notice Abstract contract for weight strategies. Weight strategies are contracts that determine the target
/// weights of assets. The sum of the weights should be 1e18.
abstract contract WeightStrategy {
    /// @notice Verifies whether the given target weights of the assets is valid for the given bit flag.
    /// @param bitFlag The bit flag representing a list of assets.
    /// @param targetWeights The target weights of the assets in the basket.
    /// @return The target weights of the assets in the basket.
    function verifyTargetWeights(
        uint256 bitFlag,
        uint256[] calldata targetWeights
    )
        public
        view
        virtual
        returns (bool);

    /// @notice Returns whether the strategy supports the given bit flag, representing a list of assets.
    /// @param bitFlag The bit flag representing a list of assets.
    /// @return Whether the strategy supports the given bit flag.
    function supportsBitFlag(uint256 bitFlag) public view virtual returns (bool);
}

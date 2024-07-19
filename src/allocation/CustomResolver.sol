// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { BasketToken } from "./../BasketToken.sol";
import { AllocationResolver } from "./AllocationResolver.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title CustomAllocationResolver
/// @notice A custom allocation resolver that allows manually setting target weights for a basket.
/// @dev Inherits from AllocationResolver and AccessControlEnumerable for role-based access control.
contract CustomAllocationResolver is AllocationResolver, AccessControlEnumerable {
    /// @dev Mapping to store target weights for each asset index in the bit flag
    mapping(uint256 assetIndexInBitFlag => uint256) private _targetWeight;

    /// @notice The supported bit flag for this resolver
    uint256 public immutable supportedBitFlag;

    /// @dev Role identifier for the manager role
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @dev Error thrown when an unsupported bit flag is used
    error UnsupportedBitFlag();
    /// @dev Error thrown when the length of weights array doesn't match the number of assets
    error InvalidWeightsLength();
    /// @dev Error thrown when the sum of weights doesn't equal 1e18 (100%)
    error WeightsSumMismatch();

    /// @notice Constructs the CustomAllocationResolver
    /// @param assetRegistry_ Address of the asset registry
    /// @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE and MANAGER_ROLE
    /// @param bitFlag The supported bit flag for this resolver
    constructor(address assetRegistry_, address admin, uint256 bitFlag) payable AllocationResolver(assetRegistry_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_MANAGER_ROLE, admin);
        supportedBitFlag = bitFlag;
    }

    /// @notice Sets the target weights for the assets
    /// @param targetWeights Array of target weights corresponding to each asset
    /// @dev Only callable by accounts with MANAGER_ROLE
    function setTargetWeights(uint256[] memory targetWeights) public onlyRole(_MANAGER_ROLE) {
        if (targetWeights.length != _popCount(supportedBitFlag)) {
            revert InvalidWeightsLength();
        }

        uint256 sum;
        for (uint256 i = 0; i < targetWeights.length; i++) {
            sum += targetWeights[i];
        }
        if (sum != 1e18) {
            revert WeightsSumMismatch();
        }

        for (uint256 i = 0; i < targetWeights.length; i++) {
            _targetWeight[i] = targetWeights[i];
        }
    }

    /// @notice Returns the target weights for a given bit flag
    /// @param bitFlag The bit flag representing a list of assets
    /// @return An array of target weights corresponding to the assets in the bit flag
    function getTargetWeights(uint256 bitFlag) public view returns (uint256[] memory) {
        if (!supportsBitFlag(bitFlag)) {
            revert UnsupportedBitFlag();
        }

        uint256[] memory filteredWeights = new uint256[](_popCount(bitFlag));
        uint256 filteredIndex = 0;

        for (uint256 i = 0; i < 256; i++) {
            if ((bitFlag & (1 << i)) != 0) {
                filteredWeights[filteredIndex] = _targetWeight[i];
                filteredIndex++;
            }
        }

        return filteredWeights;
    }

    /// @notice Returns the target weights of the assets in the basket
    /// @param basket The address of the basket
    /// @return An array of target weights for the assets in the basket
    function getTargetWeights(address basket) public view override returns (uint256[] memory) {
        uint256 basketBitFlag = BasketToken(basket).bitFlag();
        uint256[] memory targetWeights = getTargetWeights(basketBitFlag);

        uint256 sum;
        for (uint256 i = 0; i < targetWeights.length; i++) {
            sum += targetWeights[i];
        }

        if (sum != 1e18) {
            uint256[] memory normalizedWeights = new uint256[](targetWeights.length);
            for (uint256 i = 0; i < targetWeights.length; i++) {
                normalizedWeights[i] = (targetWeights[i] * 1e18) / sum;
            }
            return normalizedWeights;
        }

        return targetWeights;
    }

    /// @notice Returns whether the resolver supports the given bit flag, representing a list of assets
    /// @param bitFlag The bit flag representing a list of assets
    /// @return A boolean indicating whether the resolver supports the given bit flag
    function supportsBitFlag(uint256 bitFlag) public view override returns (bool) {
        return (supportedBitFlag & bitFlag) == bitFlag;
    }

    /// @dev Counts the number of set bits in a uint256
    /// @param x The uint256 to count set bits in
    /// @return The number of set bits
    function _popCount(uint256 x) private pure returns (uint256) {
        x -= (x >> 1) & 0x5555555555555555555555555555555555555555555555555555555555555555;
        x = (x & 0x3333333333333333333333333333333333333333333333333333333333333333)
            + ((x >> 2) & 0x3333333333333333333333333333333333333333333333333333333333333333);
        x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
        return (x * 0x0101010101010101010101010101010101010101010101010101010101010101) >> 248;
    }
}

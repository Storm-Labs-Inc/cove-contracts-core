// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { WeightStrategy } from "./WeightStrategy.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { BitFlag } from "src/libraries/BitFlag.sol";

/// @title ManagedWeightStrategy
/// @notice A custom weight strategy that allows manually setting target weights for a basket.
/// @dev Inherits from WeightStrategy and AccessControlEnumerable for role-based access control.
contract ManagedWeightStrategy is WeightStrategy, AccessControlEnumerable {
    /// @notice The target weights for all assets in the supported bit flag
    uint256[] public targetWeights;

    /// @notice The supported bit flag for this strategy
    uint256 public immutable supportedBitFlag;

    /// @dev Role identifier for the manager role
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev Precision for weights. All getTargetWeights() results should sum up to _WEIGHT_PRECISION.
    uint256 private constant _WEIGHT_PRECISION = 1e18;

    /// @dev Error thrown when an unsupported bit flag is used
    error UnsupportedBitFlag();
    /// @dev Error thrown when the length of weights array doesn't match the number of assets
    error InvalidWeightsLength();
    /// @dev Error thrown when the sum of weights doesn't equal _WEIGHT_PRECISION (100%)
    error WeightsSumMismatch();

    /// @notice Constructs the ManagedWeightStrategy
    /// @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE and MANAGER_ROLE
    /// @param bitFlag The supported bit flag for this strategy
    // slither-disable-next-line locked-ether
    constructor(address admin, uint256 bitFlag) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_MANAGER_ROLE, admin);
        supportedBitFlag = bitFlag;
    }

    /// @notice Sets the target weights for the assets
    /// @param newTargetWeights Array of target weights corresponding to each asset
    /// @dev Only callable by accounts with MANAGER_ROLE
    function setTargetWeights(uint256[] calldata newTargetWeights) external onlyRole(_MANAGER_ROLE) {
        uint256 assetCount = BitFlag.popCount(supportedBitFlag);
        if (newTargetWeights.length != assetCount) {
            revert InvalidWeightsLength();
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < assetCount;) {
            sum += newTargetWeights[i];
            unchecked {
                ++i;
            }
        }
        if (sum != _WEIGHT_PRECISION) {
            revert WeightsSumMismatch();
        }

        targetWeights = newTargetWeights;
    }

    /// @notice Returns the raw target weights for a given bit flag
    /// @param bitFlag The bit flag representing a list of assets
    /// @return filteredWeights An array of target weights corresponding to the assets in the bit flag
    function getTargetWeights(uint256 bitFlag) public view override returns (uint256[] memory filteredWeights) {
        if (!supportsBitFlag(bitFlag)) {
            revert UnsupportedBitFlag();
        }

        if (bitFlag == 0) {
            return filteredWeights;
        }

        // If there are no assets in the bit flag, return an empty array
        if (bitFlag == 0) {
            return filteredWeights;
        }
        uint256 assetCount = BitFlag.popCount(bitFlag);
        filteredWeights = new uint256[](assetCount);

        uint256 filteredIndex = 0;
        uint256 sum = 0;

        for (uint256 i = 0; i < 256;) {
            unchecked {
                if ((bitFlag & (1 << i)) != 0) {
                    // Overflow not possible: maximum value of sum <= _WEIGHT_PRECISION
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    sum += filteredWeights[filteredIndex] = targetWeights[i];
                    ++filteredIndex;
                }
                ++i;
            }
        }

        if (sum != _WEIGHT_PRECISION) {
            if (sum != 0) {
                // TODO: Implement a more sophisticated way to handle this case
                // For now, we distribute the remaining weight to the first asset
                uint256 remaining = _WEIGHT_PRECISION;
                for (uint256 i = 1; i < assetCount;) {
                    unchecked {
                        // Overflow not possible: filteredWeights[i] <= remaining <= _WEIGHT_PRECISION
                        // Divisiion by zero not possible: sum != 0
                        remaining -= filteredWeights[i] = (filteredWeights[i] * _WEIGHT_PRECISION) / sum;
                        ++i;
                    }
                }
                filteredWeights[0] = remaining;
            } else {
                // TODO: Implement a more sophisticated way to handle this case
                // If the sum of weights is 0, we set the first asset to 100%
                filteredWeights[0] = _WEIGHT_PRECISION;
            }
        }

        return filteredWeights;
    }

    /// @notice Returns whether the strategy supports the given bit flag, representing a list of assets
    /// @param bitFlag The bit flag representing a list of assets
    /// @return A boolean indicating whether the strategy supports the given bit flag
    function supportsBitFlag(uint256 bitFlag) public view override returns (bool) {
        return (supportedBitFlag & bitFlag) == bitFlag;
    }
}

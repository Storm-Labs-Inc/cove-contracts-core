// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { WeightStrategy } from "./WeightStrategy.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { BitFlag } from "src/libraries/BitFlag.sol";
import { Errors } from "src/libraries/Errors.sol";

/// @title ManagedWeightStrategy
/// @notice A custom weight strategy that allows manually setting target weights for a basket.
/// @dev Inherits from WeightStrategy and AccessControlEnumerable for role-based access control.
contract ManagedWeightStrategy is WeightStrategy, AccessControlEnumerable {
    /// @notice Mapping of the hash of the target weights for each bit flag
    mapping(uint256 rebalanceEpoch => mapping(uint256 bitFlag => bytes32 hash)) public targetWeightsHash;

    /// @dev Role identifier for the manager role
    bytes32 internal constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev Precision for weights. All getTargetWeights() results should sum up to _WEIGHT_PRECISION.
    uint256 internal constant _WEIGHT_PRECISION = 1e18;

    address internal immutable _basketManager;

    /// @dev Error thrown when an unsupported bit flag is used
    error UnsupportedBitFlag();
    /// @dev Error thrown when the length of weights array doesn't match the number of assets
    error InvalidWeightsLength();
    /// @dev Error thrown when the sum of weights doesn't equal _WEIGHT_PRECISION (100%)
    error WeightsSumMismatch();

    /// @notice Event emitted when the target weights are updated
    event TargetWeightsUpdated(uint256 indexed bitFlag, bytes32 indexed hash, uint256[] newWeights);

    /// @notice Constructs the ManagedWeightStrategy
    /// @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE and MANAGER_ROLE
    // slither-disable-next-line locked-ether
    constructor(address admin, address basketManager) payable {
        if (admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (basketManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_MANAGER_ROLE, admin);
        _basketManager = basketManager;
    }

    /// @notice Sets the target weights for the assets
    /// @param newTargetWeights Array of target weights corresponding to each asset
    /// @dev Only callable by accounts with MANAGER_ROLE
    function setTargetWeights(uint256 bitFlag, uint256[] calldata newTargetWeights) external onlyRole(_MANAGER_ROLE) {
        uint256 assetCount = BitFlag.popCount(bitFlag);
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
        bytes32 weightsHash = keccak256(abi.encode(newTargetWeights));
        emit TargetWeightsUpdated(bitFlag, weightsHash, newTargetWeights);
        targetWeightsHash[bitFlag] = weightsHash;
    }

    /// @notice Verifies whether the given target weights of the assets is valid for the given bit flag.
    /// If the weights for the bit flag are not explicitly set, it falls back to a default mechanism based on the root
    /// bitFlag's weights.
    /// @param bitFlag The bit flag representing a list of assets.
    /// @param targetWeights The target weights of the assets in the basket.
    /// @return bool True if the weights are valid, false otherwise.
    function verifyTargetWeights(
        uint256 bitFlag,
        uint256[] calldata targetWeights
    )
        public
        view
        override
        returns (bool)
    {
        uint256 assetCount = BitFlag.popCount(bitFlag);
        if (targetWeights.length != assetCount) {
            revert InvalidWeightsLength();
        }

        // Check if the weights for the given bitFlag are explicitly set
        bytes32 storedHash = targetWeightsHash[bitFlag];
        if (storedHash == bytes32(0)) {
            // If the weights are not explicitly set, fall back to the default mechanism
            return false;
        }
        // Verify the provided weights match the stored hash
        if (keccak256(abi.encode(targetWeights)) != storedHash) {
            return false;
        }
        return true;
    }

    /// @notice Returns whether the strategy supports the given bit flag, representing a list of assets
    /// @param bitFlag The bit flag representing a list of assets
    /// @return A boolean indicating whether the strategy supports the given bit flag
    function supportsBitFlag(uint256 bitFlag) public view virtual override returns (bool) {
        return targetWeightsHash[bitFlag] != bytes32(0);
    }
}

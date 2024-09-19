// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { WeightStrategy } from "./WeightStrategy.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { BasketManager } from "src/BasketManager.sol";
import { BitFlag } from "src/libraries/BitFlag.sol";
import { Errors } from "src/libraries/Errors.sol";
import { RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";

/// @title ManagedWeightStrategy
/// @notice A custom weight strategy that allows manually setting target weights for a basket.
/// @dev Inherits from WeightStrategy and AccessControlEnumerable for role-based access control.
contract ManagedWeightStrategy is WeightStrategy, AccessControlEnumerable {
    struct LastUpdated {
        uint40 epoch;
        uint40 timestamp;
    }

    /// @notice Mapping of the hash of the target weights for each bit flag
    mapping(uint256 rebalanceEpoch => mapping(uint256 bitFlag => uint64[] weights)) public targetWeights;
    mapping(uint256 bitFlag => LastUpdated) public lastUpdated;

    /// @dev Role identifier for the manager role
    bytes32 internal constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev Precision for weights. All getTargetWeights() results should sum up to _WEIGHT_PRECISION.
    uint64 internal constant _WEIGHT_PRECISION = 1e18;

    address internal immutable _basketManager;

    /// @dev Error thrown when an unsupported bit flag is used
    error UnsupportedBitFlag();
    /// @dev Error thrown when the length of weights array doesn't match the number of assets
    error InvalidWeightsLength();
    /// @dev Error thrown when the sum of weights doesn't equal _WEIGHT_PRECISION (100%)
    error WeightsSumMismatch();
    error NoTargetWeights();

    /// @notice Event emitted when the target weights are updated
    event TargetWeightsUpdated(uint256 indexed epoch, uint256 indexed bitFlag, uint64[] newWeights);

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

    /// @notice Sets the target weights for the assets for the next epoch. If a rebalance is already in progress, the
    /// next epoch value is used instead.
    /// @param newTargetWeights Array of target weights corresponding to each asset
    /// @dev Only callable by accounts with MANAGER_ROLE.
    function setTargetWeights(uint256 bitFlag, uint64[] calldata newTargetWeights) external onlyRole(_MANAGER_ROLE) {
        // Checks
        uint256 assetCount = BitFlag.popCount(bitFlag);
        if (newTargetWeights.length != assetCount) {
            revert InvalidWeightsLength();
        }
        if (assetCount < 2) {
            revert UnsupportedBitFlag();
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

        // View Interaction
        RebalanceStatus memory status = BasketManager(_basketManager).rebalanceStatus();
        uint40 epoch = status.epoch;
        if (status.status != Status.NOT_STARTED) {
            epoch += 1;
        }

        // Effects
        emit TargetWeightsUpdated(epoch, bitFlag, newTargetWeights);
        targetWeights[epoch][bitFlag] = newTargetWeights;
        lastUpdated[bitFlag] = LastUpdated(epoch, uint40(block.timestamp));
    }

    /// @notice Returns the target weights of the assets in the basket for the given bit flag. If the epoch has not been
    /// processed yet, the returned value may change until the rebalance is executed.
    /// @param epoch The epoch to get the target weights for
    /// @param bitFlag The bit flag representing a list of assets.
    /// @return weights True if the weights are valid, false otherwise.
    function getTargetWeights(uint40 epoch, uint256 bitFlag) public view override returns (uint64[] memory weights) {
        uint256 assetCount = BitFlag.popCount(bitFlag);
        if (assetCount < 2) {
            revert UnsupportedBitFlag();
        }
        weights = targetWeights[epoch][bitFlag];
        if (weights.length != assetCount) {
            // No target weights set for the given epoch and bit flag
            revert NoTargetWeights();
        }
    }

    /// @notice Returns whether the strategy supports the given bit flag, representing a list of assets
    /// @param bitFlag The bit flag representing a list of assets
    /// @return A boolean indicating whether the strategy supports the given bit flag
    function supportsBitFlag(uint256 bitFlag) public view virtual override returns (bool) {
        return lastUpdated[bitFlag].timestamp != 0;
    }
}

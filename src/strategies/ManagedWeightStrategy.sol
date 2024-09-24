// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { WeightStrategy } from "./WeightStrategy.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BitFlag } from "src/libraries/BitFlag.sol";
import { Errors } from "src/libraries/Errors.sol";
import { RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";

/// @title ManagedWeightStrategy
/// @notice A custom weight strategy that allows manual setting of target weights for a basket.
/// @dev Inherits from WeightStrategy and AccessControlEnumerable for role-based access control.
contract ManagedWeightStrategy is WeightStrategy, AccessControlEnumerable {
    /// @notice Struct to store the last updated epoch and timestamp for a bit flag.
    struct LastUpdated {
        uint40 epoch;
        uint40 timestamp;
    }

    /// @notice Maps each rebalance epoch and bit flag to the corresponding target weights.
    mapping(uint256 rebalanceEpoch => mapping(uint256 bitFlag => uint64[] weights)) public targetWeights;
    /// @notice Maps each bit flag to the last updated epoch and timestamp.
    mapping(uint256 bitFlag => LastUpdated) public lastUpdated;

    /// @dev Role identifier for the manager role.
    bytes32 internal constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev Precision for weights. All results from getTargetWeights() should sum to _WEIGHT_PRECISION.
    uint64 internal constant _WEIGHT_PRECISION = 1e18;
    /// @dev Address of the BasketManager contract associated with this strategy.
    // slither-disable-next-line uninitialized-state
    address internal immutable _basketManager;

    /// @dev Error thrown when an unsupported bit flag is provided.
    error UnsupportedBitFlag();
    /// @dev Error thrown when the length of the weights array does not match the number of assets.
    error InvalidWeightsLength();
    /// @dev Error thrown when the sum of the weights does not equal _WEIGHT_PRECISION (100%).
    error WeightsSumMismatch();
    /// @dev Error thrown when no target weights are set for the given epoch and bit flag.
    error NoTargetWeights();

    /// @notice Emitted when target weights are updated.
    /// @param epoch The epoch for which the weights are updated.
    /// @param bitFlag The bit flag representing the assets.
    /// @param newWeights The new target weights.
    event TargetWeightsUpdated(uint256 indexed epoch, uint256 indexed bitFlag, uint64[] newWeights);

    /// @notice Constructor for the ManagedWeightStrategy contract.
    /// @param admin The address of the admin who will have DEFAULT_ADMIN_ROLE and MANAGER_ROLE.
    /// @param basketManager The address of the BasketManager contract associated with this strategy.
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

    /// @notice Sets the target weights for the assets for the next epoch. If a rebalance is in progress, the weights
    /// will apply to the next epoch.
    /// @param bitFlag The bit flag representing the assets.
    /// @param newTargetWeights The array of target weights for each asset.
    /// @dev Only callable by accounts with the MANAGER_ROLE.
    function setTargetWeights(uint256 bitFlag, uint64[] calldata newTargetWeights) external onlyRole(_MANAGER_ROLE) {
        // Validate the number of assets matches the length of the weights array.
        uint256 assetCount = BitFlag.popCount(bitFlag);
        if (assetCount < 2) {
            revert UnsupportedBitFlag();
        }
        if (newTargetWeights.length != assetCount) {
            revert InvalidWeightsLength();
        }

        // Ensure the sum of the weights equals the required precision.
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

        // Determine the epoch to apply the weights to.
        RebalanceStatus memory status = BasketManager(_basketManager).rebalanceStatus();
        uint40 epoch = status.epoch;
        if (status.status != Status.NOT_STARTED) {
            epoch += 1;
        }

        // Update the target weights and emit the event.
        emit TargetWeightsUpdated(epoch, bitFlag, newTargetWeights);
        targetWeights[epoch][bitFlag] = newTargetWeights;
        lastUpdated[bitFlag] = LastUpdated(epoch, uint40(block.timestamp));
    }

    /// @notice Retrieves the target weights for the assets in the basket for a given epoch and bit flag.
    /// @param epoch The epoch to retrieve the target weights for.
    /// @param bitFlag The bit flag representing the assets.
    /// @return weights The target weights for the assets.
    function getTargetWeights(uint40 epoch, uint256 bitFlag) public view override returns (uint64[] memory weights) {
        uint256 assetCount = BitFlag.popCount(bitFlag);
        if (assetCount < 2) {
            revert UnsupportedBitFlag();
        }
        weights = targetWeights[epoch][bitFlag];
        if (weights.length != assetCount) {
            revert NoTargetWeights();
        }
    }

    /// @notice Checks if the strategy supports the given bit flag, representing a list of assets.
    /// @param bitFlag The bit flag representing the assets.
    /// @return A boolean indicating whether the strategy supports the given bit flag.
    function supportsBitFlag(uint256 bitFlag) public view virtual override returns (bool) {
        // slither-disable-next-line timestamp
        return lastUpdated[bitFlag].timestamp != 0;
    }
}

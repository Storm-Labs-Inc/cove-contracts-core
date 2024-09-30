// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

/// @notice Enum representing the status of a rebalance.
enum Status {
    // Rebalance has not started.
    NOT_STARTED,
    // Rebalance has been proposed.
    REBALANCE_PROPOSED,
    // Token swap has been proposed.
    TOKEN_SWAP_PROPOSED,
    // Token swap has been executed.
    TOKEN_SWAP_EXECUTED
}

/// @notice Struct representing the rebalance status.
struct RebalanceStatus {
    // Hash of the baskets proposed for rebalance.
    bytes32 basketHash;
    // Epoch of the rebalance.
    uint40 epoch;
    // Timestamp of the last action.
    uint40 timestamp;
    // Status of the rebalance.
    Status status;
}

/// @notice Struct representing the storage of the BasketManager contract.
struct BasketManagerStorage {
    /// @notice Address of the StrategyRegistry contract used to resolve and verify basket target weights.
    StrategyRegistry strategyRegistry;
    /// @notice Address of the EulerRouter contract used to fetch oracle quotes for swaps.
    EulerRouter eulerRouter;
    /// @notice Asset registry contract.
    address assetRegistry;
    /// @notice Address of the feeCollector contract which will receive the management fee.
    address feeCollector;
    /// @notice The current management fee in BPS denominated in 1e4.
    uint16 managementFee;
    /// @notice Address of the BasketToken implementation.
    address basketTokenImplementation;
    /// @notice Array of all basket tokens.
    address[] basketTokens;
    /// @notice Mapping of basket token to asset to balance.
    mapping(address basketToken => mapping(address asset => uint256 balance)) basketBalanceOf;
    /// @notice Mapping of basketId to basket address.
    mapping(bytes32 basketId => address basketToken) basketIdToAddress;
    /// @notice Mapping of basket token to assets.
    mapping(address basketToken => address[] basketAssets) basketAssets;
    /// @notice Mapping of basket token to basket asset to index plus one. 0 means the basket asset does not exist.
    mapping(address basketToken => mapping(address basketAsset => uint256 indexPlusOne)) basketAssetToIndexPlusOne;
    /// @notice Mapping of basket token to index plus one. 0 means the basket token does not exist.
    mapping(address basketToken => uint256 indexPlusOne) basketTokenToIndexPlusOne;
    /// @notice Mapping of basket token to pending redeeming shares.
    mapping(address basketToken => uint256 pendingRedeems) pendingRedeems;
    /// @notice Rebalance status.
    RebalanceStatus rebalanceStatus;
    /// @notice A hash of the latest external trades stored during proposeTokenSwap
    bytes32 externalTradesHash;
    /// @notice Current count of retries for the current rebalance epoch. May not exceed MAX_RETRIES.
    uint8 retryCount;
    /// @notice Address of the token swap adapter.
    address tokenSwapAdapter;
}

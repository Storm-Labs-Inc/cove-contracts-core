// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";
import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { Errors } from "src/libraries/Errors.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { BasketManagerStorage, RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";
import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

/// @title BasketManager
/// @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
/// in the BasketManagerUtils contract.
contract BasketManager is ReentrancyGuard, AccessControlEnumerable, Pausable {
    /// LIBRARIES ///
    using BasketManagerUtils for BasketManagerStorage;

    /// CONSTANTS ///
    /// @notice Manager role. Managers can create new baskets.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Pauser role.
    bytes32 private constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Rebalancer role. Rebalancers can propose rebalance, propose token swap, and execute token swap.
    bytes32 private constant _REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    /// @notice Basket token role. Given to the basket token contracts when they are created.
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    /// @dev Role given to a timelock contract that can set critical parameters.
    bytes32 private constant _TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    /// @notice Maximum management fee in BPS denominated in 1e4.
    uint16 private constant _MAX_MANAGEMENT_FEE = 10_000;

    /// STATE VARIABLES ///
    /// @notice Struct containing the BasketManagerUtils contract and other necessary data.
    BasketManagerStorage private _bmStorage;
    /// @notice Address of the TokenSwapAdapter contract used to execute token swaps.
    // slither-disable-next-line constable-states,uninitialized-state
    address public tokenSwapAdapter;
    /// @notice Mapping of order hashes to their validity status.
    mapping(bytes32 => bool) public isOrderValid;

    /// EVENTS ///
    /// @notice Emitted when the management fee is set.
    event ManagementFeeSet(uint16 oldFee, uint16 newFee);
    /// @notice Emitted when the TokenSwapAdapter contract is set.
    event TokenSwapAdapterSet(address oldAdapter, address newAdapter);

    /// ERRORS ///
    error TokenSwapNotProposed();
    error ExecuteTokenSwapFailed();
    error InvalidHash();
    error ExternalTradesHashMismatch();
    error MustWaitForRebalanceToComplete();
    error Unauthorized();
    error InvalidManagementFee();

    /// @notice Initializes the contract with the given parameters.
    /// @param basketTokenImplementation Address of the basket token implementation.
    /// @param eulerRouter_ Address of the oracle registry.
    /// @param strategyRegistry_ Address of the strategy registry.
    /// @param assetRegistry_ Address of the asset registry.
    /// @param admin Address of the admin.
    /// @param feeCollector_ Address of the fee collector.
    /// @param pauser Address of the pauser.
    constructor(
        address basketTokenImplementation,
        address eulerRouter_,
        address strategyRegistry_,
        address assetRegistry_,
        address admin,
        address feeCollector_,
        address pauser
    )
        payable
    {
        // Checks
        if (basketTokenImplementation == address(0)) revert Errors.ZeroAddress();
        if (eulerRouter_ == address(0)) revert Errors.ZeroAddress();
        if (strategyRegistry_ == address(0)) revert Errors.ZeroAddress();
        if (admin == address(0)) revert Errors.ZeroAddress();
        if (feeCollector_ == address(0)) revert Errors.ZeroAddress();
        if (pauser == address(0)) revert Errors.ZeroAddress();
        if (assetRegistry_ == address(0)) revert Errors.ZeroAddress();

        // Effects
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_PAUSER_ROLE, pauser);
        // Initialize the BasketManagerUtils struct
        _bmStorage.strategyRegistry = StrategyRegistry(strategyRegistry_);
        _bmStorage.eulerRouter = EulerRouter(eulerRouter_);
        _bmStorage.assetRegistry = assetRegistry_;
        _bmStorage.basketTokenImplementation = basketTokenImplementation;
        _bmStorage.feeCollector = feeCollector_;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Creates a new basket token with the given parameters.
    /// @param basketName Name of the basket.
    /// @param symbol Symbol of the basket.
    /// @param bitFlag Asset selection bitFlag for the basket.
    /// @param strategy Address of the strategy contract for the basket.
    function createNewBasket(
        string calldata basketName,
        string calldata symbol,
        address baseAsset,
        uint256 bitFlag,
        address strategy
    )
        external
        payable
        whenNotPaused
        onlyRole(_MANAGER_ROLE)
        returns (address basket)
    {
        basket = _bmStorage.createNewBasket(basketName, symbol, baseAsset, bitFlag, strategy);
        _grantRole(_BASKET_TOKEN_ROLE, basket);
    }

    /// @notice Returns the index of the basket token in the basketTokens array.
    /// @dev Reverts if the basket token does not exist.
    /// @param basketToken Address of the basket token.
    /// @return index Index of the basket token.
    function basketTokenToIndex(address basketToken) public view returns (uint256 index) {
        index = _bmStorage.basketTokenToIndex(basketToken);
    }

    /// @notice Returns the index of the basket asset in the basketAssets array.
    /// @dev Reverts if the basket asset does not exist.
    /// @param basketToken Address of the basket token.
    /// @param asset Address of the asset.
    /// @return index Index of the basket asset.
    function basketTokenToRebalanceAssetToIndex(
        address basketToken,
        address asset
    )
        public
        view
        returns (uint256 index)
    {
        index = _bmStorage.basketTokenToRebalanceAssetToIndex(basketToken, asset);
    }

    /// @notice Returns the number of basket tokens.
    /// @return Number of basket tokens.
    function numOfBasketTokens() public view returns (uint256) {
        return _bmStorage.basketTokens.length;
    }

    /// @notice Returns all basket token addresses.
    /// @return Array of basket token addresses.
    function basketTokens() external view returns (address[] memory) {
        return _bmStorage.basketTokens;
    }

    /// @notice Returns the basket token address with the given basketId.
    /// @param basketId Basket ID.
    function basketIdToAddress(bytes32 basketId) external view returns (address) {
        return _bmStorage.basketIdToAddress[basketId];
    }

    /// @notice Returns the balance of the given asset in the given basket.
    /// @param basketToken Address of the basket token.
    /// @param asset Address of the asset.
    /// @return Balance of the asset in the basket.
    function basketBalanceOf(address basketToken, address asset) external view returns (uint256) {
        return _bmStorage.basketBalanceOf[basketToken][asset];
    }

    /// @notice Returns the current rebalance status.
    /// @return Rebalance status struct with the following fields:
    ///   - basketHash: Hash of the baskets proposed for rebalance.
    ///   - timestamp: Timestamp of the last action.
    ///   - status: Status enum of the rebalance.
    function rebalanceStatus() external view returns (RebalanceStatus memory) {
        return _bmStorage.rebalanceStatus;
    }

    /// @notice Returns the hash of the external trades stored during proposeTokenSwap
    /// @return Hash of the external trades
    function externalTradesHash() external view returns (bytes32) {
        return _bmStorage.externalTradesHash;
    }

    /// @notice Returns the address of the basket token implementation.
    /// @return Address of the basket token implementation.
    function eulerRouter() external view returns (address) {
        return address(_bmStorage.eulerRouter);
    }

    /// @notice Returns the address of the feeCollector contract.
    /// @return Address of the feeCollector.
    function feeCollector() external view returns (address) {
        return address(_bmStorage.feeCollector);
    }

    /// @notice Returns the management fee in BPS denominated in 1e4.
    /// @return Management fee.
    function managementFee() external view returns (uint16) {
        return _bmStorage.managementFee;
    }

    /// @notice Returns the address of the strategy registry.
    /// @return Address of the strategy registry.
    function strategyRegistry() external view returns (address) {
        return address(_bmStorage.strategyRegistry);
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param basketsToRebalance Array of basket addresses to rebalance.
    function proposeRebalance(address[] calldata basketsToRebalance)
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _bmStorage.proposeRebalance(basketsToRebalance);
    }

    /// @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    function proposeTokenSwap(
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance
    )
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _bmStorage.proposeTokenSwap(internalTrades, externalTrades, basketsToRebalance);
    }

    /// @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
    /// @param externalTrades Array of external trades to execute.
    /// @param data Encoded data for the token swap.
    /// @dev This function can only be called after proposeTokenSwap.
    // slither-disable-next-line controlled-delegatecall
    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata data
    )
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (_bmStorage.rebalanceStatus.status != Status.TOKEN_SWAP_PROPOSED) {
            revert TokenSwapNotProposed();
        }
        address swapAdapter = tokenSwapAdapter;
        if (swapAdapter == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Check if the external trades match the hash from proposeTokenSwap
        if (keccak256(abi.encode(externalTrades)) != _bmStorage.externalTradesHash) {
            revert ExternalTradesHashMismatch();
        }
        _bmStorage.rebalanceStatus.status = Status.TOKEN_SWAP_EXECUTED;
        _bmStorage.rebalanceStatus.timestamp = uint40(block.timestamp);

        // slither-disable-next-line low-level-calls
        (bool success,) =
            swapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.executeTokenSwap, (externalTrades, data)));
        if (!success) {
            revert ExecuteTokenSwapFailed();
        }
    }

    /// @notice Sets the address of the TokenSwapAdapter contract used to execute token swaps.
    /// @param tokenSwapAdapter_ Address of the TokenSwapAdapter contract.
    /// @dev Only callable by the timelock.
    function setTokenSwapAdapter(address tokenSwapAdapter_) external onlyRole(_TIMELOCK_ROLE) {
        if (tokenSwapAdapter_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_bmStorage.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        emit TokenSwapAdapterSet(tokenSwapAdapter, tokenSwapAdapter_);
        tokenSwapAdapter = tokenSwapAdapter_;
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param basketsToRebalance Array of basket addresses proposed for rebalance.
    function completeRebalance(address[] calldata basketsToRebalance) external nonReentrant whenNotPaused {
        _bmStorage.completeRebalance(basketsToRebalance);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice Fallback redeem function to redeem shares when the rebalance is not in progress. Redeems the shares for
    /// each underlying asset in the basket pro-rata to the amount of shares redeemed.
    /// @param totalSupplyBefore Total supply of the basket token before the shares were burned.
    /// @param burnedShares Amount of shares burned.
    /// @param to Address to send the redeemed assets to.
    function proRataRedeem(
        uint256 totalSupplyBefore,
        uint256 burnedShares,
        address to
    )
        public
        nonReentrant
        whenNotPaused
        onlyRole(_BASKET_TOKEN_ROLE)
    {
        _bmStorage.proRataRedeem(totalSupplyBefore, burnedShares, to);
    }

    /// @notice Set the management fee to be given to the treausry on rebalance.
    /// @param managementFee_ Management fee in BPS denominated in 1e4.
    /// @dev Only callable by the timelock.
    function setManagementFee(uint16 managementFee_) external onlyRole(_TIMELOCK_ROLE) {
        if (managementFee_ > _MAX_MANAGEMENT_FEE) {
            revert InvalidManagementFee();
        }
        if (_bmStorage.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        emit ManagementFeeSet(_bmStorage.managementFee, managementFee_);
        _bmStorage.managementFee = managementFee_;
    }

    /// PAUSING FUNCTIONS ///

    /// @notice Pauses the contract. Callable by DEFAULT_ADMIN_ROLE or PAUSER_ROLE.
    function pause() external {
        if (!(hasRole(_PAUSER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))) {
            revert Unauthorized();
        }
        _pause();
    }

    /// @notice Unpauses the contract. Only callable by DEFAULT_ADMIN_ROLE.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}

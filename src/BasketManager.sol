// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { BasketToken } from "src/BasketToken.sol";

import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";
import { RebalancingUtils } from "src/libraries/RebalancingUtils.sol";

import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

import { Errors } from "src/libraries/Errors.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";

import { console } from "forge-std/console.sol";

/// @title BasketManager
/// @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
/// here.
contract BasketManager is ReentrancyGuard, AccessControlEnumerable, Pausable {
    // /// CONSTANTS ///
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Pauser role.
    bytes32 private constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Rebalancer role. Rebalancers can propose rebalance, propose token swap, and execute token swap.
    bytes32 private constant _REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    /// @notice Basket token role. Given to the basket token contracts when they are created.
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");

    // /// IMMUTABLES ///

    // /// STATE VARIABLES ///
    // TODO: make this immutable?
    address public rebalancingUtilsAddress;

    // /// EVENTS ///
    // TODO: should events be emitted here or in the utils contract?

    // /// ERRORS ///
    error Unauthorized();

    /// @notice Initializes the contract with the given parameters.
    /// @param basketTokenImplementation Address of the basket token implementation.
    /// @param eulerRouter_ Address of the oracle registry.
    /// @param strategyRegistry_ Address of the strategy registry.
    constructor(
        address basketTokenImplementation,
        address eulerRouter_,
        address strategyRegistry_,
        address rebalancingUtilsAddress_,
        address admin,
        address pauser
    )
        payable
    {
        // Checks
        if (rebalancingUtilsAddress_ == address(0)) revert Errors.ZeroAddress();

        // Effects
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_PAUSER_ROLE, pauser);
        rebalancingUtilsAddress = rebalancingUtilsAddress_;
        _delegateCall(
            abi.encodeCall(
                RebalancingUtils.initialize,
                (basketTokenImplementation, eulerRouter_, strategyRegistry_, rebalancingUtilsAddress)
            )
        );
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
        basket = abi.decode(
            _delegateCall(
                abi.encodeCall(RebalancingUtils.createNewBasket, (basketName, symbol, baseAsset, bitFlag, strategy))
            ),
            (address)
        );
        // TODO: keep roles in this contract?
        _grantRole(_BASKET_TOKEN_ROLE, basket);
    }

    /// @notice Returns the index of the basket token in the basketTokens array.
    /// @dev Reverts if the basket token does not exist.
    /// @param basketToken Address of the basket token.
    /// @return index Index of the basket token.
    function basketTokenToIndex(address basketToken) public returns (uint256 index) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.basketTokenToIndex, (basketToken))), (uint256));
    }

    /// @notice Returns the index of the basket asset in the basketAssets array.
    /// @dev Reverts if the basket asset does not exist.
    /// @param basketToken Address of the basket token.
    /// @param asset Address of the asset.
    /// @return index Index of the basket asset.
    function basketTokenToRebalanceAssetToIndex(address basketToken, address asset) public returns (uint256 index) {
        return abi.decode(
            _delegateCall(abi.encodeCall(RebalancingUtils.basketTokenToRebalanceAssetToIndex, (basketToken, asset))),
            (uint256)
        );
    }

    /// @notice Returns the number of basket tokens.
    /// @return Number of basket tokens.
    function numOfBasketTokens() public returns (uint256) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.numOfBasketTokens, ())), (uint256));
    }

    /// @notice Returns the current rebalance status.
    /// @return Rebalance status struct with the following fields:
    ///   - basketHash: Hash of the baskets proposed for rebalance.
    ///   - timestamp: Timestamp of the last action.
    ///   - status: Status enum of the rebalance.
    function rebalanceStatus() external returns (RebalancingUtils.RebalanceStatus memory) {
        return abi.decode(
            _delegateCall(abi.encodeCall(RebalancingUtils.rebalanceStatus, ())), (RebalancingUtils.RebalanceStatus)
        );
    }

    /// @notice Returns the hash of the external trades stored during proposeTokenSwap
    /// @return Hash of the external trades
    function externalTradesHash() external returns (bytes32) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.externalTradesHash, ())), (bytes32));
    }

    /// @notice Sets the rebalnce utils implementation address. Only callable by the admin.
    function setRebalanceUtilsImplementation(address rebalancingUtilsAddress_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rebalancingUtilsAddress_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        rebalancingUtilsAddress = rebalancingUtilsAddress_;
    }

    function eulerRouter() external returns (EulerRouter eulerRouter) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.eulerRouter, ())), (EulerRouter));
    }

    function strategyRegistry() external returns (address strategyRegistry) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.strategyRegistry, ())), (address));
    }

    // TODO: how to implement this view, previously basketManager.basketTokens(0) returns single address
    function basketTokens() external returns (address[] memory basketTokens) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.basketTokens, ())), (address[]));
    }

    function basketIdToAddress(bytes32 basketId) external returns (address basketToken) {
        return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.basketIdToAddress, (basketId))), (address));
    }

    function basketBalanceOf(address basketToken, address asset) external returns (uint256 balance) {
        return
            abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.basketBalanceOf, (basketToken, asset))), (uint256));
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param basketsToRebalance Array of basket addresses to rebalance.
    // slither-disable-next-line cyclomatic-complexity
    function proposeRebalance(
        address[] calldata basketsToRebalance
    )
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _delegateCall(abi.encodeCall(RebalancingUtils.proposeRebalance, (basketsToRebalance)));
    }

    /// @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    // slither-disable-next-line cyclomatic-complexity
    function proposeTokenSwap(
        RebalancingUtils.InternalTrade[] calldata internalTrades,
        RebalancingUtils.ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance
    )
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _delegateCall(
            abi.encodeCall(RebalancingUtils.proposeTokenSwap, (internalTrades, externalTrades, basketsToRebalance))
        );
    }

    /// @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
    /// @dev This function can only be called after proposeTokenSwap.
    function executeTokenSwap() external onlyRole(_REBALANCER_ROLE) nonReentrant whenNotPaused {
        // TODO: Implement the logic to execute token swap
        _delegateCall(abi.encodeCall(RebalancingUtils.executeTokenSwap, ()));
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param basketsToRebalance Array of basket addresses proposed for rebalance.
    function completeRebalance(address[] calldata basketsToRebalance) external nonReentrant whenNotPaused {
        _delegateCall(abi.encodeCall(RebalancingUtils.completeRebalance, (basketsToRebalance)));
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
        _delegateCall(abi.encodeCall(RebalancingUtils.proRataRedeem, (totalSupplyBefore, burnedShares, to)));
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

    /// INTERNAL FUNCTIONS ///

    // TODO: update comment
    /**
     * @dev Function used to delegate call the TokenizedStrategy with
     * certain `_calldata` and return any return values.
     *
     * This is used to setup the initial storage of the strategy, and
     * can be used by strategist to forward any other call to the
     * TokenizedStrategy implementation.
     *
     * @param _calldata The abi encoded calldata to use in delegatecall.
     * @return . The return value if the call was successful in bytes.
     */
    function _delegateCall(bytes memory _calldata) internal returns (bytes memory) {
        // Delegate call the tokenized strategy with provided calldata.
        (bool success, bytes memory result) = rebalancingUtilsAddress.delegatecall(_calldata);

        // If the call reverted. Return the error.
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        // Return the result.
        return result;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";

import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { Errors } from "src/libraries/Errors.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

/// @title BasketManager
/// @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
/// here.
contract BasketManager is ReentrancyGuard, AccessControlEnumerable, IERC1271, Pausable {
    /// LIBRARIES ///
    using BasketManagerUtils for BasketManagerUtils.StrategyData;

    BasketManagerUtils.StrategyData public basketManagerUtils;

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
    /// @notice Magic value for ERC1271 signature validation.
    bytes4 private constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// STATE VARIABLES ///
    /// @notice Address of the TokenSwapAdapter contract used to execute token swaps.
    address public tokenSwapAdapter;
    mapping(bytes32 => bool) public isOrderValid;

    /// ERRORS ///
    error ExecuteTokenSwapFailed();
    error InvalidHash();
    error ExternalTradesHashMismatch();
    error Unauthorized();

    /// @notice Initializes the contract with the given parameters.
    /// @param basketTokenImplementation Address of the basket token implementation.
    /// @param eulerRouter_ Address of the oracle registry.
    /// @param strategyRegistry_ Address of the strategy registry.
    constructor(
        address basketTokenImplementation,
        address eulerRouter_,
        address strategyRegistry_,
        address admin,
        address pauser
    )
        payable
    {
        // Checks
        if (basketTokenImplementation == address(0)) revert Errors.ZeroAddress();
        if (eulerRouter_ == address(0)) revert Errors.ZeroAddress();
        if (strategyRegistry_ == address(0)) revert Errors.ZeroAddress();
        if (admin == address(0)) revert Errors.ZeroAddress();
        if (pauser == address(0)) revert Errors.ZeroAddress();

        // Effects
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_PAUSER_ROLE, pauser);
        // Initialize the BasketManagerUtils struct
        basketManagerUtils.strategyRegistry = StrategyRegistry(strategyRegistry_);
        basketManagerUtils.eulerRouter = EulerRouter(eulerRouter_);
        basketManagerUtils.basketTokenImplementation = basketTokenImplementation;
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
        basket = basketManagerUtils.createNewBasket(basketName, symbol, baseAsset, bitFlag, strategy);
        _grantRole(_BASKET_TOKEN_ROLE, basket);
    }

    /// @notice Returns the index of the basket token in the basketTokens array.
    /// @dev Reverts if the basket token does not exist.
    /// @param basketToken Address of the basket token.
    /// @return index Index of the basket token.
    function basketTokenToIndex(address basketToken) public view returns (uint256 index) {
        index = basketManagerUtils.basketTokenToIndex(basketToken);
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
        index = basketManagerUtils.basketTokenToRebalanceAssetToIndex(basketToken, asset);
    }

    /// @notice Returns the number of basket tokens.
    /// @return Number of basket tokens.
    function numOfBasketTokens() public view returns (uint256) {
        return basketManagerUtils.basketTokens.length;
    }

    function basketTokens() external view returns (address[] memory) {
        return basketManagerUtils.basketTokens;
    }

    function basketIdToAddress(bytes32 bitflag) external view returns (address) {
        return basketManagerUtils.basketIdToAddress[bitflag];
    }

    function basketBalanceOf(address basketToken, address asset) external view returns (uint256) {
        return basketManagerUtils.basketBalanceOf[basketToken][asset];
    }

    /// @notice Returns the current rebalance status.
    /// @return Rebalance status struct with the following fields:
    ///   - basketHash: Hash of the baskets proposed for rebalance.
    ///   - timestamp: Timestamp of the last action.
    ///   - status: Status enum of the rebalance.
    function rebalanceStatus() external view returns (BasketManagerUtils.RebalanceStatus memory) {
        return basketManagerUtils.rebalanceStatus;
    }

    /// @notice Returns the hash of the external trades stored during proposeTokenSwap
    /// @return Hash of the external trades
    function externalTradesHash() external view returns (bytes32) {
        return basketManagerUtils.externalTradesHash;
    }

    /// @notice Returns the address of the basket token implementation.
    /// @return Address of the basket token implementation.
    function eulerRouter() external view returns (address) {
        return address(basketManagerUtils.eulerRouter);
    }

    /// @notice Returns the address of the strategy registry.
    /// @return Address of the strategy registry.
    function strategyRegistry() external view returns (address) {
        return address(basketManagerUtils.strategyRegistry);
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param basketsToRebalance Array of basket addresses to rebalance.
    function proposeRebalance(
        address[] calldata basketsToRebalance
    )
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        basketManagerUtils.proposeRebalance(basketsToRebalance);
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
        basketManagerUtils.proposeTokenSwap(internalTrades, externalTrades, basketsToRebalance);
    }

    /// @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
    /// @param data Encoded data for the token swap.
    /// @dev This function can only be called after proposeTokenSwap.
    // TODO: should this de done in the library? will delegatecall cause any issues?
    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata data
    )
        external
        onlyRole(_REBALANCER_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Check if the external trades match the hash from proposeTokenSwap
        if (keccak256(abi.encode(externalTrades)) != basketManagerUtils.externalTradesHash) {
            revert ExternalTradesHashMismatch();
        }
        (bool success, bytes memory ret) =
            tokenSwapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.executeTokenSwap, (externalTrades, data)));
        if (!success) {
            revert ExecuteTokenSwapFailed();
        }
        (bytes32[] memory hashes) = abi.decode(ret, (bytes32[]));
        uint256 length = hashes.length;
        for (uint256 i = 0; i < length;) {
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            isOrderValid[hashes[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the address of the TokenSwapAdapter contract used to execute token swaps.
    /// @param tokenSwapAdapter_ Address of the TokenSwapAdapter contract.
    /// @dev Only callable by the timelock.
    function setTokenSwapAdapter(address tokenSwapAdapter_) external onlyRole(_TIMELOCK_ROLE) {
        if (tokenSwapAdapter_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        tokenSwapAdapter = tokenSwapAdapter_;
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param basketsToRebalance Array of basket addresses proposed for rebalance.
    function completeRebalance(address[] calldata basketsToRebalance) external nonReentrant whenNotPaused {
        basketManagerUtils.completeRebalance(basketsToRebalance);
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
        basketManagerUtils.proRataRedeem(totalSupplyBefore, burnedShares, to);
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

    // ERC1271: CoWSwap will rely on this function to check if a submitted order is valid
    /// @notice Returns the magic value if the hash and the signature is valid.
    /// @param hash Hash of the order
    /// @return magicValue Magic value 0x1626ba7e if the hash and the signature is valid.
    /// @dev Refer to https://eips.ethereum.org/EIPS/eip-1271 for details.
    function isValidSignature(
        bytes32 hash,
        bytes calldata /* signature */
    )
        external
        view
        returns (bytes4 magicValue)
    {
        // TODO: Add CowSwap specific signature validation logic
        if (!isOrderValid[hash]) {
            // This hash is not valid in any context
            // TODO: Verify whether to return non magic value or revert
            revert InvalidHash();
        }
        magicValue = _ERC1271_MAGIC_VALUE;
    }
}

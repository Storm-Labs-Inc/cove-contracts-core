// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { BasketToken } from "src/BasketToken.sol";
import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
// TODO: Remove console import after testing
import { console } from "forge-std/console.sol";

/// @title BasketManager
/// @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
/// here.
contract BasketManager is ReentrancyGuard, AccessControlEnumerable, IERC1271 {
    /// LIBRARIES ///
    using SafeERC20 for IERC20;

    /// STRUCTS ///
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
        // Timestamp of the last action.
        uint40 timestamp;
        // Status of the rebalance.
        Status status;
    }

    /// @notice Struct representing a baskets ownership of an external trade.
    struct BasketTradeOwnership {
        // Address of the basket.
        address basket;
        // Ownership of the trade with a base of 1e18. An ownershipe of 1e18 means the basket owns the entire trade.
        uint96 tradeOwnership;
    }

    /// @notice Struct containing data for an internal trade.
    struct InternalTrade {
        // Address of the basket that is selling.
        address fromBasket;
        // Address of the token to sell.
        address sellToken;
        // Address of the token to buy.
        address buyToken;
        // Address of the basket that is buying.
        address toBasket;
        // Amount of the token to sell.
        uint256 sellAmount;
        // Minimum amount of the buy token that the trade results in. Used to check that the proposers oracle prices
        // are correct.
        uint256 minAmount;
        // Maximum amount of the buy token that the trade can result in.
        uint256 maxAmount;
    }

    /// @notice Struct containing data for an external trade.
    struct ExternalTrade {
        // Address of the token to sell.
        address sellToken;
        // Address of the token to buy.
        address buyToken;
        // Amount of the token to sell.
        uint256 sellAmount;
        // Minimum amount of the buy token that the trade results in.
        uint256 minAmount;
        // Array of basket trade ownerships.
        BasketTradeOwnership[] basketTradeOwnership;
    }

    /// @notice Struct containing data for an internal trade.
    struct InternalTradeInfo {
        // Index of the basket that is selling.
        uint256 fromBasketIndex;
        // Index of the basket that is buying.
        uint256 toBasketIndex;
        // Index of the token to sell.
        uint256 sellTokenAssetIndex;
        // Index of the token to buy.
        uint256 buyTokenAssetIndex;
        // Index of the buy token in the buying basket.
        uint256 toBasketBuyTokenIndex;
        // Index of the sell token in the buying basket.
        uint256 toBasketSellTokenIndex;
        // Amount of the buy token.
        uint256 buyAmount;
    }

    /// @notice Struct containing data for an external trade.
    struct ExternalTradeInfo {
        // Price of the sell token.
        uint256 sellTokenPrice;
        // Price of the buy token.
        uint256 buyTokenPrice;
        // Value of the sell token.
        uint256 sellValue;
        // Minimum amount of the buy token that the trade results in.
        uint256 internalMinAmount;
        // Difference between the internalMinAmount and the minAmount.
        uint256 diff;
    }

    /// @notice Struct containing data for basket ownership of an external trade.
    struct BasketOwnershipInfo {
        // Index of the basket.
        uint256 basketIndex;
        // Index of the buy token asset.
        uint256 buyTokenAssetIndex;
        // Index of the sell token asset.
        uint256 sellTokenAssetIndex;
    }

    /// CONSTANTS ///
    /// @notice ISO 4217 numeric code for USD, used as a constant address representation
    address public constant USD_ISO_4217_CODE = address(840);
    /// @notice Maximum number of basket tokens allowed to be created.
    uint256 public constant MAX_NUM_OF_BASKET_TOKENS = 256;
    /// @notice Maximum slippage allowed for token swaps.
    uint256 private constant _MAX_SLIPPAGE_BPS = 0.05e18; // .05%
    /// @notice Maximum deviation from target weights allowed for token swaps.
    uint256 private constant _MAX_WEIGHT_DEVIATION_BPS = 0.05e18; // .05%
    /// @notice Precision used for weight calculations.
    uint256 private constant _WEIGHT_PRECISION = 1e18;
    /// @notice Magic value for ERC1271 signature validation.
    uint256 private constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    /// @notice Manager role. Managers can create new baskets.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Pauser role.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Rebalancer role. Rebalancers can propose rebalance, propose token swap, and execute token swap.
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    /// @notice Basket token role. Given to the basket token contracts when they are created.
    bytes32 public constant BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    bytes32 private constant _TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    /// @notice Address of the StrategyRegistry contract used to resolve and verify basket target weights.
    StrategyRegistry public immutable strategyRegistry;

    /// STATE VARIABLES ///
    /// @notice Address of the TokenSwapAdapter contract used to execute token swaps.
    address public tokenSwapAdapter;
    /// @notice Array of all basket tokens.
    address[] public basketTokens;
    /// @notice Mapping of basket token to asset to balance.
    mapping(address basketToken => mapping(address asset => uint256 balance)) public basketBalanceOf;
    /// @notice Mapping of basketId to basket address.
    mapping(bytes32 basketId => address basketToken) public basketIdToAddress;
    /// @notice Mapping of basket token to assets.
    mapping(address basketToken => address[] basketAssets) public basketAssets;
    /// @notice Mapping of basket token to basket asset to index plus one. 0 means the basket asset does not exist.
    mapping(address basketToken => mapping(address basketAsset => uint256 indexPlusOne)) private
        _basketAssetToIndexPlusOne;
    /// @notice Mapping of basket token to index plus one. 0 means the basket token does not exist.
    mapping(address basketToken => uint256 indexPlusOne) private _basketTokenToIndexPlusOne;
    /// @notice Mapping of basket token to pending redeeming shares.
    mapping(address basketToken => uint256 pendingRedeems) public pendingRedeems;
    /// @notice Address of the BasketToken implementation.
    // TODO: add setter function for basketTokenImplementation
    // slither-disable-next-line immutable-states
    address public basketTokenImplementation;
    /// @notice Address of the EulerRouter contract used to fetch oracle quotes for swaps.
    // TODO: add setter function for EulerRouter
    // slither-disable-next-line immutable-states
    EulerRouter public eulerRouter;
    /// @notice Rebalance status.
    RebalanceStatus private _rebalanceStatus;
    /// @notice A hash of the latest external trades stored during proposeTokenSwap
    bytes32 private _externalTradesHash;

    /// EVENTS ///
    /// @notice Emitted when an internal trade is settled.
    /// @param internalTrade Internal trade that was settled.
    /// @param buyAmount Amount of the the from token that is traded.
    event InternalTradeSettled(InternalTrade internalTrade, uint256 buyAmount);
    /// @notice Emitted when an external trade is settled.
    /// @param externalTrade External trade that was settled.
    /// @param minAmount Minimum amount of the buy token that the trade results in.
    event ExternalTradeValidated(ExternalTrade externalTrade, uint256 minAmount);

    /// ERRORS ///
    error ZeroAddress();
    error ZeroTotalSupply();
    error ZeroBurnedShares();
    error CannotBurnMoreSharesThanTotalSupply();
    error BasketTokenNotFound();
    error AssetNotFoundInBasket();
    error BasketTokenAlreadyExists();
    error BasketTokenMaxExceeded();
    error ElementIndexNotFound();
    error StrategyRegistryDoesNotSupportStrategy();
    error BasketsMismatch();
    error BaseAssetMismatch();
    error AssetListEmpty();
    error MustWaitForRebalanceToComplete();
    error NoRebalanceInProgress();
    error TooEarlyToCompleteRebalance();
    error RebalanceNotRequired();
    error ExternalTradeSlippage();
    error TargetWeightsNotMet();
    error InternalTradeMinMaxAmountNotReached();
    error PriceOutOfSafeBounds();
    error IncorrectTradeTokenAmount();
    error ExecuteTokenSwapFailed();

    /// @notice Initializes the contract with the given parameters.
    /// @param basketTokenImplementation_ Address of the basket token implementation.
    /// @param eulerRouter_ Address of the oracle registry.
    /// @param strategyRegistry_ Address of the strategy registry.
    constructor(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address admin
    )
        payable
    {
        // Checks
        if (basketTokenImplementation_ == address(0)) revert ZeroAddress();
        if (eulerRouter_ == address(0)) revert ZeroAddress();
        if (strategyRegistry_ == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        // Effects
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        basketTokenImplementation = basketTokenImplementation_;
        eulerRouter = EulerRouter(eulerRouter_);
        strategyRegistry = StrategyRegistry(strategyRegistry_);
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
        onlyRole(MANAGER_ROLE)
        returns (address basket)
    {
        // Checks
        if (baseAsset == address(0)) {
            revert ZeroAddress();
        }
        uint256 basketTokensLength = basketTokens.length;
        if (basketTokensLength >= MAX_NUM_OF_BASKET_TOKENS) {
            revert BasketTokenMaxExceeded();
        }
        bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));
        if (basketIdToAddress[basketId] != address(0)) {
            revert BasketTokenAlreadyExists();
        }
        // Checks with external view calls
        if (!strategyRegistry.supportsBitFlag(bitFlag, strategy)) {
            revert StrategyRegistryDoesNotSupportStrategy();
        }
        // TODO: replace with AssetRegistry.getAssets(bitFlag) once AssetRegistry is implemented
        address[] memory assets = strategyRegistry.getAssets(bitFlag);
        if (assets.length == 0) {
            revert AssetListEmpty();
        }
        if (assets[0] != baseAsset) {
            revert BaseAssetMismatch();
        }
        // Effects
        basket = Clones.clone(basketTokenImplementation);
        _grantRole(BASKET_TOKEN_ROLE, basket);
        basketTokens.push(basket);
        basketAssets[basket] = assets;
        uint256 assetsLength = assets.length;
        for (uint256 j = 0; j < assetsLength;) {
            address asset = assets[j];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            _basketAssetToIndexPlusOne[basket][asset] = j + 1;
            unchecked {
                ++j;
            }
        }
        // Interactions
        basketIdToAddress[basketId] = basket;
        unchecked {
            // Overflow not possible: basketTokensLength is less than the constant MAX_NUM_OF_BASKET_TOKENS
            _basketTokenToIndexPlusOne[basket] = basketTokensLength + 1;
        }
        // Interactions
        // TODO: have owner address to pass to basket tokens on initialization
        BasketToken(basket).initialize(IERC20(baseAsset), basketName, symbol, bitFlag, strategy, address(0));
    }

    /// @notice Returns the index of the basket token in the basketTokens array.
    /// @dev Reverts if the basket token does not exist.
    /// @param basketToken Address of the basket token.
    /// @return index Index of the basket token.
    function basketTokenToIndex(address basketToken) public view returns (uint256 index) {
        index = _basketTokenToIndexPlusOne[basketToken];
        if (index == 0) {
            revert BasketTokenNotFound();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
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
        index = _basketAssetToIndexPlusOne[basketToken][asset];
        if (index == 0) {
            revert AssetNotFoundInBasket();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /// @notice Returns the number of basket tokens.
    /// @return Number of basket tokens.
    function numOfBasketTokens() public view returns (uint256) {
        return basketTokens.length;
    }

    /// @notice Returns the current rebalance status.
    /// @return Rebalance status struct with the following fields:
    ///   - basketHash: Hash of the baskets proposed for rebalance.
    ///   - timestamp: Timestamp of the last action.
    ///   - status: Status enum of the rebalance.
    function rebalanceStatus() external view returns (RebalanceStatus memory) {
        return _rebalanceStatus;
    }

    /// @notice Returns the hash of the external trades stored during proposeTokenSwap
    /// @return Hash of the external trades
    function externalTradesHash() external view returns (bytes32) {
        return _externalTradesHash;
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param basketsToRebalance Array of basket addresses to rebalance.
    // slither-disable-next-line cyclomatic-complexity
    function proposeRebalance(address[] calldata basketsToRebalance) external onlyRole(REBALANCER_ROLE) nonReentrant {
        // Checks
        // Revert if a rebalance is already in progress
        if (_rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        bool shouldRebalance = false;
        uint256 length = basketsToRebalance.length;
        for (uint256 i = 0; i < length;) {
            // slither-disable-start calls-loop
            address basket = basketsToRebalance[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            if (assetsLength == 0) {
                revert BasketTokenNotFound();
            }
            uint256[] memory balances = new uint256[](assetsLength);
            uint256[] memory targetBalances = new uint256[](assetsLength);
            uint256 basketValue = 0;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = basketBalanceOf[basket][assets[j]];

                // Rounding direction: down
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketValue += eulerRouter.getQuote(balances[j], assets[j], USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }

            // Process pending deposits and fulfill them
            uint256 totalSupply = BasketToken(basket).totalSupply();
            {
                uint256 pendingDeposit = BasketToken(basket).totalPendingDeposits();
                if (pendingDeposit > 0) {
                    // Assume the first asset listed in the basket is the base asset
                    // Round direction: down
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    uint256 pendingDepositValue = eulerRouter.getQuote(pendingDeposit, assets[0], USD_ISO_4217_CODE);
                    // Rounding direction: down
                    // Division-by-zero is not possible: basketValue is greater than 0
                    uint256 requiredDepositShares = basketValue > 0
                        ? FixedPointMathLib.fullMulDiv(pendingDepositValue, totalSupply, basketValue)
                        : pendingDeposit;
                    totalSupply += requiredDepositShares;
                    basketValue += pendingDepositValue;
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    basketBalanceOf[basket][assets[0]] = balances[0] = balances[0] + pendingDeposit;
                    // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
                    BasketToken(basket).fulfillDeposit(requiredDepositShares);
                }
            }

            // Pre-process redeems and calculate target balances
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256[] memory proposedTargetWeights = BasketToken(basket).getTargetWeights();
            {
                // Advances redeem epoch if there are pending redeems
                uint256 pendingRedeems_ = BasketToken(basket).preFulfillRedeem();
                uint256 requiredWithdrawValue = 0;

                // If there are pending redeems, calculate the required withdraw value
                // and store it in pendingWithdraw
                if (pendingRedeems_ > 0) {
                    shouldRebalance = true;
                    if (totalSupply > 0) {
                        // Rounding direction: down
                        // Division-by-zero is not possible: totalSupply is greater than 0
                        requiredWithdrawValue = basketValue * pendingRedeems_ / totalSupply;
                        if (requiredWithdrawValue > basketValue) {
                            requiredWithdrawValue = basketValue;
                        }
                        unchecked {
                            // Overflow not possible: requiredWithdrawValue is less than or equal to basketValue
                            basketValue -= requiredWithdrawValue;
                        }
                    }
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    pendingRedeems[basket] = pendingRedeems_;
                }

                // Update the target balances
                // Rounding direction: down
                // Division-by-zero is not possible: priceOfAssets[j] is greater than 0
                for (uint256 j = 0; j < assetsLength;) {
                    targetBalances[j] =
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    eulerRouter.getQuote(
                        FixedPointMathLib.fullMulDiv(proposedTargetWeights[j], basketValue, _WEIGHT_PRECISION),
                        USD_ISO_4217_CODE,
                        assets[j]
                    );

                    unchecked {
                        // Overflow not possible: j is less than assetsLength
                        ++j;
                    }
                }
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                targetBalances[0] += eulerRouter.getQuote(requiredWithdrawValue, USD_ISO_4217_CODE, assets[0]);
            }

            // Check if rebalance is needed
            for (uint256 j = 0; j < assetsLength;) {
                // Check if the target balance is different by more than 500 USD
                // NOTE: This implies it requires only one asset to be different by more than 500 USD
                //       to trigger a rebalance. This is placeholder logic and should be updated.
                // TODO: Update the logic to trigger a rebalance
                console.log("balances[%s]: %s", j, balances[j]);
                console.log("targetBalances[%s]: %s", j, targetBalances[j]);
                // TODO: verify what scale pyth returns for USD denominated value
                // TODO: is there a way to move this into the if statement that works with semgrep
                uint256 diff = MathUtils.diff(balances[j], targetBalances[j]);
                if (
                    eulerRouter.getQuote(diff, assets[j], USD_ISO_4217_CODE) > 500 // nosemgrep
                ) {
                    shouldRebalance = true;
                    break;
                }
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }
            // slither-disable-end calls-loop
            unchecked {
                // Overflow not possible: i is less than basketsToRebalance.length
                ++i;
            }
        }
        if (!shouldRebalance) {
            revert RebalanceNotRequired();
        }
        _rebalanceStatus.basketHash = keccak256(abi.encodePacked(basketsToRebalance));
        _rebalanceStatus.timestamp = uint40(block.timestamp);
        _rebalanceStatus.status = Status.REBALANCE_PROPOSED;
    }

    /// @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    // slither-disable-next-line cyclomatic-complexity
    function proposeTokenSwap(
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance
    )
        external
        onlyRole(REBALANCER_ROLE)
        nonReentrant
    {
        RebalanceStatus memory status = _rebalanceStatus;
        if (status.status != Status.REBALANCE_PROPOSED) {
            revert MustWaitForRebalanceToComplete();
        }
        // Ensure the basketsToRebalance matches the hash from proposeRebalance
        if (keccak256(abi.encodePacked(basketsToRebalance)) != status.basketHash) {
            revert BasketsMismatch();
        }

        uint256 numBaskets = basketsToRebalance.length;
        uint256[] memory totalBasketValue_ = new uint256[](numBaskets);
        uint256[][] memory afterTradeBasketAssetAmounts_ = new uint256[][](numBaskets);

        _initializeBasketData(basketsToRebalance, afterTradeBasketAssetAmounts_, totalBasketValue_);
        _settleInternalTrades(internalTrades, basketsToRebalance, afterTradeBasketAssetAmounts_);
        _validateExternalTrades(externalTrades, basketsToRebalance, totalBasketValue_, afterTradeBasketAssetAmounts_);
        _validateTargetWeights(basketsToRebalance, afterTradeBasketAssetAmounts_, totalBasketValue_);

        status.timestamp = uint40(block.timestamp);
        status.status = Status.TOKEN_SWAP_PROPOSED;
        _rebalanceStatus = status;
        _externalTradesHash = keccak256(abi.encode(externalTrades));
    }

    /// @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
    /// @param data Encoded data for the token swap.
    /// @dev This function can only be called after proposeTokenSwap.
    function executeTokenSwap(bytes calldata data) external onlyRole(REBALANCER_ROLE) nonReentrant {
        (bool success,) = tokenSwapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.executeTokenSwap, data));
        if (!success) {
            revert ExecuteTokenSwapFailed();
        }
    }

    /// @notice Sets the address of the TokenSwapAdapter contract used to execute token swaps.
    function setTokenSwapAdapter(address tokenSwapAdapter_) external onlyRole(_TIMELOCK_ROLE) {
        if (tokenSwapAdapter_ == address(0)) {
            revert ZeroAddress();
        }
        tokenSwapAdapter = tokenSwapAdapter_;
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param basketsToRebalance Array of basket addresses proposed for rebalance.
    function completeRebalance(address[] calldata basketsToRebalance) external nonReentrant {
        // Check if there is any rebalance in progress
        // slither-disable-next-line incorrect-equality
        if (_rebalanceStatus.status == Status.NOT_STARTED) {
            revert NoRebalanceInProgress();
        }
        // Check if the given baskets are the same as the ones proposed
        if (keccak256(abi.encodePacked(basketsToRebalance)) != _rebalanceStatus.basketHash) {
            revert BasketsMismatch();
        }
        // Check if the rebalance was proposed more than 15 minutes ago
        // slither-disable-next-line timestamp
        if (block.timestamp - _rebalanceStatus.timestamp < 15 minutes) {
            revert TooEarlyToCompleteRebalance();
        }
        // TODO: Add more checks for completion at different stages

        // Reset the rebalance status
        _rebalanceStatus.basketHash = bytes32(0);
        _rebalanceStatus.timestamp = uint40(block.timestamp);
        _rebalanceStatus.status = Status.NOT_STARTED;

        // Process the redeems for the given baskets
        for (uint256 i = 0; i < basketsToRebalance.length;) {
            // TODO: Make this more efficient by using calldata or by moving the logic to zk proof chain
            address basket = basketsToRebalance[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            uint256[] memory balances = new uint256[](assetsLength);
            uint256 basketValue;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = basketBalanceOf[basket][assets[j]];
                // Rounding direction: down
                // slither-disable-start calls-loop
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketValue += eulerRouter.getQuote(balances[j], assets[j], USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }

            // If there are pending redeems, process them
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 pendingRedeems_ = pendingRedeems[basket];
            if (pendingRedeems_ > 0) {
                // slither-disable-next-line costly-loop
                delete pendingRedeems[basket]; // nosemgrep
                // Assume the first asset listed in the basket is the base asset
                // Rounding direction: down
                // Division-by-zero is not possible: priceOfAssets[0] is greater than 0, totalSupply is greater than 0
                // when pendingRedeems is greater than 0
                uint256 rawAmount =
                    FixedPointMathLib.fullMulDiv(basketValue, pendingRedeems_, BasketToken(basket).totalSupply());
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 withdrawAmount = eulerRouter.getQuote(rawAmount, USD_ISO_4217_CODE, assets[0]);
                // slither-disable-end calls-loop
                if (withdrawAmount <= balances[0]) {
                    unchecked {
                        // Overflow not possible: withdrawAmount is less than or equal to balances[0]
                        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                        basketBalanceOf[basket][assets[0]] = balances[0] - withdrawAmount;
                    }
                    // slither-disable-next-line reentrancy-no-eth,calls-loop
                    IERC20(assets[0]).forceApprove(basket, withdrawAmount);
                    // ERC20.transferFrom is called in BasketToken.fulfillRedeem
                    // slither-disable-next-line reentrancy-no-eth,calls-loop
                    BasketToken(basket).fulfillRedeem(withdrawAmount);
                } else {
                    // TODO: Let the BasketToken contract handle failed redeems
                    // BasketToken(basket).failRedeem();
                }
            }
            unchecked {
                // Overflow not possible: i is less than basketsToRebalance.length
                ++i;
            }
        }
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
        onlyRole(BASKET_TOKEN_ROLE)
    {
        // Checks
        if (totalSupplyBefore == 0) {
            revert ZeroTotalSupply();
        }
        if (burnedShares == 0) {
            revert ZeroBurnedShares();
        }
        if (burnedShares > totalSupplyBefore) {
            revert CannotBurnMoreSharesThanTotalSupply();
        }
        if (to == address(0)) {
            revert ZeroAddress();
        }
        // Revert if a rebalance is in progress
        if (_rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        // Effects
        address basket = msg.sender;
        address[] storage assets = basketAssets[basket];
        uint256 assetsLength = assets.length;
        // Interactions
        for (uint256 i = 0; i < assetsLength;) {
            address asset = assets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 balance = basketBalanceOf[basket][asset];
            // Rounding direction: down
            // Division-by-zero is not possible: totalSupplyBefore is greater than 0
            uint256 amountToWithdraw = FixedPointMathLib.fullMulDiv(burnedShares, balance, totalSupplyBefore);
            if (amountToWithdraw > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketBalanceOf[basket][asset] = balance - amountToWithdraw;
                // Asset is an allowlisted ERC20 with no reentrancy problem in transfer
                // slither-disable-next-line reentrancy-no-eth
                IERC20(asset).safeTransfer(to, amountToWithdraw);
            }
            unchecked {
                // Overflow not possible: i is less than assetsLength
                ++i;
            }
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Returns the index of the element in the array.
    /// @dev Reverts if the element does not exist in the array.
    /// @param array Array to find the element in.
    /// @param element Element to find in the array.
    /// @return index Index of the element in the array.
    function _indexOf(address[] memory array, address element) internal view returns (uint256 index) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length;) {
            if (array[i] == element) {
                return i;
            }
            unchecked {
                // Overflow not possible: index is not 0
                ++i;
            }
        }
        revert ElementIndexNotFound();
    }

    /// PRIVATE FUNCTIONS ///

    /// @notice Internal function to initialize the basket data to be used while proposing a token swap.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    /// @param afterTradeBasketAssetAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @param totalBasketValue_ An initialized array of total basket values for each basket being rebalanced.
    function _initializeBasketData(
        address[] calldata basketsToRebalance,
        uint256[][] memory afterTradeBasketAssetAmounts_,
        uint256[] memory totalBasketValue_
    )
        private
        view
    {
        uint256 numBaskets = basketsToRebalance.length;

        for (uint256 i = 0; i < numBaskets;) {
            address basket = basketsToRebalance[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            afterTradeBasketAssetAmounts_[i] = new uint256[](assetsLength);
            for (uint256 j = 0; j < assetsLength;) {
                address asset = assets[j];
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 currentAssetAmount = basketBalanceOf[basket][asset];
                afterTradeBasketAssetAmounts_[i][j] = currentAssetAmount;
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                totalBasketValue_[i] += eulerRouter.getQuote(currentAssetAmount, asset, USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is less than numBaskets
                ++i;
            }
        }
    }

    /// @notice Internal function to settle internal trades.
    /// @param internalTrades Array of internal trades to execute.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    /// @param afterTradeBasketAssetAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @dev If the result of an internal trade is not within the provided minAmount or maxAmount, this function will
    /// revert.
    function _settleInternalTrades(
        InternalTrade[] calldata internalTrades,
        address[] calldata basketsToRebalance,
        uint256[][] memory afterTradeBasketAssetAmounts_
    )
        private
    {
        for (uint256 i = 0; i < internalTrades.length;) {
            InternalTrade memory trade = internalTrades[i];
            InternalTradeInfo memory info = InternalTradeInfo({
                fromBasketIndex: _indexOf(basketsToRebalance, trade.fromBasket),
                toBasketIndex: _indexOf(basketsToRebalance, trade.toBasket),
                sellTokenAssetIndex: basketTokenToRebalanceAssetToIndex(trade.fromBasket, trade.sellToken),
                buyTokenAssetIndex: basketTokenToRebalanceAssetToIndex(trade.fromBasket, trade.buyToken),
                toBasketBuyTokenIndex: basketTokenToRebalanceAssetToIndex(trade.toBasket, trade.buyToken),
                toBasketSellTokenIndex: basketTokenToRebalanceAssetToIndex(trade.toBasket, trade.sellToken),
                buyAmount: 0
            });
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.buyAmount = eulerRouter.getQuote(trade.sellAmount, trade.sellToken, trade.buyToken);

            if (info.buyAmount < trade.minAmount || trade.maxAmount < info.buyAmount) {
                revert InternalTradeMinMaxAmountNotReached();
            }
            // Settle the internal trades and track the balance changes
            if (trade.sellAmount > afterTradeBasketAssetAmounts_[info.fromBasketIndex][info.sellTokenAssetIndex]) {
                revert IncorrectTradeTokenAmount();
            }
            if (info.buyAmount > afterTradeBasketAssetAmounts_[info.toBasketIndex][info.toBasketBuyTokenIndex]) {
                revert IncorrectTradeTokenAmount();
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            basketBalanceOf[trade.fromBasket][trade.sellToken] = afterTradeBasketAssetAmounts_[info.fromBasketIndex][info
                .sellTokenAssetIndex] = basketBalanceOf[trade.fromBasket][trade.sellToken] - trade.sellAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            basketBalanceOf[trade.fromBasket][trade.buyToken] = afterTradeBasketAssetAmounts_[info.fromBasketIndex][info
                .buyTokenAssetIndex] = basketBalanceOf[trade.fromBasket][trade.buyToken] + info.buyAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            basketBalanceOf[trade.toBasket][trade.buyToken] = afterTradeBasketAssetAmounts_[info.toBasketIndex][info
                .toBasketBuyTokenIndex] = basketBalanceOf[trade.toBasket][trade.buyToken] - info.buyAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            basketBalanceOf[trade.toBasket][trade.sellToken] = afterTradeBasketAssetAmounts_[info.toBasketIndex][info
                .toBasketSellTokenIndex] = basketBalanceOf[trade.toBasket][trade.sellToken] + trade.sellAmount; // nosemgrep
            unchecked {
                ++i;
            }
            emit InternalTradeSettled(trade, info.buyAmount);
        }
    }

    /// @notice Internal function to validate external trades.
    /// @param externalTrades Array of external trades to be validated.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    /// @param totalBasketValue_ Array of total basket values in USD.
    /// @param afterTradeBasketAssetAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @dev If the result of an external trade is not within the _MAX_SLIPPAGE_BPS threshold of the minAmount, this
    function _validateExternalTrades(
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance,
        uint256[] memory totalBasketValue_,
        uint256[][] memory afterTradeBasketAssetAmounts_
    )
        private
    {
        for (uint256 i = 0; i < externalTrades.length;) {
            ExternalTrade memory trade = externalTrades[i];
            ExternalTradeInfo memory info;
            BasketOwnershipInfo memory ownershipInfo;
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 basketTradeOwnershipLength = trade.basketTradeOwnership.length;
            for (uint256 j = 0; j < basketTradeOwnershipLength;) {
                BasketTradeOwnership memory ownership = trade.basketTradeOwnership[j];
                ownershipInfo.basketIndex = _indexOf(basketsToRebalance, ownership.basket);
                ownershipInfo.buyTokenAssetIndex = basketTokenToRebalanceAssetToIndex(ownership.basket, trade.buyToken);
                ownershipInfo.sellTokenAssetIndex =
                    basketTokenToRebalanceAssetToIndex(ownership.basket, trade.sellToken);
                uint256 ownershipSellAmount =
                    FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, 1e18);
                uint256 ownershipBuyAmount =
                    FixedPointMathLib.fullMulDiv(trade.minAmount, ownership.tradeOwnership, 1e18);
                // Record changes in basket asset holdings due to the external trade
                if (
                    ownershipSellAmount
                        > afterTradeBasketAssetAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex]
                ) {
                    revert IncorrectTradeTokenAmount();
                }
                afterTradeBasketAssetAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex] =
                afterTradeBasketAssetAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex]
                    - ownershipSellAmount;
                afterTradeBasketAssetAmounts_[ownershipInfo.basketIndex][ownershipInfo.buyTokenAssetIndex] =
                afterTradeBasketAssetAmounts_[ownershipInfo.basketIndex][ownershipInfo.buyTokenAssetIndex]
                    + ownershipBuyAmount;
                // Update total basket value
                totalBasketValue_[ownershipInfo.basketIndex] = totalBasketValue_[ownershipInfo.basketIndex]
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                - eulerRouter.getQuote(ownershipSellAmount, trade.sellToken, USD_ISO_4217_CODE)
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                + eulerRouter.getQuote(ownershipBuyAmount, trade.buyToken, USD_ISO_4217_CODE);
                unchecked {
                    ++j;
                }
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.sellValue = eulerRouter.getQuote(trade.sellAmount, trade.sellToken, USD_ISO_4217_CODE);
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.internalMinAmount = eulerRouter.getQuote(info.sellValue, USD_ISO_4217_CODE, trade.buyToken);
            info.diff = MathUtils.diff(info.internalMinAmount, trade.minAmount);

            // Check if the given minAmount is within the _MAX_SLIPPAGE_BPS threshold of internalMinAmount
            if (info.internalMinAmount < trade.minAmount) {
                if (info.diff * 1e18 / info.internalMinAmount > _MAX_SLIPPAGE_BPS) {
                    revert ExternalTradeSlippage();
                }
            }
            unchecked {
                ++i;
            }
            emit ExternalTradeValidated(trade, info.internalMinAmount);
        }
    }

    /// @notice Internal function to validate the target weights for each basket have been met after all trades have
    /// been settled.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    /// @param afterTradeBasketAssetAmounts_ Array of asset amounts for each basket as updated with the results from
    /// both external and internal trades.
    /// @param totalBasketValue_ Array of total basket values in USD.
    /// @dev If target weights are not within the _MAX_WEIGHT_DEVIATION_BPS threshold, this function will revert.
    function _validateTargetWeights(
        address[] calldata basketsToRebalance,
        uint256[][] memory afterTradeBasketAssetAmounts_,
        uint256[] memory totalBasketValue_
    )
        private
        view
    {
        // Check if total weight change due to all trades is within the _MAX_WEIGHT_DEVIATION_BPS threshold
        for (uint256 i = 0; i < basketsToRebalance.length;) {
            address basket = basketsToRebalance[i];
            // slither-disable-next-line calls-loop
            uint256[] memory proposedTargetWeights = BasketToken(basket).getTargetWeights();
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 proposedTargetWeightsLength = proposedTargetWeights.length;
            for (uint256 j = 0; j < proposedTargetWeightsLength;) {
                address asset = assets[j];
                uint256 assetValueInUSD =
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                 eulerRouter.getQuote(afterTradeBasketAssetAmounts_[i][j], asset, USD_ISO_4217_CODE);
                // Rounding direction: down
                uint256 afterTradeWeight =
                    FixedPointMathLib.fullMulDiv(assetValueInUSD, _WEIGHT_PRECISION, totalBasketValue_[i]);
                if (MathUtils.diff(proposedTargetWeights[j], afterTradeWeight) > _MAX_WEIGHT_DEVIATION_BPS) {
                    console.log("basket, asset: ", basket, asset);
                    console.log("proposedTargetWeights[%s]: %s", j, proposedTargetWeights[j]);
                    console.log("afterTradeWeight: %s, usdValue: %s", afterTradeWeight, assetValueInUSD);
                    revert TargetWeightsNotMet();
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    // ERC1271: CoWSwap will rely on this function to check if a submitted order is valid
    function isValidSignature(
        bytes32 hash,
        bytes calldata /* signature */
    )
        external
        view
        returns (bytes4 magicValue)
    {
        // make a delegate call to swap adapter to check if the hash is valid
        bool isHashVerified = false;
        if (_basketManagerStorage().verifiedCowswapOrders[hash]) {
            // This hash is for CowSwap
        } else {
            // This hash is not valid in any context
            revert("unrecognized signature");
        }
        magicValue = _ERC1271_MAGIC_VALUE;
    }
}

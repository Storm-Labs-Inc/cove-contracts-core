// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { AllocationResolver } from "src/AllocationResolver.sol";
import { BasketToken } from "src/BasketToken.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";

import { console } from "forge-std/console.sol";

/**
 * @title BasketManager
 * @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
 * here.
 */
contract BasketManager is ReentrancyGuard, AccessControlEnumerable {
    /**
     * Libraries
     */
    using SafeERC20 for IERC20;

    /**
     * Structs
     */

    /**
     * @notice Enum representing the status of a rebalance.
     *   - NOT_STARTED: Rebalance has not started.
     *   - REBALANCE_PROPOSED: Rebalance has been proposed.
     *   - TOKEN_SWAP_PROPOSED: Token swap has been proposed.
     *   - TOKEN_SWAP_EXECUTED: Token swap has been executed.
     */
    enum Status {
        NOT_STARTED,
        REBALANCE_PROPOSED,
        TOKEN_SWAP_PROPOSED,
        TOKEN_SWAP_EXECUTED
    }

    /**
     * @notice Struct representing the rebalance status.
     *   - basketHash: Hash of the baskets proposed for rebalance.
     *   - timestamp: Timestamp of the last action.
     *   - status: Status of the rebalance.
     */
    struct RebalanceStatus {
        bytes32 basketHash;
        uint40 timestamp;
        Status status;
    }

    /**
     * @notice Struct representing a baskets ownership of an external trade.
     *   - basket: Address of the basket.
     *   - tradeOwnership: Ownership of the trade.
     */
    struct BasketTradeOwnership {
        address basket;
        uint96 tradeOwnership;
    }

    /* 
    * @notice Struct containing data for an internal trade.
    *   - fromBasket: Address of the basket that is selling.
    *   - sellToken: Address of the token to sell.
    *   - buyToken: Address of the token to buy.
    *   - toBasket: Address of the basket that is buying.
    *   - sellAmount: Amount of the token to sell.
    *   - minAmount: Minimum amount of the buy token that the trade results in. Used to check that the proposers
    oracle prices are correct.
    */
    struct InternalTrade {
        address fromBasket;
        address sellToken;
        address buyToken;
        address toBasket;
        uint256 sellAmount;
        uint256 minAmount;
    }
    // Example call data
    // [
    // 	BasketA, yUSDT, yDAI, BasketE, 200,
    // 	BasketB, sFRAX, yDAI, BasketE, 500
    // ]

    /*
    @ntoice Struct containing data for an external trade.
    *   - sellToken: Address of the token to sell.
    *   - buyToken: Address of the token to buy.
    *   - sellAmount: Amount of the token to sell.
    *   - minAmount: Minimum amount of the buy token that the trade results in.
    *   - basketTradeOwnership: Array of basket trade ownerships.
    */
    struct ExternalTrade {
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 minAmount;
        BasketTradeOwnership[] basketTradeOwnership;
    }

    // Example call data
    // [
    // 	yDAI, yUSDT, 100, [ {BasketE, 100%}],
    // 	sFRAX, yUSDT, 1000, [ {BasketC, 100%}],
    // 	sFRAX, yDAI, 500, [ {BasketB, 100%}],
    // 	yUSDC, yDAI, 1000, [ {BasketD, 50%}, {BasketA, 50%}]
    // ]

    /**
     * Constants
     */
    /// @notice Maximum number of basket tokens allowed to be created.
    uint256 public constant MAX_NUM_OF_BASKET_TOKENS = 256;
    /// @notice Maximum slippage allowed for token swaps.
    uint256 private constant _MAX_SLIPPAGE = 0.05e18; // .05%
    // @notice Maximum deviation from target weights allowed for token swaps.
    uint256 private constant _MAX_WEIGHT_DEVIATION = 0.05e18; // .05%
    /// @notice Manager role. Managers can create new baskets.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Pauser role.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Rebalancer role. Rebalancers can propose rebalance, propose token swap, and execute token swap.
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    /// @notice Basket token role. Given to the basket token contracts when they are created.
    bytes32 public constant BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");

    /**
     * State variables
     */
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
    // Prices are cached before propose tokenswap is called
    // TODO: remove in favor of a stored hash to compare against
    mapping(address token => uint256 price) internal _tokenPrices;
    // mapping(address => bool) internal _basketBeingTraded;
    // mapping(address basket => uint256 index) internal _basketBeingTradedIndexPlusOne;
    mapping(address => uint256) private _basketToRebalanceIndexPlusOne;

    /// @notice Address of the BasketToken implementation.
    // TODO: add setter function for basketTokenImplementation
    // slither-disable-next-line immutable-states
    address public basketTokenImplementation;
    /// @notice Address of the OracleRegistry contract used to fetch oracle values for assets.
    // TODO: add setter function for oracleRegistry
    // slither-disable-next-line immutable-states
    address public oracleRegistry;
    /// @notice Address of the AllocationResolver contract used to resolve allocations.
    // TODO: add setter function for allocationResolver
    // slither-disable-next-line immutable-states
    AllocationResolver public allocationResolver;
    /// @notice Rebalance status.
    RebalanceStatus private _rebalanceStatus;

    /**
     * Events
     */

    /**
     * Errors
     */
    error ZeroAddress();
    error ZeroTotalSupply();
    error ZeroBurnedShares();
    error CannotBurnMoreSharesThanTotalSupply();
    error BasketTokenNotFound();
    error AssetNotFoundInBasket();
    error BasketTokenAlreadyExists();
    error BasketTokenMaxExceeded();
    error AllocationResolverDoesNotSupportStrategy();
    error BasketsMismatch();
    error BaseAssetMismatch();
    error AssetListEmpty();
    error MustWaitForRebalanceToComplete();
    error NoRebalanceInProgress();
    error TooEarlyToCompleteRebalance();
    error RebalanceNotRequired();
    error ExternalTradeSlippage();
    error TargetWeightsNotMet();
    error InternalTradeMinAmountNotReached();

    /**
     * @notice Initializes the contract with the given parameters.
     * @param basketTokenImplementation_ Address of the basket token implementation.
     * @param oracleRegistry_ Address of the oracle registry.
     * @param allocationResolver_ Address of the allocation resolver.
     */
    constructor(
        address basketTokenImplementation_,
        address oracleRegistry_,
        address allocationResolver_,
        address admin
    )
        payable
    {
        // Checks
        if (basketTokenImplementation_ == address(0)) revert ZeroAddress();
        if (oracleRegistry_ == address(0)) revert ZeroAddress();
        if (allocationResolver_ == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        // Effects
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        basketTokenImplementation = basketTokenImplementation_;
        oracleRegistry = oracleRegistry_;
        allocationResolver = AllocationResolver(allocationResolver_);
    }

    /**
     * Public functions
     */

    /**
     * @notice Creates a new basket token with the given parameters.
     * @param basketName Name of the basket.
     * @param symbol Symbol of the basket.
     * @param bitFlag Asset selection bitFlag for the basket.
     * @param strategyId Strategy id for the basket.
     */
    function createNewBasket(
        string calldata basketName,
        string calldata symbol,
        address baseAsset,
        uint256 bitFlag,
        uint256 strategyId
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
        bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategyId));
        if (basketIdToAddress[basketId] != address(0)) {
            revert BasketTokenAlreadyExists();
        }
        // Checks with external view calls
        if (!allocationResolver.supportsStrategy(bitFlag, strategyId)) {
            revert AllocationResolverDoesNotSupportStrategy();
        }
        address[] memory assets = allocationResolver.getAssets(bitFlag);
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
        basketIdToAddress[basketId] = basket;
        unchecked {
            // Overflow not possible: basketTokensLength is less than the constant MAX_NUM_OF_BASKET_TOKENS
            _basketTokenToIndexPlusOne[basket] = basketTokensLength + 1;
        }
        // Interactions
        // TODO: have owner address to pass to basket tokens on initialization
        BasketToken(basket).initialize(IERC20(baseAsset), basketName, symbol, bitFlag, strategyId, address(0));
    }

    /**
     * @notice Returns the index of the basket token in the basketTokens array.
     * @dev Reverts if the basket token does not exist.
     * @param basketToken Address of the basket token.
     * @return index Index of the basket token.
     */
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

    /**
     * @notice Returns the index of the basket token in the basketToRebalance array.
     * @dev Reverts if the basket token does not exist.
     * @param basketToken Address of the basket token.
     * @return index Index of the basket token.
     */
    function basketTokenToReblanceToIndex(address basketToken) public view returns (uint256 index) {
        index = _basketToRebalanceIndexPlusOne[basketToken];
        if (index == 0) {
            revert BasketTokenNotFound();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /**
     * @notice Returns the index of the basket asset in the basketAssets array.
     * @dev Reverts if the basket asset does not exist.
     * @param basketToken Address of the basket token.
     * @param asset Address of the asset.
     * @return index Index of the basket asset.
     */
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

    /**
     * @notice Returns the number of basket tokens.
     * @return Number of basket tokens.
     */
    function numOfBasketTokens() public view returns (uint256) {
        return basketTokens.length;
    }

    /**
     * @notice Returns the current rebalance status.
     * @return Rebalance status struct with the following fields:
     *   - basketHash: Hash of the baskets proposed for rebalance.
     *   - timestamp: Timestamp of the last action.
     *   - status: Status enum of the rebalance.
     */
    function rebalanceStatus() external view returns (RebalanceStatus memory) {
        return _rebalanceStatus;
    }

    /**
     * @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
     * target balance and the current balance of any asset in the basket is more than 500 USD.
     * @param basketsToRebalance Array of basket addresses to rebalance.
     */
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
            uint256[] memory priceOfAssets = new uint256[](assetsLength);
            uint256 basketValue = 0;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = basketBalanceOf[basket][assets[j]];
                // TODO: Replace with an oracle call once the oracle is implemented
                // uint256 usdPrice = oracleRegistry.getPrice(assets[j]);
                // if (usdPrice == 0) {
                //     revert PriceOutOfSafeBounds();
                // }
                // priceOfAssets[j] = usdPrice;
                priceOfAssets[j] = 1e18;
                // Rounding direction: down
                basketValue += FixedPointMathLib.fullMulDiv(balances[j], priceOfAssets[j], 1e18);
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
                    // slither-disable-next-line divide-before-multiply
                    uint256 pendingDepositValue = FixedPointMathLib.fullMulDiv(pendingDeposit, priceOfAssets[0], 1e18);
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
            uint256[] memory proposedTargetWeights = allocationResolver.getTargetWeight(basket);
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
                        FixedPointMathLib.fullMulDiv(proposedTargetWeights[j], basketValue, priceOfAssets[j]);
                    unchecked {
                        // Overflow not possible: j is less than assetsLength
                        ++j;
                    }
                }
                targetBalances[0] += FixedPointMathLib.fullMulDiv(requiredWithdrawValue, 1e18, priceOfAssets[0]);
            }

            // Check if rebalance is needed
            for (uint256 j = 0; j < assetsLength;) {
                // Check if the target balance is different by more than 500 USD
                // NOTE: This implies it requires only one asset to be different by more than 500 USD
                //       to trigger a rebalance. This is placeholder logic and should be updated.
                // TODO: Update the logic to trigger a rebalance
                console.log("balances[%s]: %s", j, balances[j]);
                console.log("targetBalances[%s]: %s", j, targetBalances[j]);
                if (
                    FixedPointMathLib.fullMulDiv(MathUtils.diff(balances[j], targetBalances[j]), priceOfAssets[j], 1e18)
                        > 500
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

    /**
     * @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
     * If the proposed token swap results are not close to the target balances, this function will revert.
     * @dev This function can only be called after proposeRebalance.
     */
    function proposeTokenSwap(
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance
    )
        external
        onlyRole(REBALANCER_ROLE)
        nonReentrant
    {
        if (_rebalanceStatus.status != Status.REBALANCE_PROPOSED) {
            revert MustWaitForRebalance();
        }
        // Ensure the basketsToRebalance matches the hash from proposeRebalance
        if (keccak256(abi.encodePacked(basketsToRebalance)) != _rebalanceStatus.basketHash) {
            revert BasketsMismatch();
        }

        uint256 numBaskets = basketsToRebalance.length;
        uint256[] memory _totalBasketValue = new uint256[](numBaskets);
        uint256[][] memory _afterTradeBasketAssetAmounts = new uint256[][](numBaskets);
        for (uint256 i = 0; i < numBaskets;) {
            address basket = basketsToRebalance[i];
            address[] memory assets = basketAssets[basket];
            uint256 numAssets = assets.length;
            uint256[] memory _basketAssetAmounts = new uint256[](numAssets);
            _basketToRebalanceIndexPlusOne[basket] = i + 1;
            for (uint256 j = 0; j < numAssets;) {
                address asset = assets[j];
                _basketAssetToIndexPlusOne[basket][asset] = j + 1;
                _basketAssetAmounts[j] = basketBalanceOf[basket][asset];
                // TODO: Replace with an oracle call once the oracle is implemented
                // uint256 usdPrice = oracleRegistry.getPrice(assets[j]);
                // if (usdPrice == 0) {
                //     revert PriceOutOfSafeBounds();
                // }
                // _tokenPrices[asset] = usdPrice;
                _tokenPrices[asset] = 1e18;
                unchecked {
                    ++j;
                }
            }
            // Initialize this array with current asset amounts
            _afterTradeBasketAssetAmounts[i] = _basketAssetAmounts;
            _totalBasketValue[i] = _basketTotalValue(basket);
            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < internalTrades.length;) {
            InternalTrade memory trade = internalTrades[i];
            {
                address fromBasket = trade.fromBasket;
                uint256 frombasketIndex = basketTokenToReblanceToIndex(fromBasket);
                address toBasket = trade.toBasket;
                uint256 toBasketIndex = basketTokenToReblanceToIndex(toBasket);
                address sellToken = trade.sellToken;
                uint256 sellAmount = trade.sellAmount;
                address buyToken = trade.buyToken;
                // Below checks that the asset exists in the basket
                uint256 sellTokenAssetIndex = basketTokenToRebalanceAssetToIndex(fromBasket, sellToken);
                uint256 buyTokenAssetIndex = basketTokenToRebalanceAssetToIndex(fromBasket, buyToken);
                uint256 toBasketBuyTokenIndex = basketTokenToRebalanceAssetToIndex(toBasket, buyToken);
                uint256 toBasketSellTokenIndex = basketTokenToRebalanceAssetToIndex(toBasket, sellToken);
                uint256 sellTokenPrice = _tokenPrices[sellToken];
                uint256 buyTokenPrice = _tokenPrices[buyToken];
                uint256 buyAmount = (sellAmount * sellTokenPrice) / buyTokenPrice;
                uint256 fromBasketValue = _totalBasketValue[frombasketIndex];
                uint256 toBasketValue = _totalBasketValue[toBasketIndex];

                if (buyAmount < trade.minAmount) {
                    revert InternalTradeMinAmountNotReached();
                }
                // record the updated balances
                _afterTradeBasketAssetAmounts[frombasketIndex][sellTokenAssetIndex] =
                    _afterTradeBasketAssetAmounts[frombasketIndex][sellTokenAssetIndex] - sellAmount;
                _afterTradeBasketAssetAmounts[frombasketIndex][buyTokenAssetIndex] =
                    _afterTradeBasketAssetAmounts[frombasketIndex][buyTokenAssetIndex] + buyAmount;
                _afterTradeBasketAssetAmounts[toBasketIndex][toBasketBuyTokenIndex] =
                    _afterTradeBasketAssetAmounts[toBasketIndex][toBasketBuyTokenIndex] - buyAmount;
                _afterTradeBasketAssetAmounts[toBasketIndex][toBasketSellTokenIndex] =
                    _afterTradeBasketAssetAmounts[toBasketIndex][toBasketSellTokenIndex] + sellAmount;
                basketBalanceOf[fromBasket][sellToken] = basketBalanceOf[fromBasket][sellToken] - sellAmount;
                basketBalanceOf[fromBasket][buyToken] = basketBalanceOf[fromBasket][buyToken] + buyAmount;
                basketBalanceOf[toBasket][buyToken] = basketBalanceOf[toBasket][buyToken] - buyAmount;
                basketBalanceOf[toBasket][sellToken] = basketBalanceOf[toBasket][sellToken] + sellAmount;
            }
            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < externalTrades.length;) {
            ExternalTrade memory trade = externalTrades[i];
            {
                address buyToken = trade.buyToken;
                address sellToken = trade.sellToken;
                uint256 sellAmount = trade.sellAmount;
                uint256 sellTokenPrice = _tokenPrices[sellToken];
                uint256 buyTokenPrice = _tokenPrices[buyToken];
                uint256 sellValue = sellAmount * sellTokenPrice;
                uint256 internalMinAmount = sellValue / buyTokenPrice;

                // Check if the given minAmount is within the _MAX_SLIPPAGE threshold of internalMinAmount
                uint256 diff = MathUtils.diff(internalMinAmount, trade.minAmount);
                if (diff * 1e18 / internalMinAmount > _MAX_SLIPPAGE) {
                    revert ExternalTradeSlippage();
                }

                for (uint256 j = 0; j < trade.basketTradeOwnership.length;) {
                    address basket = trade.basketTradeOwnership[j].basket;
                    uint96 tradeOwnership = trade.basketTradeOwnership[j].tradeOwnership;
                    uint256 basketIndex = basketTokenToReblanceToIndex(basket);
                    uint256 buyTokenAssetIndex = basketTokenToRebalanceAssetToIndex(basket, buyToken);
                    uint256 sellTokenAssetIndex = basketTokenToRebalanceAssetToIndex(basket, sellToken);
                    // Record changes in basket asset holdings due to the external trade
                    _afterTradeBasketAssetAmounts[basketIndex][sellTokenAssetIndex] = _afterTradeBasketAssetAmounts[basketIndex][sellTokenAssetIndex]
                        - (sellAmount * 1e18) / tradeOwnership;
                    _afterTradeBasketAssetAmounts[basketIndex][buyTokenAssetIndex] = _afterTradeBasketAssetAmounts[basketIndex][buyTokenAssetIndex]
                        + (internalMinAmount * 1e18) / tradeOwnership;
                    unchecked {
                        ++j;
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        // Check if total weight change due to all trades is within the _MAX_WEIGHT_DEVIATION threshold
        for (uint256 i = 0; i < numBaskets;) {
            address basket = basketsToRebalance[i];
            uint256[] memory proposedTargetWeights = allocationResolver.getTargetWeight(basket);
            address[] memory assets = basketAssets[basket];
            for (uint256 j = 0; j < proposedTargetWeights.length;) {
                address asset = assets[j];
                uint256 afterTradeWeight =
                    _afterTradeBasketAssetAmounts[i][j] * _tokenPrices[asset] * 1e18 / _totalBasketValue[i];
                if (MathUtils.diff(proposedTargetWeights[j], afterTradeWeight) > _MAX_WEIGHT_DEVIATION) {
                    console.log("basket, asset: ", basket, asset);
                    console.log("proposedTargetWeights[%s]: %s", j, proposedTargetWeights[j]);
                    console.log("afterTradeWeight: %s", afterTradeWeight);
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
        _rebalanceStatus.timestamp = uint40(block.timestamp);
        _rebalanceStatus.status = Status.TOKEN_SWAP_PROPOSED;
    }

    function _calculateCurrentBasketWeights(address basket) internal view returns (uint256[] memory weights) {
        uint256[] memory values;
        uint256 totalUSDCValue = _basketTotalValue(basket);
        for (uint256 i = 0; i < values.length; i++) {
            weights[i] = values[i] * 1e18 / totalUSDCValue;
        }
    }

    function _basketTotalValue(address basket) internal view returns (uint256 totalUSDCValue) {
        address[] memory assets = basketAssets[basket];
        for (uint256 i = 0; i < assets.length; i++) {
            totalUSDCValue = totalUSDCValue + basketBalanceOf[basket][assets[i]] * _tokenPrices[assets[i]];
        }
    }

    /**
     * @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
     * @dev This function can only be called after proposeTokenSwap.
     */
    function executeTokenSwap() external onlyRole(REBALANCER_ROLE) nonReentrant {
        // TODO: Implement the logic to execute token swap
    }

    /**
     * @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than 15
     * minutes since the last action.
     * @param basketsToRebalance Array of basket addresses proposed for rebalance.
     */
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
            uint256[] memory priceOfAssets = new uint256[](assetsLength);
            uint256 basketValue;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = basketBalanceOf[basket][assets[j]];
                // TODO: Replace with an oracle call once the oracle is implemented
                // uint256 usdPrice = oracleRegistry.getPrice(assets[j]);
                // if (usdPrice == 0) {
                //     revert PriceOutOfSafeBounds();
                // }
                // priceOfAssets[j] = usdPrice;
                priceOfAssets[j] = 1e18;
                // Rounding direction: down
                basketValue += FixedPointMathLib.fullMulDiv(balances[j], priceOfAssets[j], 1e18);
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
                // slither-disable-next-line calls-loop
                uint256 withdrawAmount = FixedPointMathLib.fullMulDiv(
                    FixedPointMathLib.fullMulDiv(basketValue, 1e18, priceOfAssets[0]),
                    pendingRedeems_,
                    BasketToken(basket).totalSupply()
                );
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

    /*//////////////////////////////////////////////////////////////
                        FALLBACK REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fallback redeem function to redeem shares when the rebalance is not in progress. Redeems the shares for
     * each underlying asset in the basket pro-rata to the amount of shares redeemed.
     * @param totalSupplyBefore Total supply of the basket token before the shares were burned.
     * @param burnedShares Amount of shares burned.
     * @param to Address to send the redeemed assets to.
     */
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
}

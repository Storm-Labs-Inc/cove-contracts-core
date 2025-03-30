// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { BasketManagerStorage, RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

/// @title BasketManagerUtils
/// @notice Library containing utility functions for managing storage related to baskets, including creating new
/// baskets, proposing and executing rebalances, and settling internal and external token trades.
library BasketManagerUtils {
    using SafeERC20 for IERC20;

    /// STRUCTS ///
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
        // Amount of the buy token that is traded.
        uint256 netBuyAmount;
        // Amount of the sell token that is traded.
        uint256 netSellAmount;
        // Fee charged on the buy token on the trade.
        uint256 feeOnBuy;
        // Fee charged on the sell token on the trade.
        uint256 feeOnSell;
        // USD value of the sell token amount
        uint256 sellValue;
        // USD value of the fees charged on the trade
        uint256 feeValue;
    }

    /// CONSTANTS ///
    /// @notice ISO 4217 numeric code for USD, used as a constant address representation
    address private constant _USD_ISO_4217_CODE = address(840);
    /// @notice Maximum number of basket tokens allowed to be created.
    uint256 private constant _MAX_NUM_OF_BASKET_TOKENS = 256;
    /// @notice Precision used for weight calculations and slippage calculations.
    uint256 private constant _WEIGHT_PRECISION = 1e18;
    /// @notice Minimum time between rebalances in seconds.
    uint40 private constant _REBALANCE_COOLDOWN_SEC = 1 hours;

    /// EVENTS ///
    /// @notice Emitted when an internal trade is settled.
    /// @param internalTrade Internal trade that was settled.
    /// @param buyAmount Amount of the the from token that is traded.
    event InternalTradeSettled(InternalTrade internalTrade, uint256 buyAmount);
    /// @notice Emitted when swap fees are charged on an internal trade.
    /// @param asset Asset that the swap fee was charged in.
    /// @param amount Amount of the asset that was charged.
    event SwapFeeCharged(address indexed asset, uint256 amount);
    /// @notice Emitted when a rebalance is proposed for a set of baskets
    /// @param epoch Unique identifier for the rebalance, incremented each time a rebalance is proposed
    /// @param baskets Array of basket addresses to rebalance
    /// @param proposedTargetWeights Array of target weights for each basket
    /// @param basketAssets Array of assets in each basket
    /// @param basketHash Hash of the basket addresses and target weights for the rebalance
    event RebalanceProposed(
        uint40 indexed epoch,
        address[] baskets,
        uint64[][] proposedTargetWeights,
        address[][] basketAssets,
        bytes32 basketHash
    );
    /// @notice Emitted when a rebalance is completed.
    /// @param epoch Unique identifier for the rebalance, incremented each time a rebalance is completed
    event RebalanceCompleted(uint40 indexed epoch);
    /// @notice Emitted when a rebalance is retried.
    /// @param epoch Unique identifier for the rebalance, incremented each time a rebalance is completed
    /// @param retryCount Number of retries for the current rebalance epoch. On the first retry, this will be 1.
    event RebalanceRetried(uint40 indexed epoch, uint256 retryCount);

    /// ERRORS ///
    /// @notice Reverts when the address is zero.
    error ZeroAddress();
    /// @notice Reverts when the amount is zero.
    error ZeroAmount();
    /// @notice Reverts when the total supply of a basket token is zero.
    error ZeroTotalSupply();
    /// @notice Reverts when the amount of burned shares is zero.
    error ZeroBurnedShares();
    /// @notice Reverts when trying to burn more shares than the total supply.
    error CannotBurnMoreSharesThanTotalSupply();
    /// @notice Reverts when the requested basket token is not found.
    error BasketTokenNotFound();
    /// @notice Reverts when the requested asset is not found in the basket.
    error AssetNotFoundInBasket();
    /// @notice Reverts when trying to create a basket token that already exists.
    error BasketTokenAlreadyExists();
    /// @notice Reverts when the maximum number of basket tokens has been reached.
    error BasketTokenMaxExceeded();
    /// @notice Reverts when the requested element index is not found.
    error ElementIndexNotFound();
    /// @notice Reverts when the strategy registry does not support the given strategy.
    error StrategyRegistryDoesNotSupportStrategy();
    /// @notice Reverts when the baskets or target weights do not match the proposed rebalance.
    error BasketsMismatch();
    /// @notice Reverts when the base asset does not match the given asset.
    error BaseAssetMismatch();
    /// @notice Reverts when the asset is not found in the asset registry.
    error AssetListEmpty();
    /// @notice Reverts when a rebalance is in progress and the caller must wait for it to complete.
    error MustWaitForRebalanceToComplete();
    /// @notice Reverts when there is no rebalance in progress.
    error NoRebalanceInProgress();
    /// @notice Reverts when it is too early to complete the rebalance.
    error TooEarlyToCompleteRebalance();
    /// @notice Reverts when it is too early to propose a rebalance.
    error TooEarlyToProposeRebalance();
    /// @notice Reverts when a rebalance is not required.
    error RebalanceNotRequired();
    /// @notice Reverts when the external trade slippage exceeds the allowed limit.
    error ExternalTradeSlippage();
    /// @notice Reverts when the target weights are not met.
    error TargetWeightsNotMet();
    /// @notice Reverts when the minimum or maximum amount is not reached for an internal trade.
    error InternalTradeMinMaxAmountNotReached();
    /// @notice Reverts when the trade token amount is incorrect.
    error IncorrectTradeTokenAmount();
    /// @notice Reverts when given external trades do not match.
    error ExternalTradeMismatch();
    /// @notice Reverts when the delegatecall to the tokenswap adapter fails.
    error CompleteTokenSwapFailed();
    /// @notice Reverts when an asset included in a bit flag is not enabled in the asset registry.
    error AssetNotEnabled();
    /// @notice Reverts when no internal or external trades are provided for a rebalance.
    error CannotProposeEmptyTrades();
    /// @notice Reverts when the sum of tradeOwnerships do not match the _WEIGHT_PRECISION
    error OwnershipSumMismatch();
    /// @dev Reverts when the sell amount of an internal trade is zero.
    error InternalTradeSellAmountZero();
    /// @dev Reverts when the sell amount of an external trade is zero.
    error ExternalTradeSellAmountZero();

    /// @notice Creates a new basket token with the given parameters.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketName Name of the basket.
    /// @param symbol Symbol of the basket.
    /// @param bitFlag Asset selection bitFlag for the basket.
    /// @param strategy Address of the strategy contract for the basket.
    /// @return basket Address of the newly created basket token.
    function createNewBasket(
        BasketManagerStorage storage self,
        string calldata basketName,
        string calldata symbol,
        address baseAsset,
        uint256 bitFlag,
        address strategy
    )
        external
        returns (address basket)
    {
        // Checks
        if (baseAsset == address(0)) {
            revert ZeroAddress();
        }
        uint256 basketTokensLength = self.basketTokens.length;
        if (basketTokensLength >= _MAX_NUM_OF_BASKET_TOKENS) {
            revert BasketTokenMaxExceeded();
        }
        bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));
        if (self.basketIdToAddress[basketId] != address(0)) {
            revert BasketTokenAlreadyExists();
        }
        // Checks with external view calls
        if (!self.strategyRegistry.supportsBitFlag(bitFlag, strategy)) {
            revert StrategyRegistryDoesNotSupportStrategy();
        }
        AssetRegistry assetRegistry = AssetRegistry(self.assetRegistry);
        if (assetRegistry.hasPausedAssets(bitFlag)) {
            revert AssetNotEnabled();
        }
        address[] memory assets = assetRegistry.getAssets(bitFlag);
        if (assets.length == 0) {
            revert AssetListEmpty();
        }
        basket = Clones.clone(self.basketTokenImplementation);
        _setBaseAssetIndex(self, basket, assets, baseAsset);
        self.basketTokens.push(basket);
        self.basketAssets[basket] = assets;
        self.basketIdToAddress[basketId] = basket;
        // The set default management fee will given to the zero address
        self.managementFees[basket] = self.managementFees[address(0)];
        uint256 assetsLength = assets.length;
        for (uint256 j = 0; j < assetsLength;) {
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketAssetToIndexPlusOne[basket][assets[j]] = j + 1;
            unchecked {
                // Overflow not possible: j is bounded by assets.length
                ++j;
            }
        }
        unchecked {
            // Overflow not possible: basketTokensLength is less than the constant _MAX_NUM_OF_BASKET_TOKENS
            self.basketTokenToIndexPlusOne[basket] = basketTokensLength + 1;
        }
        // Interactions
        BasketToken(basket).initialize(IERC20(baseAsset), basketName, symbol, bitFlag, strategy, address(assetRegistry));
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param baskets Array of basket addresses to rebalance.
    // solhint-disable code-complexity
    // slither-disable-next-line cyclomatic-complexity
    function proposeRebalance(BasketManagerStorage storage self, address[] calldata baskets) external {
        // Checks
        // Revert if a rebalance is already in progress
        if (self.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        // slither-disable-next-line timestamp
        if (block.timestamp - self.rebalanceStatus.timestamp < _REBALANCE_COOLDOWN_SEC) {
            revert TooEarlyToProposeRebalance();
        }

        // Effects
        self.rebalanceStatus.basketMask = _createRebalanceBitMask(self, baskets);
        self.rebalanceStatus.proposalTimestamp = uint40(block.timestamp);
        self.rebalanceStatus.timestamp = uint40(block.timestamp);
        self.rebalanceStatus.status = Status.REBALANCE_PROPOSED;

        address assetRegistry = self.assetRegistry;
        address feeCollector = self.feeCollector;
        EulerRouter eulerRouter = self.eulerRouter;
        uint64[][] memory basketTargetWeights = new uint64[][](baskets.length);
        address[][] memory basketAssets = new address[][](baskets.length);

        // Interactions
        for (uint256 i = 0; i < baskets.length;) {
            // slither-disable-start calls-loop
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = basketAssets[i] = self.basketAssets[basket];
            basketTargetWeights[i] = BasketToken(basket).getTargetWeights();
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            if (assets.length == 0) {
                revert BasketTokenNotFound();
            }
            if (AssetRegistry(assetRegistry).hasPausedAssets(BasketToken(basket).bitFlag())) {
                revert AssetNotEnabled();
            }
            // Calculate current basket value
            (uint256[] memory balances, uint256 basketValue) = _calculateBasketValue(self, eulerRouter, basket, assets);
            // Notify Basket Token of rebalance:
            (uint256 pendingDeposits, uint256 pendingRedeems) =
                BasketToken(basket).prepareForRebalance(self.managementFees[basket], feeCollector);
            // Cache total supply for later use
            uint256 totalSupply = BasketToken(basket).totalSupply();
            // Process pending deposits
            if (pendingDeposits > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 baseAssetIndex = self.basketTokenToBaseAssetIndexPlusOne[basket] - 1;
                // Process pending deposits and fulfill them
                (uint256 newShares, uint256 pendingDepositValue) = _processPendingDeposits(
                    self,
                    eulerRouter,
                    basket,
                    totalSupply,
                    basketValue,
                    balances[baseAssetIndex],
                    pendingDeposits,
                    assets[baseAssetIndex]
                );
                // If no new shares are minted, no deposit will be added to the basket
                if (newShares > 0) {
                    balances[baseAssetIndex] += pendingDeposits;
                    totalSupply += newShares;
                    basketValue += pendingDepositValue;
                }
            }
            // No need to rebalance if the total supply is 0 even after processing pending deposits
            if (totalSupply == 0) {
                revert ZeroTotalSupply();
            }
            uint256 requiredWithdrawValue = 0;
            // Pre-process pending redemptions
            if (pendingRedeems > 0) {
                if (totalSupply > 0) {
                    // totalSupply cannot be 0 when pendingRedeems is greater than 0, as redemptions
                    // can only occur if there are issued shares (i.e., totalSupply > 0).
                    // Division-by-zero is not possible: totalSupply is greater than 0
                    requiredWithdrawValue = FixedPointMathLib.fullMulDiv(basketValue, pendingRedeems, totalSupply);
                    if (requiredWithdrawValue > basketValue) {
                        // This should never happen, but if it does, withdraw the entire basket value
                        requiredWithdrawValue = basketValue;
                    }
                    unchecked {
                        // Overflow not possible: requiredWithdrawValue is less than or equal to basketValue
                        basketValue -= requiredWithdrawValue;
                    }
                }
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.pendingRedeems[basket] = pendingRedeems;
            }
            // slither-disable-end calls-loop
            unchecked {
                // Overflow not possible: i is less than baskets.length
                ++i;
            }
        }

        // Effects after Interactions. Target weights require external view calls to respective strategies.
        bytes32 basketHash = keccak256(abi.encode(baskets, basketTargetWeights, basketAssets));
        // slither-disable-next-line reentrancy-events
        emit RebalanceProposed(self.rebalanceStatus.epoch, baskets, basketTargetWeights, basketAssets, basketHash);
        self.rebalanceStatus.basketHash = basketHash;
    }
    // solhint-enable code-complexity

    // @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketTargetWeights Array of target weights for each basket.
    /// @param basketAssets Array of assets in each basket.
    // slither-disable-next-line cyclomatic-complexity
    function proposeTokenSwap(
        BasketManagerStorage storage self,
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint64[][] calldata basketTargetWeights,
        address[][] calldata basketAssets
    )
        external
    {
        // Checks
        RebalanceStatus memory status = self.rebalanceStatus;
        if (status.status != Status.REBALANCE_PROPOSED) {
            revert MustWaitForRebalanceToComplete();
        }
        _validateBasketHash(self, baskets, basketTargetWeights, basketAssets);
        if (internalTrades.length == 0) {
            if (externalTrades.length == 0) {
                revert CannotProposeEmptyTrades();
            }
        }
        // Effects
        status.timestamp = uint40(block.timestamp);
        status.status = Status.TOKEN_SWAP_PROPOSED;
        self.rebalanceStatus = status;
        self.externalTradesHash = keccak256(abi.encode(externalTrades));

        EulerRouter eulerRouter = self.eulerRouter;
        uint256 numBaskets = baskets.length;
        uint256[] memory totalValues = new uint256[](numBaskets);
        // 2d array of asset balances for each basket
        uint256[][] memory basketBalances = new uint256[][](numBaskets);
        _initializeBasketData(self, eulerRouter, baskets, basketAssets, basketBalances, totalValues);
        // NOTE: for rebalance retries the internal trades must be updated as well
        _processInternalTrades(self, eulerRouter, internalTrades, baskets, totalValues, basketBalances);
        _validateExternalTrades(self, eulerRouter, externalTrades, baskets, totalValues, basketBalances);
        if (
            !_isTargetWeightMet(
                self, eulerRouter, baskets, basketTargetWeights, basketAssets, basketBalances, totalValues
            )
        ) {
            revert TargetWeightsNotMet();
        }
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades matching those proposed for rebalance.
    /// @param baskets Array of basket addresses proposed for rebalance.
    /// @param basketTargetWeights Array of target weights for each basket.
    // slither-disable-next-line cyclomatic-complexity
    function completeRebalance(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint64[][] calldata basketTargetWeights,
        address[][] calldata basketAssets
    )
        external
    {
        // Revert if there is no rebalance in progress
        // slither-disable-next-line incorrect-equality
        if (self.rebalanceStatus.status == Status.NOT_STARTED) {
            revert NoRebalanceInProgress();
        }
        _validateBasketHash(self, baskets, basketTargetWeights, basketAssets);
        // Check if the rebalance was proposed more than 15 minutes ago
        // slither-disable-next-line timestamp
        if (block.timestamp - self.rebalanceStatus.timestamp < self.stepDelay) {
            revert TooEarlyToCompleteRebalance();
        }
        // if external trades are proposed and executed, finalize them and claim results from the trades
        if (self.rebalanceStatus.status == Status.TOKEN_SWAP_EXECUTED) {
            if (keccak256(abi.encode(externalTrades)) != self.externalTradesHash) {
                revert ExternalTradeMismatch();
            }
            _processExternalTrades(self, externalTrades);
        }

        EulerRouter eulerRouter = self.eulerRouter;
        uint256 len = baskets.length;
        uint256[] memory totalValue_ = new uint256[](len);
        // 2d array of asset amounts for each basket after all trades are settled
        uint256[][] memory afterTradeAmounts_ = new uint256[][](len);
        _initializeBasketData(self, eulerRouter, baskets, basketAssets, afterTradeAmounts_, totalValue_);
        // Confirm that target weights have been met, if max retries is reached continue regardless
        uint8 currentRetryCount = self.rebalanceStatus.retryCount;
        if (currentRetryCount < self.retryLimit) {
            if (
                !_isTargetWeightMet(
                    self, eulerRouter, baskets, basketTargetWeights, basketAssets, afterTradeAmounts_, totalValue_
                )
            ) {
                emit RebalanceRetried(self.rebalanceStatus.epoch, ++currentRetryCount);
                // If target weights are not met and we have not reached max retries, revert to beginning of rebalance
                // to allow for additional token swaps to be proposed and increment retryCount.
                self.rebalanceStatus.retryCount = currentRetryCount;
                self.rebalanceStatus.timestamp = uint40(block.timestamp);
                self.externalTradesHash = bytes32(0);
                self.rebalanceStatus.status = Status.REBALANCE_PROPOSED;
                return;
            }
        }
        _finalizeRebalance(self, eulerRouter, baskets, basketAssets);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice Fallback redeem function to redeem shares when the rebalance is not in progress. Redeems the shares for
    /// each underlying asset in the basket pro-rata to the amount of shares redeemed.
    /// @param totalSupplyBefore Total supply of the basket token before the shares were burned.
    /// @param burnedShares Amount of shares burned.
    /// @param to Address to send the redeemed assets to.
    // solhint-disable-next-line code-complexity
    function proRataRedeem(
        BasketManagerStorage storage self,
        uint256 totalSupplyBefore,
        uint256 burnedShares,
        address to
    )
        external
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
        // Revert if the basket is currently rebalancing
        if ((self.rebalanceStatus.basketMask & (1 << self.basketTokenToIndexPlusOne[msg.sender] - 1)) != 0) {
            revert MustWaitForRebalanceToComplete();
        }

        address basket = msg.sender;
        address[] memory assets = self.basketAssets[basket];
        uint256 assetsLength = assets.length;
        uint256[] memory amountToWithdraws = new uint256[](assetsLength);

        // Interactions
        // First loop: compute amountToWithdraw for each asset and update balances
        for (uint256 i = 0; i < assetsLength;) {
            address asset = assets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 balance = self.basketBalanceOf[basket][asset];
            // Rounding direction: down
            // Division-by-zero is not possible: totalSupplyBefore is greater than 0
            uint256 amountToWithdraw = FixedPointMathLib.fullMulDiv(burnedShares, balance, totalSupplyBefore);
            amountToWithdraws[i] = amountToWithdraw;
            if (amountToWithdraw > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[basket][asset] = balance - amountToWithdraw;
            }
            unchecked {
                // Overflow not possible: i is less than assetsLength
                ++i;
            }
        }

        // Second loop: perform safeTransfer for each asset
        for (uint256 i = 0; i < assetsLength;) {
            uint256 amountToWithdraw = amountToWithdraws[i];
            if (amountToWithdraw > 0) {
                // Asset is an allowlisted ERC20 with no reentrancy problem in transfer
                // slither-disable-next-line reentrancy-no-eth
                IERC20(assets[i]).safeTransfer(to, amountToWithdraw);
            }
            unchecked {
                // Overflow not possible: i is less than assetsLength
                ++i;
            }
        }
    }

    /// @notice Returns the index of the asset in a given basket
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketToken Basket token address.
    /// @param asset Asset address.
    /// @return index Index of the asset in the basket.
    function getAssetIndexInBasket(
        BasketManagerStorage storage self,
        address basketToken,
        address asset
    )
        public
        view
        returns (uint256 index)
    {
        index = self.basketAssetToIndexPlusOne[basketToken][asset];
        if (index == 0) {
            revert AssetNotFoundInBasket();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /// @notice Returns the index of the basket token.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketToken Basket token address.
    /// @return index Index of the basket token.
    function basketTokenToIndex(
        BasketManagerStorage storage self,
        address basketToken
    )
        public
        view
        returns (uint256 index)
    {
        index = self.basketTokenToIndexPlusOne[basketToken];
        if (index == 0) {
            revert BasketTokenNotFound();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Returns the index of the element in the array.
    /// @dev Reverts if the element does not exist in the array.
    /// @param array Array to find the element in.
    /// @param element Element to find in the array.
    /// @return index Index of the element in the array.
    function _indexOf(address[] calldata array, address element) internal pure returns (uint256 index) {
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

    /// @notice Internal function to finalize the state changes for the current rebalance. Resets rebalance status and
    /// attempts to process pending redeems. If all pending redeems cannot be fulfilled notifies basket token of a
    /// failed rebalance.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    function _finalizeRebalance(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        address[] calldata baskets,
        address[][] calldata basketAssets
    )
        private
    {
        // Advance the rebalance epoch and reset the status
        uint40 epoch = self.rebalanceStatus.epoch;
        self.rebalanceStatus.basketHash = bytes32(0);
        self.rebalanceStatus.basketMask = 0;
        self.rebalanceStatus.epoch = epoch + 1;
        self.rebalanceStatus.proposalTimestamp = uint40(0);
        self.rebalanceStatus.timestamp = uint40(block.timestamp);
        self.rebalanceStatus.status = Status.NOT_STARTED;
        self.externalTradesHash = bytes32(0);
        self.rebalanceStatus.retryCount = 0;
        // slither-disable-next-line reentrancy-events
        emit RebalanceCompleted(epoch);

        // Process the redeems for the given baskets
        uint256 len = baskets.length;
        // slither-disable-start calls-loop
        for (uint256 i = 0; i < len;) {
            // NOTE: Can be optimized by using calldata for the `baskets` parameter or by moving the
            // redemption processing logic to a ZK coprocessor like Axiom for improved efficiency and scalability.
            address basket = baskets[i];
            address[] calldata assets = basketAssets[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            uint256[] memory balances = new uint256[](assetsLength);
            uint256 basketValue = 0;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = self.basketBalanceOf[basket][assets[j]];
                if (balances[j] > 0) {
                    // Rounding direction: down
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    basketValue += eulerRouter.getQuote(balances[j], assets[j], _USD_ISO_4217_CODE);
                }
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }

            // If there are pending redeems, process them
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 pendingRedeems = self.pendingRedeems[basket];
            if (pendingRedeems > 0) {
                // slither-disable-next-line costly-loop
                delete self.pendingRedeems[basket]; // nosemgrep
                uint256 baseAssetIndex = self.basketTokenToBaseAssetIndexPlusOne[basket] - 1;
                address baseAsset = assets[baseAssetIndex];
                uint256 baseAssetBalance = balances[baseAssetIndex];
                // Rounding direction: down
                // Division-by-zero is not possible: totalSupply is greater than 0 when pendingRedeems is greater than 0
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 withdrawAmount = eulerRouter.getQuote(
                    FixedPointMathLib.fullMulDiv(basketValue, pendingRedeems, BasketToken(basket).totalSupply()),
                    _USD_ISO_4217_CODE,
                    baseAsset
                );
                // Set withdrawAmount to zero if it exceeds baseAssetBalance, otherwise keep it unchanged
                withdrawAmount = withdrawAmount <= baseAssetBalance ? withdrawAmount : 0;
                if (withdrawAmount > 0) {
                    unchecked {
                        // Overflow not possible: withdrawAmount is less than or equal to balances[baseAssetIndex]
                        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                        self.basketBalanceOf[basket][baseAsset] = baseAssetBalance - withdrawAmount;
                    }
                    // slither-disable-next-line reentrancy-no-eth
                    IERC20(baseAsset).forceApprove(basket, withdrawAmount);
                }
                // ERC20.transferFrom is called in BasketToken.fulfillRedeem
                // slither-disable-next-line reentrancy-no-eth
                BasketToken(basket).fulfillRedeem(withdrawAmount);
            }
            unchecked {
                // Overflow not possible: i is less than baskets.length
                ++i;
            }
        }
        // slither-disable-end calls-loop
    }

    /// @notice Internal function to complete proposed token swaps.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be completed.
    /// @return claimedAmounts amounts claimed from the completed token swaps
    function _completeTokenSwap(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades
    )
        private
        returns (uint256[2][] memory claimedAmounts)
    {
        // solhint-disable avoid-low-level-calls
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory data) =
            self.tokenSwapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.completeTokenSwap, (externalTrades)));
        // solhint-enable avoid-low-level-calls
        if (!success) {
            // assume this low-level call never fails
            revert CompleteTokenSwapFailed();
        }
        claimedAmounts = abi.decode(data, (uint256[2][]));
    }

    /// @notice Internal function to update internal accounting with result of completed token swaps.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be completed.
    function _processExternalTrades(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades
    )
        private
    {
        uint256 externalTradesLength = externalTrades.length;
        uint256[2][] memory claimedAmounts = _completeTokenSwap(self, externalTrades);
        // Update basketBalanceOf with amounts gained from swaps
        for (uint256 i = 0; i < externalTradesLength;) {
            ExternalTrade calldata trade = externalTrades[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 tradeOwnershipLength = trade.basketTradeOwnership.length;
            uint256 remainingSellTokenAmount = claimedAmounts[i][0];
            uint256 remainingBuyTokenAmount = claimedAmounts[i][1];
            uint256 remainingSellAmount = trade.sellAmount;

            for (uint256 j; j < tradeOwnershipLength;) {
                BasketTradeOwnership calldata ownership = trade.basketTradeOwnership[j];

                // Get basket balances mapping for this ownership
                mapping(address => uint256) storage basketBalanceOf = self.basketBalanceOf[ownership.basket];

                if (j == tradeOwnershipLength - 1) {
                    // Last ownership gets remaining amounts
                    basketBalanceOf[trade.buyToken] += remainingBuyTokenAmount;
                    basketBalanceOf[trade.sellToken] =
                        basketBalanceOf[trade.sellToken] + remainingSellTokenAmount - remainingSellAmount;
                } else {
                    // Calculate ownership portions
                    uint256 buyTokenAmount =
                        FixedPointMathLib.fullMulDiv(claimedAmounts[i][1], ownership.tradeOwnership, _WEIGHT_PRECISION);
                    uint256 sellTokenAmount =
                        FixedPointMathLib.fullMulDiv(claimedAmounts[i][0], ownership.tradeOwnership, _WEIGHT_PRECISION);
                    uint256 sellAmount =
                        FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, _WEIGHT_PRECISION);

                    // Update balances
                    basketBalanceOf[trade.buyToken] += buyTokenAmount;
                    basketBalanceOf[trade.sellToken] = basketBalanceOf[trade.sellToken] + sellTokenAmount - sellAmount;

                    // Track remaining amounts
                    remainingBuyTokenAmount -= buyTokenAmount;
                    remainingSellTokenAmount -= sellTokenAmount;
                    remainingSellAmount -= sellAmount;
                }
                unchecked {
                    // Overflow not possible: i is less than tradeOwnerShipLength.length
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is less than externalTradesLength.length
                ++i;
            }
        }
    }

    /// @notice Internal function to initialize basket data.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketBalances An empty array used for asset balances for each basket being rebalanced. Updated with
    /// current balances at the end of the function.
    /// @param totalValues An initialized array of total basket values for each basket being rebalanced.
    function _initializeBasketData(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        address[] calldata baskets,
        address[][] calldata basketAssets,
        uint256[][] memory basketBalances,
        uint256[] memory totalValues
    )
        private
        view
    {
        uint256 numBaskets = baskets.length;
        for (uint256 i = 0; i < numBaskets;) {
            address[] calldata assets = basketAssets[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            basketBalances[i] = new uint256[](assetsLength);
            // Create a storage mapping reference for the current basket's balances
            mapping(address => uint256) storage basketBalanceOf = self.basketBalanceOf[baskets[i]];
            for (uint256 j = 0; j < assetsLength;) {
                address asset = assets[j];
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 currentAssetAmount = basketBalanceOf[asset];
                basketBalances[i][j] = currentAssetAmount;
                if (currentAssetAmount > 0) {
                    // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                    totalValues[i] += eulerRouter.getQuote(currentAssetAmount, asset, _USD_ISO_4217_CODE);
                }
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
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param internalTrades Array of internal trades to execute.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketBalances An initialized array of asset amounts for each basket being rebalanced. Updated with
    /// settled internal trades at the end of the function.
    /// @dev If the result of an internal trade is not within the provided minAmount or maxAmount, this function will
    /// revert.
    function _processInternalTrades(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        InternalTrade[] calldata internalTrades,
        address[] calldata baskets,
        uint256[] memory totalValues,
        uint256[][] memory basketBalances
    )
        private
    {
        uint256 swapFee = self.swapFee; // Fetch swapFee once for gas optimization
        uint256 internalTradesLength = internalTrades.length;
        for (uint256 i = 0; i < internalTradesLength;) {
            InternalTrade calldata trade = internalTrades[i];
            if (trade.sellAmount == 0) {
                revert InternalTradeSellAmountZero();
            }
            InternalTradeInfo memory info = InternalTradeInfo({
                fromBasketIndex: _indexOf(baskets, trade.fromBasket),
                toBasketIndex: _indexOf(baskets, trade.toBasket),
                sellTokenAssetIndex: getAssetIndexInBasket(self, trade.fromBasket, trade.sellToken),
                buyTokenAssetIndex: getAssetIndexInBasket(self, trade.fromBasket, trade.buyToken),
                toBasketBuyTokenIndex: getAssetIndexInBasket(self, trade.toBasket, trade.buyToken),
                toBasketSellTokenIndex: getAssetIndexInBasket(self, trade.toBasket, trade.sellToken),
                netBuyAmount: 0,
                netSellAmount: 0,
                feeOnBuy: 0,
                feeOnSell: 0,
                sellValue: eulerRouter.getQuote(trade.sellAmount, trade.sellToken, _USD_ISO_4217_CODE),
                feeValue: 0
            });
            uint256 initialBuyAmount = 0;
            if (info.sellValue > 0) {
                initialBuyAmount = eulerRouter.getQuote(info.sellValue, _USD_ISO_4217_CODE, trade.buyToken);
            }
            // Calculate fee on sellAmount
            if (swapFee > 0) {
                info.feeOnSell = FixedPointMathLib.fullMulDiv(trade.sellAmount, swapFee, 20_000);
                info.feeValue = FixedPointMathLib.fullMulDiv(info.sellValue, swapFee, 20_000);
                totalValues[info.fromBasketIndex] -= info.feeValue;
                self.collectedSwapFees[trade.sellToken] += info.feeOnSell;
                emit SwapFeeCharged(trade.sellToken, info.feeOnSell);

                info.feeOnBuy = FixedPointMathLib.fullMulDiv(initialBuyAmount, swapFee, 20_000);
                totalValues[info.toBasketIndex] -= info.feeValue;
                self.collectedSwapFees[trade.buyToken] += info.feeOnBuy;
                emit SwapFeeCharged(trade.buyToken, info.feeOnBuy);
            }
            info.netSellAmount = trade.sellAmount - info.feeOnSell;
            info.netBuyAmount = initialBuyAmount - info.feeOnBuy;

            if (info.netBuyAmount < trade.minAmount || trade.maxAmount < initialBuyAmount) {
                revert InternalTradeMinMaxAmountNotReached();
            }
            if (trade.sellAmount > basketBalances[info.fromBasketIndex][info.sellTokenAssetIndex]) {
                revert IncorrectTradeTokenAmount();
            }
            if (initialBuyAmount > basketBalances[info.toBasketIndex][info.toBasketBuyTokenIndex]) {
                revert IncorrectTradeTokenAmount();
            }

            // Settle the internal trades and track the balance changes.
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.fromBasket][trade.sellToken] =
                basketBalances[info.fromBasketIndex][info.sellTokenAssetIndex] -= trade.sellAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.fromBasket][trade.buyToken] =
                basketBalances[info.fromBasketIndex][info.buyTokenAssetIndex] += info.netBuyAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.toBasket][trade.buyToken] =
                basketBalances[info.toBasketIndex][info.toBasketBuyTokenIndex] -= initialBuyAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.toBasket][trade.sellToken] =
                basketBalances[info.toBasketIndex][info.toBasketSellTokenIndex] += info.netSellAmount; // nosemgrep
            unchecked {
                // Overflow not possible: i is less than internalTradesLength and internalTradesLength cannot be near
                // the maximum value of uint256 due to gas limits
                ++i;
            }
            emit InternalTradeSettled(trade, info.netBuyAmount);
        }
    }

    /// @notice Internal function to validate the results of external trades.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be validated.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param totalValue_ Array of total basket values in USD.
    /// @param afterTradeAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @dev If the result of an external trade is not within the slippageLimit threshold of the minAmount, this
    /// function will revert. If the sum of the trade ownerships is not equal to _WEIGHT_PRECISION, this function will
    /// revert.
    function _validateExternalTrades(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint256[] memory totalValue_,
        uint256[][] memory afterTradeAmounts_
    )
        private
        view
    {
        uint256 slippageLimit = self.slippageLimit;
        for (uint256 i = 0; i < externalTrades.length;) {
            ExternalTrade calldata trade = externalTrades[i];
            if (trade.sellAmount == 0) {
                revert ExternalTradeSellAmountZero();
            }
            uint256 ownershipSum = 0;
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            for (uint256 j = 0; j < trade.basketTradeOwnership.length;) {
                BasketTradeOwnership calldata ownership = trade.basketTradeOwnership[j];
                ownershipSum += ownership.tradeOwnership;
                uint256 basketIndex = _indexOf(baskets, ownership.basket);
                uint256 buyTokenAssetIndex = getAssetIndexInBasket(self, ownership.basket, trade.buyToken);
                uint256 sellTokenAssetIndex = getAssetIndexInBasket(self, ownership.basket, trade.sellToken);
                uint256 ownershipSellAmount =
                    FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, _WEIGHT_PRECISION);
                uint256 ownershipBuyAmount =
                    FixedPointMathLib.fullMulDiv(trade.minAmount, ownership.tradeOwnership, _WEIGHT_PRECISION);
                // Record changes in basket asset holdings due to the external trade
                if (ownershipSellAmount > afterTradeAmounts_[basketIndex][sellTokenAssetIndex]) {
                    revert IncorrectTradeTokenAmount();
                }
                // solhint-disable-next-line max-line-length
                afterTradeAmounts_[basketIndex][sellTokenAssetIndex] =
                    afterTradeAmounts_[basketIndex][sellTokenAssetIndex] - ownershipSellAmount;
                afterTradeAmounts_[basketIndex][buyTokenAssetIndex] =
                    afterTradeAmounts_[basketIndex][buyTokenAssetIndex] + ownershipBuyAmount;
                // Update total basket value
                totalValue_[basketIndex] = totalValue_[basketIndex]
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                - eulerRouter.getQuote(ownershipSellAmount, trade.sellToken, _USD_ISO_4217_CODE)
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                + eulerRouter.getQuote(ownershipBuyAmount, trade.buyToken, _USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is bounded by trade.basketTradeOwnership.length
                    ++j;
                }
            }
            if (ownershipSum != _WEIGHT_PRECISION) {
                revert OwnershipSumMismatch();
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 internalMinAmount = eulerRouter.getQuote(
                eulerRouter.getQuote(trade.sellAmount, trade.sellToken, _USD_ISO_4217_CODE),
                _USD_ISO_4217_CODE,
                trade.buyToken
            );

            // Check if the given minAmount is within the slippageLimit threshold of internalMinAmount
            if (
                FixedPointMathLib.fullMulDiv(
                    MathUtils.diff(internalMinAmount, trade.minAmount), _WEIGHT_PRECISION, internalMinAmount
                ) > slippageLimit
            ) {
                revert ExternalTradeSlippage();
            }

            unchecked {
                // Overflow not possible: i is bounded by baskets.length
                ++i;
            }
        }
    }

    /// @notice Validate the basket hash based on the given baskets and target weights.
    function _validateBasketHash(
        BasketManagerStorage storage self,
        address[] calldata baskets,
        uint64[][] calldata basketsTargetWeights,
        address[][] calldata basketAssets
    )
        private
        view
    {
        // Validate the calldata hashes
        bytes32 basketHash = keccak256(abi.encode(baskets, basketsTargetWeights, basketAssets));
        if (self.rebalanceStatus.basketHash != basketHash) {
            revert BasketsMismatch();
        }
        // Check that the length matches
        if (baskets.length != basketsTargetWeights.length || baskets.length != basketAssets.length) {
            revert BasketsMismatch();
        }
    }

    /// @notice Checks if weight deviations after trades are within the acceptable weightDeviationLimit threshold.
    /// Returns true if all deviations are within bounds for each asset in every basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketsTargetWeights Array of target weights for each basket.
    /// @param basketAssets Array of assets in each basket.
    /// @param basketBalances 2D array of asset balances for each basket. Rows are baskets, columns are assets.
    /// @param totalValues Array of total basket values in USD.
    function _isTargetWeightMet(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        address[] calldata baskets,
        uint64[][] calldata basketsTargetWeights,
        address[][] calldata basketAssets,
        uint256[][] memory basketBalances,
        uint256[] memory totalValues
    )
        private
        view
        returns (bool)
    {
        // Check if total weight change due to all trades is within the weightDeviationLimit threshold
        uint256 len = baskets.length;
        uint256 weightDeviationLimit = self.weightDeviationLimit;
        for (uint256 i = 0; i < len;) {
            // slither-disable-next-line calls-loop
            uint64[] calldata proposedTargetWeights = basketsTargetWeights[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 numOfAssets = proposedTargetWeights.length;
            uint64[] memory adjustedTargetWeights = new uint64[](numOfAssets);

            // Calculate adjusted target weights accounting for pending redeems
            uint256 pendingRedeems = self.pendingRedeems[baskets[i]];
            if (pendingRedeems > 0) {
                uint256 totalSupply = BasketToken(baskets[i]).totalSupply();
                uint256 remainingSupply = totalSupply - pendingRedeems;

                // Get base asset index
                uint256 baseAssetIndex = self.basketTokenToBaseAssetIndexPlusOne[baskets[i]] - 1;

                // Track running sum for all weights except the last one
                uint256 runningSum;
                uint256 lastIndex = numOfAssets - 1;

                // Adjust weights while maintaining 1e18 sum
                for (uint256 j = 0; j < numOfAssets;) {
                    if (j == lastIndex) {
                        // Use remainder for the last weight to ensure exact 1e18 sum
                        adjustedTargetWeights[j] = uint64(_WEIGHT_PRECISION - runningSum);
                    } else {
                        if (j == baseAssetIndex) {
                            // Increase base asset weight by adding extra weight from pending redeems
                            adjustedTargetWeights[j] = uint64(
                                FixedPointMathLib.fullMulDiv(
                                    FixedPointMathLib.fullMulDiv(
                                        remainingSupply, proposedTargetWeights[j], _WEIGHT_PRECISION
                                    ) + pendingRedeems,
                                    _WEIGHT_PRECISION,
                                    totalSupply
                                )
                            );
                            runningSum += adjustedTargetWeights[j];
                        } else {
                            // Scale down other weights proportionally
                            adjustedTargetWeights[j] = uint64(
                                FixedPointMathLib.fullMulDiv(remainingSupply, proposedTargetWeights[j], totalSupply)
                            );
                            runningSum += adjustedTargetWeights[j];
                        }
                    }
                    unchecked {
                        ++j;
                    }
                }
            } else {
                // If no pending redeems, use original target weights
                adjustedTargetWeights = proposedTargetWeights;
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] calldata assets = basketAssets[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 proposedTargetWeightsLength = proposedTargetWeights.length;
            for (uint256 j = 0; j < proposedTargetWeightsLength;) {
                // If the total value of the basket is 0, we can't calculate the weight.
                // So we assume the target weight is met.
                if (totalValues[i] != 0) {
                    uint256 assetValueInUSD = 0;
                    if (basketBalances[i][j] > 0) {
                        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                        assetValueInUSD = eulerRouter.getQuote(basketBalances[i][j], assets[j], _USD_ISO_4217_CODE);
                    }
                    // Rounding direction: down
                    uint256 afterTradeWeight =
                        FixedPointMathLib.fullMulDiv(assetValueInUSD, _WEIGHT_PRECISION, totalValues[i]);
                    if (MathUtils.diff(adjustedTargetWeights[j], afterTradeWeight) > weightDeviationLimit) {
                        return false;
                    }
                }
                unchecked {
                    // Overflow not possible: j is bounded by proposedTargetWeightsLength
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is bounded by len
                ++i;
            }
        }
        return true;
    }

    /// @notice Internal function to process pending deposits and fulfill them.
    /// @dev Assumes pendingDeposit is not 0.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param basketValue Current value of the basket in USD.
    /// @param baseAssetBalance Current balance of the base asset in the basket.
    /// @param pendingDeposit Current assets pending deposit in the given basket.
    /// @return newShares Amount of new shares minted.
    /// @return pendingDepositValue Value of the pending deposits in USD.
    // slither-disable-next-line calls-loop
    function _processPendingDeposits(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        address basket,
        uint256 totalSupply,
        uint256 basketValue,
        uint256 baseAssetBalance,
        uint256 pendingDeposit,
        address baseAssetAddress
    )
        private
        returns (uint256 newShares, uint256 pendingDepositValue)
    {
        // Assume the first asset listed in the basket is the base asset
        // Round direction: down
        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
        pendingDepositValue = eulerRouter.getQuote(pendingDeposit, baseAssetAddress, _USD_ISO_4217_CODE);
        // Rounding direction: down
        // Division-by-zero is not possible: basketValue is greater than 0
        newShares = basketValue > 0
            ? FixedPointMathLib.fullMulDiv(pendingDepositValue, totalSupply, basketValue)
            : pendingDepositValue;
        if (newShares > 0) {
            // Add the deposit to the basket balance if newShares is positive
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[basket][baseAssetAddress] = baseAssetBalance + pendingDeposit;
        } else {
            // If newShares is 0, set pendingDepositValue to 0 to indicate rejected deposit, no deposit is minted
            pendingDepositValue = 0;
        }
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
        BasketToken(basket).fulfillDeposit(newShares);
    }

    /// @notice Internal function to calculate the current value of all assets in a given basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param assets Array of asset addresses in the basket.
    /// @return balances Array of balances of each asset in the basket.
    /// @return basketValue Current value of the basket in USD.
    // slither-disable-next-line calls-loop
    function _calculateBasketValue(
        BasketManagerStorage storage self,
        EulerRouter eulerRouter,
        address basket,
        address[] memory assets
    )
        private
        view
        returns (uint256[] memory balances, uint256 basketValue)
    {
        uint256 assetsLength = assets.length;
        balances = new uint256[](assetsLength);
        for (uint256 j = 0; j < assetsLength;) {
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            balances[j] = self.basketBalanceOf[basket][assets[j]];
            // Rounding direction: down
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            if (balances[j] > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketValue += eulerRouter.getQuote(balances[j], assets[j], _USD_ISO_4217_CODE);
            }
            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
    }

    /// @notice Internal function to store the index of the base asset for a given basket. Reverts if the base asset is
    /// not present in the basket's assets.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param assets Array of asset addresses in the basket.
    /// @param baseAsset Base asset address.
    /// @dev If the base asset is not present in the basket, this function will revert.
    function _setBaseAssetIndex(
        BasketManagerStorage storage self,
        address basket,
        address[] memory assets,
        address baseAsset
    )
        private
    {
        uint256 len = assets.length;
        for (uint256 i = 0; i < len;) {
            if (assets[i] == baseAsset) {
                self.basketTokenToBaseAssetIndexPlusOne[basket] = i + 1;
                return;
            }
            unchecked {
                // Overflow not possible: i is less than len
                ++i;
            }
        }
        revert BaseAssetMismatch();
    }

    /// @notice Internal function to create a bitmask for baskets being rebalanced.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @return basketMask Bitmask for baskets being rebalanced.
    /// @dev A bitmask like 00000011 indicates that the first two baskets are being rebalanced.
    function _createRebalanceBitMask(
        BasketManagerStorage storage self,
        address[] memory baskets
    )
        private
        view
        returns (uint256 basketMask)
    {
        // Create the bitmask for baskets being rebalanced
        basketMask = 0;
        uint256 len = baskets.length;
        for (uint256 i = 0; i < len;) {
            uint256 indexPlusOne = self.basketTokenToIndexPlusOne[baskets[i]];
            if (indexPlusOne == 0) {
                revert BasketTokenNotFound();
            }
            basketMask |= (1 << indexPlusOne - 1);
            unchecked {
                // Overflow not possible: i is less than len
                ++i;
            }
        }
    }
}

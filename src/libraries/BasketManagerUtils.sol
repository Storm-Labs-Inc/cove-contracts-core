// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { console } from "forge-std/console.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";
import { Errors } from "src/libraries/Errors.sol";
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
    address private constant _USD_ISO_4217_CODE = address(840);
    /// @notice Maximum number of basket tokens allowed to be created.
    uint256 private constant _MAX_NUM_OF_BASKET_TOKENS = 256;
    /// @notice Maximum slippage allowed for token swaps.
    uint256 private constant _MAX_SLIPPAGE_BPS = 0.05e18; // .05%
    /// @notice Maximum deviation from target weights allowed for token swaps.
    uint256 private constant _MAX_WEIGHT_DEVIATION_BPS = 0.05e18; // .05%
    /// @notice Precision used for weight calculations.
    uint256 private constant _WEIGHT_PRECISION = 1e18;
    /// @notice Maximum number of retries for a rebalance.
    uint8 private constant _MAX_RETRIES = 3;

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
    /// @dev Reverts when the total supply of a basket token is zero.
    error ZeroTotalSupply();
    /// @dev Reverts when the amount of burned shares is zero.
    error ZeroBurnedShares();
    /// @dev Reverts when trying to burn more shares than the total supply.
    error CannotBurnMoreSharesThanTotalSupply();
    /// @dev Reverts when the requested basket token is not found.
    error BasketTokenNotFound();
    /// @dev Reverts when the requested asset is not found in the basket.
    error AssetNotFoundInBasket();
    /// @dev Reverts when trying to create a basket token that already exists.
    error BasketTokenAlreadyExists();
    /// @dev Reverts when the maximum number of basket tokens has been reached.
    error BasketTokenMaxExceeded();
    /// @dev Reverts when the requested element index is not found.
    error ElementIndexNotFound();
    /// @dev Reverts when the strategy registry does not support the given strategy.
    error StrategyRegistryDoesNotSupportStrategy();
    /// @dev Reverts when the baskets do not match.
    error BasketsMismatch();
    /// @dev Reverts when the base asset does not match the given asset.
    error BaseAssetMismatch();
    /// @dev Reverts when the asset is not found in the asset registry.
    error AssetListEmpty();
    /// @dev Reverts when a rebalance is in progress and the caller must wait for it to complete.
    error MustWaitForRebalanceToComplete();
    /// @dev Reverts when there is no rebalance in progress.
    error NoRebalanceInProgress();
    /// @dev Reverts when it is too early to complete the rebalance.
    error TooEarlyToCompleteRebalance();
    /// @dev Reverts when a rebalance is not required.
    error RebalanceNotRequired();
    /// @dev Reverts when the external trade slippage exceeds the allowed limit.
    error ExternalTradeSlippage();
    /// @dev Reverts when the target weights are not met.
    error TargetWeightsNotMet();
    /// @dev Reverts when the minimum or maximum amount is not reached for an internal trade.
    error InternalTradeMinMaxAmountNotReached();
    /// @dev Reverts when the trade token amount is incorrect.
    error IncorrectTradeTokenAmount();
    /// @dev Reverts when given external trades do not match.
    error ExternalTradeMismatch();
    /// @dev Reverts when the delegatecall to the tokenswap adapter fails.
    error CompleteTokenSwapFailed();
    /// @dev Reverts when an asset included in a bit flag is not enabled in the asset registry.
    error AssetNotEnabled();

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
            revert Errors.ZeroAddress();
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
        {
            if (assetRegistry.hasPausedAssets(bitFlag)) {
                revert AssetNotEnabled();
            }
            address[] memory assets = assetRegistry.getAssets(bitFlag);
            if (assets.length == 0) {
                revert AssetListEmpty();
            }
            if (assets[0] != baseAsset) {
                revert BaseAssetMismatch();
            }
            basket = Clones.clone(self.basketTokenImplementation);
            self.basketTokens.push(basket);
            self.basketAssets[basket] = assets;
            self.basketIdToAddress[basketId] = basket;
            uint256 assetsLength = assets.length;
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketAssetToIndexPlusOne[basket][assets[j]] = j + 1;
                unchecked {
                    ++j;
                }
            }
        }
        unchecked {
            // Overflow not possible: basketTokensLength is less than the constant _MAX_NUM_OF_BASKET_TOKENS
            self.basketTokenToIndexPlusOne[basket] = basketTokensLength + 1;
        }
        // Interactions
        // TODO: have owner address to pass to basket tokens on initialization
        BasketToken(basket).initialize(
            IERC20(baseAsset), basketName, symbol, bitFlag, strategy, address(assetRegistry), address(1)
        );
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param baskets Array of basket addresses to rebalance.
    // slither-disable-next-line cyclomatic-complexity
    function proposeRebalance(BasketManagerStorage storage self, address[] calldata baskets) external {
        // Checks
        // Revert if a rebalance is already in progress
        if (self.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }

        // Effects
        self.rebalanceStatus.basketHash = keccak256(abi.encodePacked(baskets));
        self.rebalanceStatus.timestamp = uint40(block.timestamp);
        self.rebalanceStatus.status = Status.REBALANCE_PROPOSED;

        address assetRegistry = self.assetRegistry;

        // Interactions
        bool shouldRebalance = false;
        for (uint256 i = 0; i < baskets.length;) {
            // slither-disable-start calls-loop
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            if (assets.length == 0) {
                revert BasketTokenNotFound();
            }
            if (AssetRegistry(assetRegistry).hasPausedAssets(BasketToken(basket).bitFlag())) {
                revert AssetNotEnabled();
            }
            // Harvest management fee
            BasketToken(basket).harvestManagementFee(self.managementFee, self.feeCollector);
            // Calculate current basket value
            (uint256[] memory balances, uint256 basketValue) = _calculateBasketValue(self, basket, assets);
            // Notify Basket Token of rebalance: // TODO double check this logic
            uint256 pendingDeposit = BasketToken(basket).totalPendingDeposits(); // have to cache value before prepare
            uint256 pendingRedeems_ = BasketToken(basket).prepareForRebalance();
            uint256 totalSupply;
            {
                uint256 pendingDepositValue;
                // Process pending deposits and fulfill them
                (totalSupply, pendingDepositValue) =
                    _processPendingDeposits(self, basket, basketValue, balances[0], pendingDeposit);
                balances[0] += pendingDeposit;
                basketValue += pendingDepositValue;
            }
            uint256 requiredWithdrawValue = 0;
            // Pre-process pending redemptions
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
                self.pendingRedeems[basket] = pendingRedeems_;
            }
            uint256[] memory targetBalances =
                _calculateTargetBalances(self, basket, basketValue, requiredWithdrawValue, assets);
            if (_checkForRebalance(self, assets, balances, targetBalances)) {
                shouldRebalance = true;
            }
            // slither-disable-end calls-loop
            unchecked {
                // Overflow not possible: i is less than baskets.length
                ++i;
            }
        }
        if (!shouldRebalance) {
            revert RebalanceNotRequired();
        }
    }

    // @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param baskets Array of basket addresses currently being rebalanced.
    // slither-disable-next-line cyclomatic-complexity
    function proposeTokenSwap(
        BasketManagerStorage storage self,
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets
    )
        external
    {
        RebalanceStatus memory status = self.rebalanceStatus;
        if (status.status != Status.REBALANCE_PROPOSED) {
            revert MustWaitForRebalanceToComplete();
        }
        // Ensure the baskets matches the hash from proposeRebalance
        if (keccak256(abi.encodePacked(baskets)) != status.basketHash) {
            revert BasketsMismatch();
        }

        uint256 numBaskets = baskets.length;
        uint256[] memory totalValue_ = new uint256[](numBaskets);
        // 2d array of asset amounts for each basket after all trades are settled
        uint256[][] memory afterTradeAmounts_ = new uint256[][](numBaskets);
        _initializeBasketData(self, baskets, afterTradeAmounts_, totalValue_);
        // NOTE: for rebalance retries the internal trades must be updated as well
        _settleInternalTrades(self, internalTrades, baskets, afterTradeAmounts_);
        _validateExternalTrades(self, externalTrades, baskets, totalValue_, afterTradeAmounts_);
        if (!_validateTargetWeights(self, baskets, afterTradeAmounts_, totalValue_)) {
            revert TargetWeightsNotMet();
        }
        status.timestamp = uint40(block.timestamp);
        status.status = Status.TOKEN_SWAP_PROPOSED;
        self.rebalanceStatus = status;
        self.externalTradesHash = keccak256(abi.encode(externalTrades));
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses proposed for rebalance.
    // slither-disable-next-line cyclomatic-complexity
    function completeRebalance(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets
    )
        external
    {
        // Revert if there is no rebalance in progress
        // slither-disable-next-line incorrect-equality
        if (self.rebalanceStatus.status == Status.NOT_STARTED) {
            revert NoRebalanceInProgress();
        }
        // Check if the given baskets are the same as the ones proposed
        if (keccak256(abi.encodePacked(baskets)) != self.rebalanceStatus.basketHash) {
            revert BasketsMismatch();
        }
        // Check if the rebalance was proposed more than 15 minutes ago
        // slither-disable-next-line timestamp
        if (block.timestamp - self.rebalanceStatus.timestamp < 15 minutes) {
            revert TooEarlyToCompleteRebalance();
        }
        // if external trades are proposed and executed, finalize them and claim results from the trades
        if (self.rebalanceStatus.status == Status.TOKEN_SWAP_EXECUTED) {
            if (keccak256(abi.encode(externalTrades)) != self.externalTradesHash) {
                revert ExternalTradeMismatch();
            }
            _getResultsOfExternalTrades(self, externalTrades);
        }

        uint256 len = baskets.length;
        uint256[] memory totalValue_ = new uint256[](len);
        // 2d array of asset amounts for each basket after all trades are settled
        uint256[][] memory afterTradeAmounts_ = new uint256[][](len);
        _initializeBasketData(self, baskets, afterTradeAmounts_, totalValue_);
        // Confirm that target weights have been met, if max retries is reached continue regardless
        if (self.retryCount < _MAX_RETRIES) {
            if (!_validateTargetWeights(self, baskets, afterTradeAmounts_, totalValue_)) {
                // If target weights are not met and we have not reached max retries, revert to beginning of rebalance
                // to allow for additional token swaps to be proposed and increment retryCount.
                self.retryCount += 1;
                self.rebalanceStatus.timestamp = uint40(block.timestamp);
                self.externalTradesHash = bytes32(0);
                self.rebalanceStatus.status = Status.REBALANCE_PROPOSED;
                return;
            }
        }
        _finalizeRebalance(self, baskets);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice Fallback redeem function to redeem shares when the rebalance is not in progress. Redeems the shares for
    /// each underlying asset in the basket pro-rata to the amount of shares redeemed.
    /// @param totalSupplyBefore Total supply of the basket token before the shares were burned.
    /// @param burnedShares Amount of shares burned.
    /// @param to Address to send the redeemed assets to.
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
            revert Errors.ZeroAddress();
        }
        // Revert if a rebalance is in progress
        if (self.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        // Effects
        address basket = msg.sender;
        address[] storage assets = self.basketAssets[basket];
        uint256 assetsLength = assets.length;
        // Interactions
        for (uint256 i = 0; i < assetsLength;) {
            address asset = assets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 balance = self.basketBalanceOf[basket][asset];
            // Rounding direction: down
            // Division-by-zero is not possible: totalSupplyBefore is greater than 0
            uint256 amountToWithdraw = FixedPointMathLib.fullMulDiv(burnedShares, balance, totalSupplyBefore);
            if (amountToWithdraw > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[basket][asset] = balance - amountToWithdraw;
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

    /// @notice Returns the index of the asset in a given basket
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketToken Basket token address.
    /// @param asset Asset address.
    /// @return index Index of the asset in the basket.
    function basketTokenToRebalanceAssetToIndex(
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
    function _indexOf(address[] memory array, address element) internal pure returns (uint256 index) {
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
    function _finalizeRebalance(BasketManagerStorage storage self, address[] calldata baskets) private {
        // Advance the rebalance epoch and reset the status
        self.rebalanceStatus.basketHash = bytes32(0);
        self.rebalanceStatus.epoch += 1;
        self.rebalanceStatus.timestamp = uint40(block.timestamp);
        self.rebalanceStatus.status = Status.NOT_STARTED;
        self.externalTradesHash = bytes32(0);
        self.retryCount = 0;

        // Process the redeems for the given baskets
        // slither-disable-start calls-loop
        uint256 len = baskets.length;
        for (uint256 i = 0; i < len;) {
            // TODO: Make this more efficient by using calldata or by moving the logic to zk proof chain
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            uint256[] memory balances = new uint256[](assetsLength);
            uint256 basketValue = 0;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = self.basketBalanceOf[basket][assets[j]];
                // Rounding direction: down
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketValue += self.eulerRouter.getQuote(balances[j], assets[j], _USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }

            // If there are pending redeems, process them
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 pendingRedeems_ = self.pendingRedeems[basket];
            if (pendingRedeems_ > 0) {
                // slither-disable-next-line costly-loop
                delete self.pendingRedeems[basket]; // nosemgrep
                // Assume the first asset listed in the basket is the base asset
                // Rounding direction: down
                // Division-by-zero is not possible: priceOfAssets[0] is greater than 0, totalSupply is greater than 0
                // when pendingRedeems is greater than 0
                uint256 rawAmount =
                    FixedPointMathLib.fullMulDiv(basketValue, pendingRedeems_, BasketToken(basket).totalSupply());
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 withdrawAmount = self.eulerRouter.getQuote(rawAmount, _USD_ISO_4217_CODE, assets[0]);
                if (withdrawAmount <= balances[0]) {
                    unchecked {
                        // Overflow not possible: withdrawAmount is less than or equal to balances[0]
                        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                        self.basketBalanceOf[basket][assets[0]] = balances[0] - withdrawAmount;
                    }
                    // slither-disable-next-line reentrancy-no-eth
                    IERC20(assets[0]).forceApprove(basket, withdrawAmount);
                    // ERC20.transferFrom is called in BasketToken.fulfillRedeem
                    // slither-disable-next-line reentrancy-no-eth
                    BasketToken(basket).fulfillRedeem(withdrawAmount);
                } else {
                    BasketToken(basket).fallbackRedeemTrigger();
                }
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
        // slither-disable-start low-level-calls
        (bool success, bytes memory data) =
            self.tokenSwapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.completeTokenSwap, (externalTrades)));
        // slither-disable-end low-level-calls
        if (!success) {
            // assume this low-level call never fails
            revert CompleteTokenSwapFailed();
        }
        claimedAmounts = abi.decode(data, (uint256[2][]));
    }

    /// @notice Internal function to update internal accounting with result of completed token swaps.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be completed.
    function _getResultsOfExternalTrades(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades
    )
        private
    {
        uint256 externalTradesLength = externalTrades.length;
        uint256[2][] memory claimedAmounts = _completeTokenSwap(self, externalTrades);
        // Update basketBalanceOf with amounts gained from swaps
        for (uint256 i = 0; i < externalTradesLength;) {
            ExternalTrade memory trade = externalTrades[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 tradeOwnershipLength = trade.basketTradeOwnership.length;
            for (uint256 j; j < tradeOwnershipLength;) {
                BasketTradeOwnership memory ownership = trade.basketTradeOwnership[j];
                address basket = ownership.basket;
                // Account for bought tokens
                // TODO: confirm if this is the correct index
                self.basketBalanceOf[basket][trade.buyToken] +=
                    FixedPointMathLib.fullMulDiv(claimedAmounts[i][0], ownership.tradeOwnership, 1e18);
                // Account for sold tokens
                self.basketBalanceOf[basket][trade.sellToken] = self.basketBalanceOf[basket][trade.sellToken]
                    + FixedPointMathLib.fullMulDiv(claimedAmounts[i][1], ownership.tradeOwnership, 1e18)
                    - FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, 1e18);
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
    /// @param afterTradeAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @param totalValue_ An initialized array of total basket values for each basket being rebalanced.
    function _initializeBasketData(
        BasketManagerStorage storage self,
        address[] calldata baskets,
        uint256[][] memory afterTradeAmounts_,
        uint256[] memory totalValue_
    )
        private
        view
    {
        uint256 numBaskets = baskets.length;
        for (uint256 i = 0; i < numBaskets;) {
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            afterTradeAmounts_[i] = new uint256[](assetsLength);
            for (uint256 j = 0; j < assetsLength;) {
                address asset = assets[j];
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 currentAssetAmount = self.basketBalanceOf[basket][asset];
                afterTradeAmounts_[i][j] = currentAssetAmount;
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                totalValue_[i] += self.eulerRouter.getQuote(currentAssetAmount, asset, _USD_ISO_4217_CODE);
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
    /// @param afterTradeAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @dev If the result of an internal trade is not within the provided minAmount or maxAmount, this function will
    /// revert.
    function _settleInternalTrades(
        BasketManagerStorage storage self,
        InternalTrade[] calldata internalTrades,
        address[] calldata baskets,
        uint256[][] memory afterTradeAmounts_
    )
        private
    {
        uint256 internalTradesLength = internalTrades.length;
        for (uint256 i = 0; i < internalTradesLength;) {
            InternalTrade memory trade = internalTrades[i];
            InternalTradeInfo memory info = InternalTradeInfo({
                fromBasketIndex: _indexOf(baskets, trade.fromBasket),
                toBasketIndex: _indexOf(baskets, trade.toBasket),
                sellTokenAssetIndex: basketTokenToRebalanceAssetToIndex(self, trade.fromBasket, trade.sellToken),
                buyTokenAssetIndex: basketTokenToRebalanceAssetToIndex(self, trade.fromBasket, trade.buyToken),
                toBasketBuyTokenIndex: basketTokenToRebalanceAssetToIndex(self, trade.toBasket, trade.buyToken),
                toBasketSellTokenIndex: basketTokenToRebalanceAssetToIndex(self, trade.toBasket, trade.sellToken),
                buyAmount: 0
            });
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.buyAmount = self.eulerRouter.getQuote(trade.sellAmount, trade.sellToken, trade.buyToken);

            if (info.buyAmount < trade.minAmount || trade.maxAmount < info.buyAmount) {
                revert InternalTradeMinMaxAmountNotReached();
            }
            // Settle the internal trades and track the balance changes
            if (trade.sellAmount > afterTradeAmounts_[info.fromBasketIndex][info.sellTokenAssetIndex]) {
                revert IncorrectTradeTokenAmount();
            }
            if (info.buyAmount > afterTradeAmounts_[info.toBasketIndex][info.toBasketBuyTokenIndex]) {
                revert IncorrectTradeTokenAmount();
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.fromBasket][trade.sellToken] = afterTradeAmounts_[info.fromBasketIndex][info
                .sellTokenAssetIndex] = self.basketBalanceOf[trade.fromBasket][trade.sellToken] - trade.sellAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.fromBasket][trade.buyToken] = afterTradeAmounts_[info.fromBasketIndex][info
                .buyTokenAssetIndex] = self.basketBalanceOf[trade.fromBasket][trade.buyToken] + info.buyAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.toBasket][trade.buyToken] = afterTradeAmounts_[info.toBasketIndex][info
                .toBasketBuyTokenIndex] = self.basketBalanceOf[trade.toBasket][trade.buyToken] - info.buyAmount; // nosemgrep
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[trade.toBasket][trade.sellToken] = afterTradeAmounts_[info.toBasketIndex][info
                .toBasketSellTokenIndex] = self.basketBalanceOf[trade.toBasket][trade.sellToken] + trade.sellAmount; // nosemgrep
            unchecked {
                ++i;
            }
            emit InternalTradeSettled(trade, info.buyAmount);
        }
    }

    /// @notice Internal function to validate the results of external trades.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be validated.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param totalValue_ Array of total basket values in USD.
    /// @param afterTradeAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @dev If the result of an external trade is not within the _MAX_SLIPPAGE_BPS threshold of the minAmount, this
    function _validateExternalTrades(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint256[] memory totalValue_,
        uint256[][] memory afterTradeAmounts_
    )
        private
    {
        for (uint256 i = 0; i < externalTrades.length;) {
            ExternalTrade memory trade = externalTrades[i];
            // slither-disable-start uninitialized-local
            ExternalTradeInfo memory info;
            BasketOwnershipInfo memory ownershipInfo;
            // slither-disable-end uninitialized-local

            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            for (uint256 j = 0; j < trade.basketTradeOwnership.length;) {
                BasketTradeOwnership memory ownership = trade.basketTradeOwnership[j];
                ownershipInfo.basketIndex = _indexOf(baskets, ownership.basket);
                ownershipInfo.buyTokenAssetIndex =
                    basketTokenToRebalanceAssetToIndex(self, ownership.basket, trade.buyToken);
                ownershipInfo.sellTokenAssetIndex =
                    basketTokenToRebalanceAssetToIndex(self, ownership.basket, trade.sellToken);
                uint256 ownershipSellAmount =
                    FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, 1e18);
                uint256 ownershipBuyAmount =
                    FixedPointMathLib.fullMulDiv(trade.minAmount, ownership.tradeOwnership, 1e18);
                // Record changes in basket asset holdings due to the external trade
                if (
                    ownershipSellAmount
                        > afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex]
                ) {
                    revert IncorrectTradeTokenAmount();
                }
                afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex] = afterTradeAmounts_[ownershipInfo
                    .basketIndex][ownershipInfo.sellTokenAssetIndex] - ownershipSellAmount;
                afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.buyTokenAssetIndex] =
                    afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.buyTokenAssetIndex] + ownershipBuyAmount;
                // Update total basket value
                totalValue_[ownershipInfo.basketIndex] = totalValue_[ownershipInfo.basketIndex]
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                - self.eulerRouter.getQuote(ownershipSellAmount, trade.sellToken, _USD_ISO_4217_CODE)
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                + self.eulerRouter.getQuote(ownershipBuyAmount, trade.buyToken, _USD_ISO_4217_CODE);
                unchecked {
                    ++j;
                }
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.sellValue = self.eulerRouter.getQuote(trade.sellAmount, trade.sellToken, _USD_ISO_4217_CODE);
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.internalMinAmount = self.eulerRouter.getQuote(info.sellValue, _USD_ISO_4217_CODE, trade.buyToken);
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

    /// @notice Internal function to validate the target weights for each basket have been met.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param afterTradeAmounts_ Array of asset amounts for each basket as updated with the results from
    /// both external and internal trades.
    /// @param totalValue_ Array of total basket values in USD.
    /// @dev If target weights are not within the _MAX_WEIGHT_DEVIATION_BPS threshold, this function will revert.
    function _validateTargetWeights(
        BasketManagerStorage storage self,
        address[] calldata baskets,
        uint256[][] memory afterTradeAmounts_,
        uint256[] memory totalValue_
    )
        private
        view
        returns (bool valid)
    {
        // Check if total weight change due to all trades is within the _MAX_WEIGHT_DEVIATION_BPS threshold
        uint256 len = baskets.length;
        for (uint256 i = 0; i < len;) {
            uint40 epoch = self.rebalanceStatus.epoch;
            address basket = baskets[i];
            // slither-disable-next-line calls-loop
            uint64[] memory proposedTargetWeights = BasketToken(basket).getTargetWeights(epoch);
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 proposedTargetWeightsLength = proposedTargetWeights.length;
            for (uint256 j = 0; j < proposedTargetWeightsLength;) {
                address asset = assets[j];
                uint256 assetValueInUSD =
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                 self.eulerRouter.getQuote(afterTradeAmounts_[i][j], asset, _USD_ISO_4217_CODE);
                console.log("asset, assetValueInUSD: ", asset, assetValueInUSD);
                // Rounding direction: down
                uint256 afterTradeWeight =
                    FixedPointMathLib.fullMulDiv(assetValueInUSD, _WEIGHT_PRECISION, totalValue_[i]);
                if (MathUtils.diff(proposedTargetWeights[j], afterTradeWeight) > _MAX_WEIGHT_DEVIATION_BPS) {
                    console.log("basket, asset: ", basket, asset);
                    console.log("proposedTargetWeights[%s]: %s", j, proposedTargetWeights[j]);
                    console.log("afterTradeWeight: %s, usdValue: %s", afterTradeWeight, assetValueInUSD);
                    return false;
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @notice Internal function to process pending deposits and fulfill them.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param basketValue Current value of the basket in USD.
    /// @param baseAssetBalance Current balance of the base asset in the basket.
    /// @param pendingDeposit Current assets pending deposit in the given basket.
    /// @return totalSupply Total supply of the basket token after processing pending deposits.
    /// @return pendingDepositValue Value of the pending deposits in USD.
    // slither-disable-next-line calls-loop
    function _processPendingDeposits(
        BasketManagerStorage storage self,
        address basket,
        uint256 basketValue,
        uint256 baseAssetBalance,
        uint256 pendingDeposit
    )
        private
        returns (uint256 totalSupply, uint256 pendingDepositValue)
    {
        totalSupply = BasketToken(basket).totalSupply();

        if (pendingDeposit > 0) {
            // Assume the first asset listed in the basket is the base asset
            // Round direction: down
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            pendingDepositValue =
                self.eulerRouter.getQuote(pendingDeposit, self.basketAssets[basket][0], _USD_ISO_4217_CODE);
            // Rounding direction: down
            // Division-by-zero is not possible: basketValue is greater than 0
            console.log("basket value: ", basketValue);
            uint256 requiredDepositShares = basketValue > 0
                ? FixedPointMathLib.fullMulDiv(pendingDepositValue, totalSupply, basketValue)
                : pendingDeposit;
            totalSupply += requiredDepositShares;
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[basket][self.basketAssets[basket][0]] += baseAssetBalance + pendingDeposit;
            // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
            BasketToken(basket).fulfillDeposit(requiredDepositShares);
        }
    }

    /// @notice Internal function to calculate the target balances for each asset in a given basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param basketValue Current value of the basket in USD.
    /// @param requiredWithdrawValue Value of the assets to be withdrawn from the basket.
    /// @param assets Array of asset addresses in the basket.
    /// @return targetBalances Array of target balances for each asset in the basket.
    // slither-disable-next-line calls-loop,naming-convention
    function _calculateTargetBalances(
        BasketManagerStorage storage self,
        address basket,
        uint256 basketValue,
        uint256 requiredWithdrawValue,
        address[] memory assets
    )
        private
        view
        returns (uint256[] memory targetBalances)
    {
        uint64[] memory proposedTargetWeights = BasketToken(basket).getTargetWeights(self.rebalanceStatus.epoch);
        uint256 assetsLength = assets.length;
        targetBalances = new uint256[](assetsLength);
        // Rounding direction: down
        // Division-by-zero is not possible: priceOfAssets[j] is greater than 0
        for (uint256 j = 0; j < assetsLength;) {
            targetBalances[j] =
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.eulerRouter.getQuote(
                FixedPointMathLib.fullMulDiv(proposedTargetWeights[j], basketValue, _WEIGHT_PRECISION),
                _USD_ISO_4217_CODE,
                assets[j]
            );

            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
        targetBalances[0] += self.eulerRouter.getQuote(requiredWithdrawValue, _USD_ISO_4217_CODE, assets[0]);
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
            basketValue += self.eulerRouter.getQuote(balances[j], assets[j], _USD_ISO_4217_CODE);
            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
    }

    /// @notice Internal function to check if a rebalance is required for the given basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param assets Array of asset addresses in the basket.
    /// @param balances Array of balances of each asset in the basket.
    /// @param targetBalances Array of target balances for each asset in the basket.
    /// @return shouldRebalance Boolean indicating if a rebalance is required.
    function _checkForRebalance(
        BasketManagerStorage storage self,
        address[] memory assets,
        uint256[] memory balances,
        uint256[] memory targetBalances
    )
        private
        view
        returns (bool shouldRebalance)
    {
        uint256 assetsLength = assets.length;
        for (uint256 j = 0; j < assetsLength;) {
            // Check if the target balance is different by more than 500 USD
            // NOTE: This implies it requires only one asset to be different by more than 500 USD
            //       to trigger a rebalance. This is placeholder logic and should be updated.
            // TODO: Update the logic to trigger a rebalance
            console.log("balances[%s]: %s", j, balances[j]);
            console.log("targetBalances[%s]: %s", j, targetBalances[j]);
            // TODO: verify what scale pyth returns for USD denominated value
            // TODO: is there a way to move this into the if statement that works with semgrep
            // slither-disable-start calls-loop
            if (
                self.eulerRouter.getQuote(MathUtils.diff(balances[j], targetBalances[j]), assets[j], _USD_ISO_4217_CODE)
                    > 500 // nosemgrep
            ) {
                shouldRebalance = true;
                break;
            }
            // slither-disable-end calls-loop
            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
    }
}

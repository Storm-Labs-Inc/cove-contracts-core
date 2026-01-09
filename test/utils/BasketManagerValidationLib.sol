// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPyth } from "@pyth/IPyth.sol";
import { PythStructs } from "@pyth/PythStructs.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";

import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { CurveEMAOracleUnderlying } from "src/oracles/CurveEMAOracleUnderlying.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";
import { IPriceOracleWithBaseAndQuote } from "src/interfaces/deps/IPriceOracleWithBaseAndQuote.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";

import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";
import { AutopoolOracle } from "src/oracles/AutopoolOracle.sol";
import { ChainedERC4626Oracle } from "src/oracles/ChainedERC4626Oracle.sol";
import { ERC4626Oracle } from "src/oracles/ERC4626Oracle.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";
/// @title BasketManagerValidationLib
/// @author Cove
/// @notice Library for testing the BasketManager contract. Other test contracts should import
/// this library and use it for BasketManager addresses.

library BasketManagerValidationLib {
    /// @notice Error thrown when an oracle is not configured for an asset
    error OracleNotConfigured(address asset);
    /// @notice Error thrown when an oracle is not an anchored oracle
    error NotAnchoredOracle(address asset);
    /// @notice Error thrown when an oracle path does not use both Pyth and Chainlink
    error InvalidOraclePath(address asset);
    /// @notice Error thrown when AnchoredOracle is given when expecting an oracle with a linear path to USD
    error OracleIsNotLinear(address asset);
    /// @notice Error thrown when an invalid oracle is given
    error InvalidOracle(address oracle);
    /// @notice Error thrown when base, cross, and quote are not properly configured for a CrossAdapter
    error InvalidCrossAdapter_BaseCrossMisMatch(
        address oracle,
        address base,
        address cross,
        address oracleBaseCross,
        address oracleBaseCrossBase,
        address oracleBaseCrossQuote
    );
    /// @notice Error thrown when base, cross, and quote are not properly configured for a CrossAdapter
    error InvalidCrossAdapter_CrossQuoteMisMatch(
        address oracle,
        address cross,
        address quote,
        address oracleCrossQuote,
        address oracleCrossQuoteBase,
        address oracleCrossQuoteQuote
    );

    /// @notice Struct for holding information about surplus and deficit of assets in a basket
    struct SurplusDeficit {
        address basket;
        address asset;
        uint256 surplus; // If > 0, surplus. If == 0, balanced.
        uint256 deficit; // If > 0, deficit. If == 0, balanced.
        uint256 currentAmount;
        uint256 targetAmount;
    }

    /// @notice Struct to hold working variables for testLib_generateInternalAndExternalTrades to avoid stack overflow
    struct TestLibGenerateTradesSlot {
        uint256 totalPairs;
        uint256 surplusDeficitCount;
        SurplusDeficit[] surplusDeficits;
        // Internal trades
        uint256 potentialInternalTradeCount;
        InternalTrade[] internalTrades;
        uint256 internalTradeCount;
        // External trades
        uint256 externalTradeCount;
        ExternalTrade[] externalTrades;
        uint256 currentExternalTrade;
        // Per basket calculation temps
        uint256 totalValue;
        uint256[] usdValues;
        uint256 baseAssetIndex;
        address baseAsset;
        uint256 redemptionValue;
        uint256 pendingRedeems;
        uint256 totalSupply;
        uint256 baseAssetTargetValue;
        uint256 baseAssetNeededForRedemption;
        uint256 baseAssetTotalTarget;
        uint256 currentBaseAssetAmount;
        // Per asset calculation temps
        uint256 targetValue;
        uint256 currentValue;
        uint256 currentAmount;
        uint256 targetAmount;
        uint256 tradeAmount;
        // External trade temps
        address deficitAsset;
        uint256 deficitAmount;
        uint256 sellAmount;
        uint256 sellValueUSD;
        uint256 expectedBuyAmount;
        uint256 minBuyAmount;
        BasketTradeOwnership[] tradeOwnerships;
        BasketTradeOwnership singleOwnership;
    }

    /// @notice USD address constant (using ISO 4217 currency code)
    address internal constant USD = address(840);
    address internal constant PYTH = address(0x4305FB66699C3B2702D4d05CF36551390A4c69C6);
    address internal constant BASE_PYTH = address(0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a);
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    // solhint-disable-next-line const-name-snakecase
    Vm internal constant vm = Vm(VM_ADDRESS);

    /// @notice Validates that all assets in the basket have properly configured oracles
    /// @param basketManager The BasketManager contract to validate
    function testLib_validateConfiguredOracles(BasketManager basketManager) internal view {
        // Get the EulerRouter from the BasketManager
        EulerRouter eulerRouter = EulerRouter(basketManager.eulerRouter());

        // Get all basket tokens
        address[] memory baskets = basketManager.basketTokens();

        // Iterate through each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            // Get all assets in the basket
            address[] memory assets = basketManager.basketAssets(baskets[i]);

            // Iterate through each asset
            for (uint256 j = 0; j < assets.length; j++) {
                address asset = assets[j];
                _validateOraclePath(eulerRouter, asset);
            }
        }
    }

    function testLib_updateOracleTimestamps(BasketManager basketManager) internal {
        // Get the EulerRouter from the BasketManager
        EulerRouter eulerRouter = EulerRouter(basketManager.eulerRouter());

        // Get all assets
        AssetRegistry assetRegistry = AssetRegistry(basketManager.assetRegistry());
        address[] memory assets = assetRegistry.getAllAssets();

        // Iterate through each asset
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            address oracle = eulerRouter.getConfiguredOracle(asset, USD);
            if (oracle == address(0)) {
                revert OracleNotConfigured(asset);
            }
            _updateOracleTimestamp(eulerRouter, oracle);
        }
    }

    function testLib_getTargetWeights(BasketManager basketManager)
        internal
        view
        returns (uint64[][] memory targetWeights)
    {
        address[] memory baskets = basketManager.basketTokens();
        targetWeights = new uint64[][](baskets.length);
        for (uint256 i = 0; i < baskets.length; i++) {
            targetWeights[i] = BasketToken(baskets[i]).getTargetWeights();
        }
    }

    function testLib_getTargetWeights(
        BasketManager,
        address[] memory baskets
    )
        internal
        view
        returns (uint64[][] memory targetWeights)
    {
        targetWeights = new uint64[][](baskets.length);
        for (uint256 i = 0; i < baskets.length; i++) {
            targetWeights[i] = BasketToken(baskets[i]).getTargetWeights();
        }
    }

    function testLib_getBasketAssets(
        BasketManager,
        address[] memory baskets
    )
        internal
        view
        returns (address[][] memory basketAssets)
    {
        basketAssets = new address[][](baskets.length);
        for (uint256 i = 0; i < baskets.length; i++) {
            basketAssets[i] = BasketToken(baskets[i]).getAssets();
        }
    }

    function testLib_needsRebalance(BasketManager basketManager, address[] memory baskets)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < baskets.length; i++) {
            if (testLib_needsRebalance(basketManager, baskets[i])) {
                return true;
            }
        }
        return false;
    }

    function testLib_needsRebalance(BasketManager basketManager) internal view returns (bool) {
        address[] memory baskets = basketManager.basketTokens();
        for (uint256 i = 0; i < baskets.length; i++) {
            if (testLib_needsRebalance(basketManager, baskets[i])) {
                return true;
            }
        }
        return false;
    }

    // solhint-disable-next-line code-complexity
    function testLib_needsRebalance(BasketManager basketManager, address basket) internal view returns (bool) {
        // Only if the basket rebalance status is NOT_STARTED
        if (basketManager.rebalanceStatus().status != Status.NOT_STARTED) {
            return false;
        }

        // Check if there is pending deposit, if so return true
        if (BasketToken(basket).totalPendingDeposits() > 0) {
            return true;
        }

        // Check if there is pending withdrawal, if so return true
        if (BasketToken(basket).totalPendingRedemptions() > 0) {
            return true;
        }

        // Check if the target weights have met
        uint64[] memory targetWeights = BasketToken(basket).getTargetWeights();

        // Calculate the current weights
        address[] memory assets = basketManager.basketAssets(basket);
        uint256[] memory usdValues = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            // get balances
            uint256 balance = basketManager.basketBalanceOf(basket, assets[i]);
            uint256 usdValue = _getPrimaryOracleQuote(EulerRouter(basketManager.eulerRouter()), balance, assets[i], USD);
            usdValues[i] = usdValue;
        }

        // Calculate the total USD value of the basket
        uint256 totalUsdValue = 0;
        for (uint256 i = 0; i < usdValues.length; i++) {
            totalUsdValue += usdValues[i];
        }
        if (totalUsdValue < 1e18) {
            return false;
        }

        // Calculate the current weights
        uint64[] memory currentWeights = new uint64[](assets.length);
        uint256 remainingSum = 1e18;
        for (uint256 i = 0; i < assets.length - 1; i++) {
            currentWeights[i] = uint64(usdValues[i] * 1e18 / totalUsdValue);
            remainingSum -= currentWeights[i];
        }
        currentWeights[assets.length - 1] = uint64(remainingSum);

        // Check if the target weights have met
        for (uint256 i = 0; i < targetWeights.length; i++) {
            // Check if the weight difference exceeds the configured weightDeviationLimit
            uint256 weightDiff = targetWeights[i] > currentWeights[i]
                ? targetWeights[i] - currentWeights[i]
                : currentWeights[i] - targetWeights[i];
            if (weightDiff > basketManager.weightDeviationLimit()) {
                return true;
            }
        }

        // If non of the above conditions are met, return false
        return false;
    }

    /// @notice Generates internal and external trades to rebalance a basket
    /// @dev This function analyzes the current state of the baskets and generates:
    /// 1. Internal trades between baskets (when one basket has a surplus of an asset another basket needs)
    /// 2. External trades for remaining imbalances within each basket
    /// The function considers pending redemptions and ensures base assets are set aside for them
    /// @param basketManager The BasketManager contract
    /// @param baskets Array of basket addresses to generate trades for
    /// @return internalTradesResult Array of internal trades between baskets
    /// @return externalTradesResult Array of external trades needed from DEXs or other external sources
    function testLib_generateInternalAndExternalTrades(
        BasketManager basketManager,
        address[] memory baskets,
        uint64[][] memory allTargetWeights
    )
        internal
        view
        returns (InternalTrade[] memory internalTradesResult, ExternalTrade[] memory externalTradesResult)
    {
        console.log("=== Starting trade generation for baskets ===", baskets.length);

        // Get the EulerRouter from the BasketManager
        EulerRouter eulerRouter = EulerRouter(basketManager.eulerRouter());

        // Create a slot to store all our working variables
        TestLibGenerateTradesSlot memory slot;

        // Calculate the number of basket-asset pairs
        slot.totalPairs = 0;
        for (uint256 i = 0; i < baskets.length; i++) {
            address[] memory assets = basketManager.basketAssets(baskets[i]);
            slot.totalPairs += assets.length;
            console.log(
                string.concat(
                    "Basket ",
                    vm.toString(i),
                    " : ",
                    vm.toString(baskets[i]),
                    " has assets: ",
                    vm.toString(assets.length)
                )
            );
        }
        console.log("Total basket-asset pairs: ", slot.totalPairs);

        testLib_compareCurrentAndTargetWeights(basketManager, baskets, allTargetWeights);

        // Calculate surplus and deficit for each asset in each basket
        slot = testLib_calculateSurplusAndDeficit(basketManager, eulerRouter, baskets, allTargetWeights, slot);

        // Generate internal trades
        slot = testLib_generateInternalTrades(slot);

        // Generate external trades
        slot = testLib_generateExternalTrades(eulerRouter, slot);

        // Return the final trade arrays
        internalTradesResult = slot.internalTrades;
        externalTradesResult = slot.externalTrades;

        console.log("\n=== Trade generation summary ===");
        console.log("Internal trades: ", internalTradesResult.length);
        console.log("External trades: ", externalTradesResult.length);
        console.log("=== End of trade generation ===\n");

        return (internalTradesResult, externalTradesResult);
    }

    // solhint-disable-next-line code-complexity
    function testLib_compareCurrentAndTargetWeights(
        BasketManager basketManager,
        address[] memory baskets,
        uint64[][] memory allTargetWeights
    )
        internal
        view
    {
        console.log("\n=== Comparing Current vs Target Weights ===");

        // Get the EulerRouter from the BasketManager
        EulerRouter eulerRouter = EulerRouter(basketManager.eulerRouter());

        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            address[] memory assets = basketManager.basketAssets(basket);
            uint64[] memory targetWeights = allTargetWeights[i];

            // Get current and adjusted target weights
            (uint256[] memory currentWeights, uint64[] memory adjustedTargetWeights) =
                testLib_getCurrentAndAdjustedTargetWeights(basketManager, eulerRouter, basket, assets, targetWeights);

            console.log(string.concat("Basket: ", vm.toString(basket)));

            // Calculate and log current weights vs adjusted target weights
            for (uint256 j = 0; j < assets.length; j++) {
                console.log(
                    string.concat(
                        "Asset: ",
                        vm.toString(assets[j]),
                        " Current Weight: ",
                        vm.toString(currentWeights[j]),
                        " (",
                        vm.toString(currentWeights[j] / 1e16),
                        "%) Redeem Adjusted Target Weight: ",
                        vm.toString(adjustedTargetWeights[j]),
                        " (",
                        vm.toString(adjustedTargetWeights[j] / 1e16),
                        "%) Original Target Weight: ",
                        vm.toString(targetWeights[j]),
                        " (",
                        vm.toString(targetWeights[j] / 1e16),
                        "%)"
                    )
                );
            }
            console.log("---");
        }
        console.log("=== End of Weight Comparison ===\n");
    }

    function testLib_getCurrentAndAdjustedTargetWeights(
        BasketManager basketManager,
        EulerRouter eulerRouter,
        address basket,
        address[] memory assets,
        uint64[] memory targetWeights
    )
        internal
        view
        returns (uint256[] memory currentWeights, uint64[] memory adjustedTargetWeights)
    {
        uint256 pendingRedeems = 0;
        if (basketManager.rebalanceStatus().status == Status.NOT_STARTED) {
            pendingRedeems = BasketToken(basket).totalPendingRedemptions();
        } else {
            pendingRedeems = _getPendingRedemptionSharesBeingProcessed(BasketToken(basket), basketManager);
        }

        // Calculate total USD value of the basket
        uint256 totalValue = 0;
        uint256[] memory assetValues = new uint256[](assets.length);

        for (uint256 j = 0; j < assets.length; j++) {
            uint256 balance = basketManager.basketBalanceOf(basket, assets[j]);
            assetValues[j] = _getPrimaryOracleQuote(eulerRouter, balance, assets[j], USD);
            totalValue += assetValues[j];
        }

        // Calculate current weights
        currentWeights = new uint256[](assets.length);
        for (uint256 j = 0; j < assets.length; j++) {
            currentWeights[j] = totalValue > 0 ? (assetValues[j] * 1e18 / totalValue) : 0;
        }

        // Calculate adjusted target weights accounting for pending redeems
        adjustedTargetWeights = new uint64[](assets.length);

        if (pendingRedeems > 0) {
            uint256 totalSupply = BasketToken(basket).totalSupply();
            uint256 remainingSupply = totalSupply - pendingRedeems;

            // Track running sum for all weights except the last one
            uint256 runningSum = 0;
            uint256 lastIndex = assets.length - 1;

            // Get base asset index
            uint256 baseAssetIndex = basketManager.basketTokenToBaseAssetIndex(basket);

            // Adjust weights while maintaining 1e18 sum
            for (uint256 j = 0; j < assets.length; j++) {
                if (j == lastIndex) {
                    // Use remainder for the last weight to ensure exact 1e18 sum
                    adjustedTargetWeights[j] = uint64(1e18 - runningSum);
                } else if (j == baseAssetIndex) {
                    // Increase base asset weight by adding extra weight from pending redeems
                    adjustedTargetWeights[j] = uint64(
                        FixedPointMathLib.fullMulDiv(
                            FixedPointMathLib.fullMulDiv(remainingSupply, targetWeights[j], 1e18) + pendingRedeems,
                            1e18,
                            totalSupply
                        )
                    );
                    runningSum += adjustedTargetWeights[j];
                } else {
                    // Scale down other weights proportionally
                    adjustedTargetWeights[j] =
                        uint64(FixedPointMathLib.fullMulDiv(remainingSupply, targetWeights[j], totalSupply));
                    runningSum += adjustedTargetWeights[j];
                }
            }
        } else {
            // If no pending redeems, use original target weights
            adjustedTargetWeights = targetWeights;
        }

        return (currentWeights, adjustedTargetWeights);
    }

    /// @notice Calculates surplus and deficit for each asset in each basket
    /// @param basketManager The BasketManager contract
    /// @param eulerRouter The EulerRouter contract
    /// @param baskets Array of basket addresses
    /// @param allTargetWeights Target weights for each basket
    /// @param slot The working variables slot
    /// @return Updated slot with surplus and deficit information
    // solhint-disable-next-line code-complexity
    function testLib_calculateSurplusAndDeficit(
        BasketManager basketManager,
        EulerRouter eulerRouter,
        address[] memory baskets,
        uint64[][] memory allTargetWeights,
        TestLibGenerateTradesSlot memory slot
    )
        internal
        view
        returns (TestLibGenerateTradesSlot memory)
    {
        // Create arrays to store surplus and deficit information for each asset in each basket
        slot.surplusDeficits = new SurplusDeficit[](slot.totalPairs);
        slot.surplusDeficitCount = 0;

        // For each basket, calculate surplus/deficit for each asset
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            console.log("\n--- Processing basket ---", basket);

            address[] memory assets = basketManager.basketAssets(basket);
            uint64[] memory targetWeights = allTargetWeights[i];

            // Get the base asset index for this basket
            slot.baseAssetIndex = basketManager.basketTokenToBaseAssetIndex(basket);
            slot.baseAsset = assets[slot.baseAssetIndex];
            console.log(
                string.concat("Base asset: ", vm.toString(slot.baseAsset), " index: ", vm.toString(slot.baseAssetIndex))
            );

            // Calculate total USD value of the basket and base asset requirements for redemptions
            slot.totalValue = 0;
            slot.usdValues = new uint256[](assets.length);

            for (uint256 j = 0; j < assets.length; j++) {
                uint256 balance = basketManager.basketBalanceOf(basket, assets[j]);
                slot.usdValues[j] = _getPrimaryOracleQuote(eulerRouter, balance, assets[j], USD);
                slot.totalValue += slot.usdValues[j];
                console.log(
                    string.concat(
                        "Asset ",
                        vm.toString(j),
                        " : ",
                        vm.toString(assets[j]),
                        " Balance: ",
                        vm.toString(balance),
                        " USD Value: ",
                        vm.toString(slot.usdValues[j])
                    )
                );
            }
            console.log("Total basket USD value: ", slot.totalValue);

            // Handle pending redemptions - need to set aside base asset
            // Assumes the rebalance cycle has already started, thus we use the nextRedeemRequestId - 2
            // Only if the basket rebalance status is NOT_STARTED
            if (basketManager.rebalanceStatus().status == Status.NOT_STARTED) {
                slot.pendingRedeems = BasketToken(basket).totalPendingRedemptions();
            } else {
                slot.pendingRedeems = _getPendingRedemptionSharesBeingProcessed(BasketToken(basket), basketManager);
            }
            slot.totalSupply = BasketToken(basket).totalSupply();
            slot.redemptionValue = 0;

            console.log("Pending redemptions: ", slot.pendingRedeems);
            console.log("Total supply: ", slot.totalSupply);

            console.log("--- Processing redemptions ---");
            // Calculate the USD value needed for redemptions
            slot.redemptionValue = FixedPointMathLib.fullMulDiv(slot.totalValue, slot.pendingRedeems, slot.totalSupply);
            console.log("Redemption USD value: ", slot.redemptionValue);

            // Adjust the target value for base asset to account for redemptions
            slot.baseAssetTargetValue = FixedPointMathLib.fullMulDiv(
                slot.totalValue - slot.redemptionValue, targetWeights[slot.baseAssetIndex], 1e18
            );
            slot.baseAssetNeededForRedemption =
                _getPrimaryOracleQuote(eulerRouter, slot.redemptionValue, USD, assets[slot.baseAssetIndex]);
            slot.baseAssetTotalTarget = slot.baseAssetNeededForRedemption
                + _getPrimaryOracleQuote(eulerRouter, slot.baseAssetTargetValue, USD, assets[slot.baseAssetIndex]);

            console.log("Base asset target value (excl. redemptions): ", slot.baseAssetTargetValue);
            console.log("Base asset needed for redemptions: ", slot.baseAssetNeededForRedemption);
            console.log("Base asset total target: ", slot.baseAssetTotalTarget);

            // Record surplus/deficit for base asset considering redemptions
            slot.currentBaseAssetAmount = basketManager.basketBalanceOf(basket, slot.baseAsset);
            if (slot.currentBaseAssetAmount > slot.baseAssetTotalTarget) {
                slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                    basket: basket,
                    asset: slot.baseAsset,
                    surplus: slot.currentBaseAssetAmount - slot.baseAssetTotalTarget,
                    deficit: 0,
                    currentAmount: slot.currentBaseAssetAmount,
                    targetAmount: slot.baseAssetTotalTarget
                });
                console.log("Base asset SURPLUS: ", slot.currentBaseAssetAmount - slot.baseAssetTotalTarget);
            } else if (slot.currentBaseAssetAmount < slot.baseAssetTotalTarget) {
                slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                    basket: basket,
                    asset: slot.baseAsset,
                    surplus: 0,
                    deficit: slot.baseAssetTotalTarget - slot.currentBaseAssetAmount,
                    currentAmount: slot.currentBaseAssetAmount,
                    targetAmount: slot.baseAssetTotalTarget
                });
                console.log("Base asset DEFICIT: ", slot.baseAssetTotalTarget - slot.currentBaseAssetAmount);
            } else {
                slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                    basket: basket,
                    asset: slot.baseAsset,
                    surplus: 0,
                    deficit: 0,
                    currentAmount: slot.currentBaseAssetAmount,
                    targetAmount: slot.baseAssetTotalTarget
                });
                console.log("Base asset BALANCED");
            }
            slot.surplusDeficitCount++;

            // Adjust total value to account for redemptions
            slot.totalValue -= slot.redemptionValue;
            console.log("Adjusted total USD value (excl. redemptions): ", slot.totalValue);

            // Calculate surplus/deficit for non-base assets
            console.log("--- Processing non-base assets ---");
            for (uint256 j = 0; j < assets.length; j++) {
                if (j != slot.baseAssetIndex) {
                    // Skip base asset as it's already handled
                    slot.targetValue = FixedPointMathLib.fullMulDiv(slot.totalValue, targetWeights[j], 1e18);
                    slot.currentValue = slot.usdValues[j];

                    console.log(
                        string.concat(
                            "Asset ",
                            vm.toString(assets[j]),
                            " Target weight: ",
                            vm.toString(targetWeights[j]),
                            " Target USD value: ",
                            vm.toString(slot.targetValue),
                            " Current USD value: ",
                            vm.toString(slot.currentValue)
                        )
                    );

                    slot.currentAmount = basketManager.basketBalanceOf(basket, assets[j]);
                    slot.targetAmount = 0;

                    if (slot.currentValue > 0) {
                        // Convert target USD value to asset amount
                        slot.targetAmount =
                            FixedPointMathLib.fullMulDiv(slot.targetValue, slot.currentAmount, slot.currentValue);
                    } else if (slot.targetValue > 0) {
                        // If current value is 0 but target is not, use price to calculate target amount
                        slot.targetAmount = _getPrimaryOracleQuote(eulerRouter, slot.targetValue, USD, assets[j]);
                    }

                    console.log(
                        string.concat(
                            "Asset ",
                            vm.toString(assets[j]),
                            " Current amount: ",
                            vm.toString(slot.currentAmount),
                            " Target amount: ",
                            vm.toString(slot.targetAmount)
                        )
                    );

                    if (slot.currentAmount > slot.targetAmount) {
                        slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                            basket: basket,
                            asset: assets[j],
                            surplus: slot.currentAmount - slot.targetAmount,
                            deficit: 0,
                            currentAmount: slot.currentAmount,
                            targetAmount: slot.targetAmount
                        });
                        console.log("Asset ", assets[j], " SURPLUS: ", slot.currentAmount - slot.targetAmount);
                    } else if (slot.currentAmount < slot.targetAmount) {
                        slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                            basket: basket,
                            asset: assets[j],
                            surplus: 0,
                            deficit: slot.targetAmount - slot.currentAmount,
                            currentAmount: slot.currentAmount,
                            targetAmount: slot.targetAmount
                        });
                        console.log("Asset ", assets[j], " DEFICIT: ", slot.targetAmount - slot.currentAmount);
                    } else {
                        slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                            basket: basket,
                            asset: assets[j],
                            surplus: 0,
                            deficit: 0,
                            currentAmount: slot.currentAmount,
                            targetAmount: slot.targetAmount
                        });
                        console.log("Asset ", assets[j], " BALANCED");
                    }
                    slot.surplusDeficitCount++;
                }
            }
        }

        return slot;
    }

    /// @notice Generates internal trades between baskets
    /// @param slot The working variables slot with surplus/deficit information
    /// @return Updated slot with internal trades
    // solhint-disable-next-line code-complexity
    function testLib_generateInternalTrades(TestLibGenerateTradesSlot memory slot)
        internal
        view
        returns (TestLibGenerateTradesSlot memory)
    {
        console.log("\n=== Generating internal trades ===");
        console.log("Total surplus/deficit records: ", slot.surplusDeficitCount);

        // Count how many internal trades we need to generate
        slot.potentialInternalTradeCount = 0;
        for (uint256 i = 0; i < slot.surplusDeficitCount; i++) {
            if (slot.surplusDeficits[i].surplus > 0) {
                for (uint256 j = 0; j < slot.surplusDeficitCount; j++) {
                    if (
                        i != j && slot.surplusDeficits[j].deficit > 0
                            && slot.surplusDeficits[i].basket != slot.surplusDeficits[j].basket
                            && slot.surplusDeficits[i].asset == slot.surplusDeficits[j].asset
                    ) {
                        slot.potentialInternalTradeCount++;
                    }
                }
            }
        }

        console.log("Potential internal trades: ", slot.potentialInternalTradeCount);

        // Generate internal trades - match surplus of one basket with deficit of another
        slot.internalTrades = new InternalTrade[](slot.potentialInternalTradeCount);
        slot.internalTradeCount = 0;

        for (
            uint256 i = 0;
            i < slot.surplusDeficitCount && slot.internalTradeCount < slot.potentialInternalTradeCount;
            i++
        ) {
            if (slot.surplusDeficits[i].surplus > 0) {
                for (uint256 j = 0; j < slot.surplusDeficitCount; j++) {
                    if (
                        i != j && slot.surplusDeficits[j].deficit > 0
                            && slot.surplusDeficits[i].basket != slot.surplusDeficits[j].basket
                            && slot.surplusDeficits[i].asset == slot.surplusDeficits[j].asset
                    ) {
                        // Calculate trade amount (min of surplus and deficit)
                        slot.tradeAmount = slot.surplusDeficits[i].surplus < slot.surplusDeficits[j].deficit
                            ? slot.surplusDeficits[i].surplus
                            : slot.surplusDeficits[j].deficit;

                        if (slot.tradeAmount > 0) {
                            // Create internal trade: fromBasket sells asset to toBasket
                            // Note: For internal trades, the same asset is both sold and bought (just transferred
                            // between baskets)
                            slot.internalTrades[slot.internalTradeCount] = InternalTrade({
                                fromBasket: slot.surplusDeficits[i].basket,
                                toBasket: slot.surplusDeficits[j].basket,
                                sellToken: slot.surplusDeficits[i].asset,
                                buyToken: slot.surplusDeficits[i].asset,
                                sellAmount: slot.tradeAmount,
                                minAmount: slot.tradeAmount,
                                maxAmount: slot.tradeAmount
                            });

                            console.log(
                                string.concat(
                                    "INTERNAL TRADE",
                                    vm.toString(slot.internalTradeCount),
                                    "From:",
                                    vm.toString(slot.surplusDeficits[i].basket),
                                    "To:",
                                    vm.toString(slot.surplusDeficits[j].basket),
                                    "Asset:",
                                    vm.toString(slot.surplusDeficits[i].asset),
                                    "Amount:",
                                    vm.toString(slot.tradeAmount)
                                )
                            );

                            // Update surplus and deficit
                            slot.surplusDeficits[i].surplus -= slot.tradeAmount;
                            slot.surplusDeficits[j].deficit -= slot.tradeAmount;
                            slot.internalTradeCount++;
                        }
                    }
                }
            }
        }

        console.log("Generated internal trades: ", slot.internalTradeCount);

        // Resize internal trades array to actual count
        if (slot.internalTradeCount < slot.potentialInternalTradeCount) {
            InternalTrade[] memory rightSizedInternalTrades = new InternalTrade[](slot.internalTradeCount);
            for (uint256 i = 0; i < slot.internalTradeCount; i++) {
                rightSizedInternalTrades[i] = slot.internalTrades[i];
            }
            slot.internalTrades = rightSizedInternalTrades;
            console.log(
                "Resized internal trades array from", slot.potentialInternalTradeCount, "to", slot.internalTradeCount
            );
        }

        return slot;
    }

    /// @notice Generates external trades for remaining imbalances
    /// @param eulerRouter The EulerRouter contract
    /// @param slot The working variables slot with updated surplus/deficit after internal trades
    /// @return Updated slot with external trades
    // solhint-disable-next-line code-complexity
    function testLib_generateExternalTrades(
        EulerRouter eulerRouter,
        TestLibGenerateTradesSlot memory slot
    )
        internal
        view
        returns (TestLibGenerateTradesSlot memory)
    {
        console.log("\n=== Generating external trades ===");

        // Count remaining surplus/deficit for external trades
        // For each basket, we'll use surplus assets to cover deficits of other assets
        slot.externalTradeCount = 0;

        // First pass: Calculate total number of potential trades
        for (uint256 i = 0; i < slot.surplusDeficitCount; i++) {
            if (slot.surplusDeficits[i].surplus > 0) {
                // For each surplus, we need to find deficit assets in the same basket
                for (uint256 j = 0; j < slot.surplusDeficitCount; j++) {
                    if (
                        slot.surplusDeficits[j].deficit > 0
                            && slot.surplusDeficits[i].basket == slot.surplusDeficits[j].basket
                    ) {
                        slot.externalTradeCount++;
                    }
                }
            }
        }

        console.log("Potential external trades: ", slot.externalTradeCount);

        // Generate external trades for remaining imbalances
        slot.externalTrades = new ExternalTrade[](slot.externalTradeCount);
        slot.currentExternalTrade = 0;

        // Second pass: Generate actual trades - iterate through surpluses first
        for (uint256 i = 0; i < slot.surplusDeficitCount && slot.currentExternalTrade < slot.externalTradeCount; i++) {
            if (slot.surplusDeficits[i].surplus > 0) {
                // Calculate USD value of surplus
                uint256 surplusValueUSD = _getPrimaryOracleQuote(
                    eulerRouter, slot.surplusDeficits[i].surplus, slot.surplusDeficits[i].asset, USD
                );

                // Find deficit assets in the same basket to match with this surplus
                for (uint256 j = 0; j < slot.surplusDeficitCount && surplusValueUSD > 0; j++) {
                    if (
                        slot.surplusDeficits[j].deficit > 0
                            && slot.surplusDeficits[i].basket == slot.surplusDeficits[j].basket
                    ) {
                        // Calculate USD value of deficit
                        uint256 deficitValueUSD = _getPrimaryOracleQuote(
                            eulerRouter, slot.surplusDeficits[j].deficit, slot.surplusDeficits[j].asset, USD
                        );

                        // Use either the full surplus or just enough to cover the deficit
                        uint256 tradeUSD = surplusValueUSD > deficitValueUSD ? deficitValueUSD : surplusValueUSD;

                        // Calculate actual amounts to trade
                        slot.sellAmount =
                            _getPrimaryOracleQuote(eulerRouter, tradeUSD, USD, slot.surplusDeficits[i].asset);

                        // Ensure we don't sell more than available surplus
                        if (slot.sellAmount > slot.surplusDeficits[i].surplus) {
                            slot.sellAmount = slot.surplusDeficits[i].surplus;
                            // Recalculate tradeUSD based on actual sellAmount
                            tradeUSD = _getPrimaryOracleQuote(
                                eulerRouter, slot.sellAmount, slot.surplusDeficits[i].asset, USD
                            );
                        }

                        slot.expectedBuyAmount =
                            _getPrimaryOracleQuote(eulerRouter, tradeUSD, USD, slot.surplusDeficits[j].asset);

                        // Apply 0.5% slippage
                        slot.minBuyAmount = slot.expectedBuyAmount * 995 / 1000;

                        // Create trade ownership
                        slot.tradeOwnerships = new BasketTradeOwnership[](1);
                        slot.singleOwnership = BasketTradeOwnership({
                            basket: slot.surplusDeficits[i].basket, tradeOwnership: uint96(1e18)
                        });
                        slot.tradeOwnerships[0] = slot.singleOwnership;

                        // Create external trade
                        slot.externalTrades[slot.currentExternalTrade] = ExternalTrade({
                            sellToken: slot.surplusDeficits[i].asset,
                            buyToken: slot.surplusDeficits[j].asset,
                            sellAmount: slot.sellAmount,
                            minAmount: slot.minBuyAmount,
                            basketTradeOwnership: slot.tradeOwnerships
                        });

                        console.log(
                            string.concat(
                                "EXTERNAL TRADE ",
                                vm.toString(slot.currentExternalTrade),
                                " Basket: ",
                                vm.toString(slot.surplusDeficits[i].basket),
                                " Sells: ",
                                vm.toString(slot.surplusDeficits[i].asset),
                                " Sell Amount: ",
                                vm.toString(slot.sellAmount),
                                " Buys: ",
                                vm.toString(slot.surplusDeficits[j].asset),
                                " Min Buy Amount: ",
                                vm.toString(slot.minBuyAmount)
                            )
                        );

                        slot.currentExternalTrade++;

                        // Update remaining surplus and deficit
                        slot.surplusDeficits[i].surplus -= slot.sellAmount;
                        surplusValueUSD -= tradeUSD;

                        // Update deficit amount
                        if (slot.expectedBuyAmount >= slot.surplusDeficits[j].deficit) {
                            slot.surplusDeficits[j].deficit = 0;
                        } else {
                            slot.surplusDeficits[j].deficit -= slot.expectedBuyAmount;
                        }

                        // If we've used all of this surplus, move to the next surplus
                        if (slot.surplusDeficits[i].surplus == 0 || surplusValueUSD == 0) {
                            break;
                        }
                    }
                }
            }
        }

        console.log("Generated external trades: ", slot.currentExternalTrade);

        // Resize external trades array to actual count
        if (slot.currentExternalTrade < slot.externalTradeCount) {
            ExternalTrade[] memory rightSizedExternalTrades = new ExternalTrade[](slot.currentExternalTrade);
            for (uint256 i = 0; i < slot.currentExternalTrade; i++) {
                rightSizedExternalTrades[i] = slot.externalTrades[i];
            }
            slot.externalTrades = rightSizedExternalTrades;
            console.log(
                "Resized external trades array from ", slot.externalTradeCount, " to ", slot.currentExternalTrade
            );
        }

        return slot;
    }

    function testLib_getPrimaryOracleQuote(
        BasketManager basketManager,
        uint256 amount,
        address base,
        address quote
    )
        internal
        view
        returns (uint256)
    {
        return _getPrimaryOracleQuote(EulerRouter(basketManager.eulerRouter()), amount, base, quote);
    }

    function _getPrimaryOracleQuote(
        EulerRouter eulerRouter,
        uint256 amount,
        address base,
        address quote
    )
        internal
        view
        returns (uint256)
    {
        if (amount == 0) {
            return 0;
        }
        address anchoredOracle = eulerRouter.getConfiguredOracle(base, quote);
        if (anchoredOracle == address(0)) {
            revert OracleNotConfigured(base);
        }
        return IPriceOracle(AnchoredOracle(anchoredOracle).primaryOracle()).getQuote(amount, base, quote);
    }

    function _updateOracleTimestamp(EulerRouter eulerRouter, address oracle) private {
        // Update the oracle timestamp
        if (_isAnchoredOracle(oracle)) {
            _updateOracleTimestamp(eulerRouter, AnchoredOracle(oracle).primaryOracle());
            _updateOracleTimestamp(eulerRouter, AnchoredOracle(oracle).anchorOracle());
        } else if (_isCrossAdapter(oracle)) {
            _updateOracleTimestamp(eulerRouter, CrossAdapter(oracle).oracleBaseCross());
            _updateOracleTimestamp(eulerRouter, CrossAdapter(oracle).oracleCrossQuote());
        } else if (_isERC4626Oracle(oracle)) {
            // Do nothing
            return;
        } else if (_isPythOracle(oracle)) {
            _updatePythOracleTimeStamp(PythOracle(oracle).feedId());
        } else if (_isChainlinkOracle(oracle)) {
            _updateChainLinkOracleTimeStamp(ChainlinkOracle(oracle).feed());
        } else if (_isCurveEMAOracleUnderlying(oracle)) {
            // Do nothing
        } else if (_isChainedERC4626Oracle(oracle)) {
            // Do nothing
        } else if (_isAutoPoolCompounderOracle(oracle)) {
            // Do nothing
        } else if (_isAutopoolOracle(oracle)) {
            // Do nothing
        } else {
            revert InvalidOracle(oracle);
        }
    }

    function _pyth() internal view returns (address) {
        if (block.chainid == 8453) {
            return BASE_PYTH;
        }
        return PYTH;
    }

    // Updates the timestamp of a Pyth oracle response to the current block timestamp
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        vm.record();
        IPyth(_pyth()).getPriceUnsafe(pythPriceFeed);
        (bytes32[] memory readSlots,) = vm.accesses(_pyth());
        // Second read slot contains the timestamp in the last 32 bits
        // key   "0x28b01e5f9379f2a22698d286ce7faa0c31f6e4041ee32933d99cfe45a4a8ced5":
        // value "0x0000000000000000071021bc0000003f435df940fffffff80000000067a59cb0",
        // Where timestamp is 0x67a59cb0
        // overwrite this by using vm.store(readSlots[1], modified state)
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData =
            bytes32((uint256(vm.load(_pyth(), readSlots[1])) & ~uint256(0xFFFFFFFF)) | newPublishTime);
        vm.store(_pyth(), readSlots[1], modifiedStorageData);

        // Verify the storage was updated.
        PythStructs.Price memory res = IPyth(_pyth()).getPriceUnsafe(pythPriceFeed);
        require(res.publishTime == newPublishTime, "PythOracle timestamp was not updated correctly");
    }

    // Updates the timestamp of a ChainLink oracle response to the current block timestamp
    function _updateChainLinkOracleTimeStamp(address chainlinkOracle) internal {
        address aggregator = IChainlinkAggregatorV3Interface(chainlinkOracle).aggregator();
        vm.record();
        (,,, uint256 oldTimestamp,) = IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        (bytes32[] memory readSlots,) = vm.accesses(aggregator);
        // The third slot that is read is the storage slot in which the timestamp is stored in
        // Format: 0x67a4876b67a48757000000000000000000000000000000000f806f93b728efc0
        // Where 0x67a4876b is the timestamp
        // It also could be shifted by 32 bits to the right so in case the first 32 bits are not the same as
        // oldTimestamp, check if the next
        // 32 bits are the same as oldTimestamp
        uint256 maybeOldTimestamp = uint256(vm.load(aggregator, readSlots[2])) >> (224);
        uint256 offset = 0;
        if (maybeOldTimestamp != oldTimestamp) {
            maybeOldTimestamp = (uint256(vm.load(aggregator, readSlots[2])) << 32) >> 224;
            if (maybeOldTimestamp != oldTimestamp) {
                revert("Slot could not be found");
            }
            offset = 32;
        }
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData = bytes32(
            (uint256(vm.load(aggregator, readSlots[2])) & ~(uint256(0xFFFFFFFF) << (224 - offset)))
                | (newPublishTime << (224 - offset))
        );
        vm.store(aggregator, readSlots[2], modifiedStorageData);

        // Verify the storage was updated
        (,,, uint256 updatedTimestamp,) = IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        require(updatedTimestamp == newPublishTime, "ChainLink timestamp was not updated correctly");
    }

    /// @notice Helper function to validate that an oracle path uses both Pyth and Chainlink
    /// @param eulerRouter The EulerRouter contract
    /// @param asset The asset to validate
    function _validateOraclePath(EulerRouter eulerRouter, address asset) private view {
        // Get the configured oracle for this asset pair
        address oracle = eulerRouter.getConfiguredOracle(asset, USD);
        if (oracle == address(0)) {
            revert OracleNotConfigured(asset);
        }

        bool isAnchoredOracle = _isAnchoredOracle(oracle);
        if (!isAnchoredOracle) {
            revert NotAnchoredOracle(asset);
        }

        // For AnchoredOracle, we need to verify that one path uses Pyth and the other uses Chainlink
        address primaryOracleAddr = AnchoredOracle(oracle).primaryOracle();
        address anchorOracleAddr = AnchoredOracle(oracle).anchorOracle();

        // Validate the primary and anchor oracle paths
        bool primaryHasPyth = _isOraclePathPyth(primaryOracleAddr);
        bool primaryHasChainlink = _isOraclePathChainlink(primaryOracleAddr);
        bool anchorHasPyth = _isOraclePathPyth(anchorOracleAddr);
        bool anchorHasChainlink = _isOraclePathChainlink(anchorOracleAddr);

        // We require that one path uses Pyth and the other uses Chainlink
        // Typical configurations:
        // Primary = Pyth, Anchor = Chainlink
        if (!(primaryHasPyth && anchorHasChainlink && !primaryHasChainlink && !anchorHasPyth)) {
            revert InvalidOraclePath(asset);
        }
    }

    /// @notice Validates a CrossAdapter oracle by checking its paths
    /// @param oracleAddr The CrossAdapter oracle address
    function _validateCrossAdapterPath(address oracleAddr) private view {
        // Get the CrossAdapter's oracles
        address oracleBaseCross = CrossAdapter(oracleAddr).oracleBaseCross();
        address oracleCrossQuote = CrossAdapter(oracleAddr).oracleCrossQuote();

        address base = CrossAdapter(oracleAddr).base();
        address cross = CrossAdapter(oracleAddr).cross();
        address quote = CrossAdapter(oracleAddr).quote();

        address oracleBaseCrossBase = IPriceOracleWithBaseAndQuote(oracleBaseCross).base();
        address oracleBaseCrossQuote = IPriceOracleWithBaseAndQuote(oracleBaseCross).quote();
        address oracleCrossQuoteBase = IPriceOracleWithBaseAndQuote(oracleCrossQuote).base();
        address oracleCrossQuoteQuote = IPriceOracleWithBaseAndQuote(oracleCrossQuote).quote();

        // Check if the CrossAdapter's base, cross, and quote are all respected by the oracle paths
        if (
            (base != oracleBaseCrossBase || cross != oracleBaseCrossQuote)
                && (base != oracleBaseCrossQuote || cross != oracleBaseCrossBase)
        ) {
            revert InvalidCrossAdapter_BaseCrossMisMatch(
                oracleAddr, base, cross, oracleBaseCross, oracleBaseCrossBase, oracleBaseCrossQuote
            );
        }
        if (
            (cross != oracleCrossQuoteBase || quote != oracleCrossQuoteQuote)
                && (cross != oracleCrossQuoteQuote || quote != oracleCrossQuoteBase)
        ) {
            revert InvalidCrossAdapter_CrossQuoteMisMatch(
                oracleAddr, cross, quote, oracleCrossQuote, oracleCrossQuoteBase, oracleCrossQuoteQuote
            );
        }
    }

    /// @notice Checks if an oracle path includes Pyth at any point
    /// @param oracle The oracle to check
    /// @return True if the oracle path includes Pyth
    function _isOraclePathPyth(address oracle) private view returns (bool) {
        // Direct check
        if (_isPythOracle(oracle)) {
            return true;
        }

        // Check if it's an AnchoredOracle. In this case, the oracle is linear and could be of multiple types
        if (_isAnchoredOracle(oracle)) {
            revert OracleIsNotLinear(oracle);
        }

        // Check if it's a CrossAdapter with Pyth
        if (_isCrossAdapter(oracle)) {
            address oracleBaseCross = CrossAdapter(oracle).oracleBaseCross();
            address oracleCrossQuote = CrossAdapter(oracle).oracleCrossQuote();
            _validateCrossAdapterPath(oracle);
            return (_isOraclePathPyth(oracleBaseCross) || _isOraclePathPyth(oracleCrossQuote))
                && (!_isOraclePathChainlink(oracleBaseCross) && !_isOraclePathChainlink(oracleCrossQuote));
        }

        return false;
    }

    /// @notice Checks if an oracle path includes Chainlink at any point
    /// @param oracle The oracle to check
    /// @return True if the oracle path includes Chainlink
    function _isOraclePathChainlink(address oracle) private view returns (bool) {
        // Direct check
        if (_isChainlinkOracle(oracle)) {
            return true;
        }

        // Check if it's an AnchoredOracle. In this case, the oracle is linear and could be of multiple types
        if (_isAnchoredOracle(oracle)) {
            revert OracleIsNotLinear(oracle);
        }

        // Check if it's a CrossAdapter with Chainlink
        if (_isCrossAdapter(oracle)) {
            address oracleBaseCross = CrossAdapter(oracle).oracleBaseCross();
            address oracleCrossQuote = CrossAdapter(oracle).oracleCrossQuote();
            _validateCrossAdapterPath(oracle);
            return (_isOraclePathChainlink(oracleBaseCross) || _isOraclePathChainlink(oracleCrossQuote))
                && (!_isOraclePathPyth(oracleBaseCross) && !_isOraclePathPyth(oracleCrossQuote));
        }

        return false;
    }

    /// @notice Helper function to check if an oracle is an AnchoredOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is an AnchoredOracle
    function _isAnchoredOracle(address oracle) private view returns (bool) {
        try AnchoredOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("AnchoredOracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a CrossAdapter
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a CrossAdapter
    function _isCrossAdapter(address oracle) private view returns (bool) {
        try CrossAdapter(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("CrossAdapter"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is an ERC4626Oracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is an ERC4626Oracle
    function _isERC4626Oracle(address oracle) private view returns (bool) {
        try ERC4626Oracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("ERC4626Oracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a PythOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a PythOracle
    function _isPythOracle(address oracle) private view returns (bool) {
        try PythOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("PythOracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a ChainlinkOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a ChainlinkOracle
    function _isChainlinkOracle(address oracle) private view returns (bool) {
        try ChainlinkOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("ChainlinkOracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a CurveEMAOracleUnderlying
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a CurveEMAOracleUnderlying
    function _isCurveEMAOracleUnderlying(address oracle) private view returns (bool) {
        try CurveEMAOracleUnderlying(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("CurveEMAOracleUnderlying"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a ChainedERC4626Oracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a ChainedERC4626Oracle
    function _isChainedERC4626Oracle(address oracle) private view returns (bool) {
        try ChainedERC4626Oracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("ChainedERC4626Oracle"));
        } catch {
            return false;
        }
    }

    function _isAutoPoolCompounderOracle(address oracle) private view returns (bool) {
        try AutoPoolCompounderOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("AutoPoolCompounderOracle"));
        } catch {
            return false;
        }
    }

    function _isAutopoolOracle(address oracle) private view returns (bool) {
        try AutopoolOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("AutopoolOracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to get the pending redemption shares being processed
    /// @dev Note that this function is only for locked redemption shares that are being processed in the current
    /// rebalance cycle. Does not include pending redemption shares in the future epoch that are not yet being
    /// processed.
    /// @param bt The BasketToken instance
    /// @param basketManager The BasketManager instance
    /// @return pendingRedeems The pending redemption shares being processed
    function _getPendingRedemptionSharesBeingProcessed(
        BasketToken bt,
        BasketManager basketManager
    )
        internal
        view
        returns (uint256 pendingRedeems)
    {
        if (basketManager.rebalanceStatus().status == Status.NOT_STARTED) {
            revert("No pending redemption shares are being processed");
        }
        // When rebalance has started, prepareForRebalance has run.
        // The redeem request ID that fulfillRedeem will target is nextRedeemRequestId - 2.
        uint256 currentNextRedeemRequestId = bt.nextRedeemRequestId();

        // nextRedeemRequestId is always >= 3, so currentNextRedeemRequestId - 2 is always >= 1.
        uint256 reqIdForCurrentCycleProcessing = currentNextRedeemRequestId - 2;
        BasketToken.RedeemRequestView memory redeemRequest = bt.getRedeemRequest(reqIdForCurrentCycleProcessing);

        // If this request slot is not yet fulfilled and not in fallback,
        // its shares are considered pending for the current cycle's calculations.
        if (redeemRequest.fulfilledAssets == 0 && !redeemRequest.fallbackTriggered) {
            pendingRedeems = redeemRequest.totalRedeemShares;
        } else {
            // If the request slot (nextRedeemRequestId - 2) is already settled (fulfilled or fallbacked),
            // it means that for the purpose of calculating targets for the *current* rebalance cycle,
            // there are no "pending" shares from this specific processing slot.
            // This handles the case where prepareForRebalance processed an epoch with 0 actual new redemptions,
            // did not advance nextRedeemRequestId, and thus nextRedeemRequestId - 2 points to an old, settled request.
            pendingRedeems = 0;
        }
    }
}

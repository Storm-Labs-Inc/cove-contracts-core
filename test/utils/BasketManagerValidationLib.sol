// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IPyth } from "euler-price-oracle/lib/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "euler-price-oracle/lib/pyth-sdk-solidity/PythStructs.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { CurveEMAOracle } from "euler-price-oracle/src/adapter/curve/CurveEMAOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { ChainedERC4626Oracle } from "src/oracles/ChainedERC4626Oracle.sol";
import { ERC4626Oracle } from "src/oracles/ERC4626Oracle.sol";
import { RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";
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
    /// @notice Error thrown when primary oracle is not using Pyth
    error PrimaryNotPyth(address asset);
    /// @notice Error thrown when anchor oracle is not using Chainlink
    error AnchorNotChainlink(address asset);
    /// @notice Error thrown when AnchoredOracle is given when expecting an oracle with a linear path to USD
    error OracleIsNotLinear(address asset);
    /// @notice Error thrown when an invalid oracle is given
    error InvalidOracle(address oracle);

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

        // Get all basket tokens
        address[] memory baskets = basketManager.basketTokens();

        // Iterate through each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            // Get all assets in the basket
            address[] memory assets = basketManager.basketAssets(baskets[i]);

            // Iterate through each asset
            for (uint256 j = 0; j < assets.length; j++) {
                address asset = assets[j];
                address oracle = eulerRouter.getConfiguredOracle(asset, USD);
                _updateOracleTimestamp(eulerRouter, oracle);
            }
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

    function testLib_needsRebalance(
        BasketManager basketManager,
        address[] memory baskets
    )
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
        if (totalUsdValue == 0) {
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
        address[] memory baskets
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
                    "Basket", vm.toString(i), ":", vm.toString(baskets[i]), "has assets:", vm.toString(assets.length)
                )
            );
        }
        console.log("Total basket-asset pairs:", slot.totalPairs);

        // Create arrays to store surplus and deficit information for each asset in each basket
        slot.surplusDeficits = new SurplusDeficit[](slot.totalPairs);
        slot.surplusDeficitCount = 0;

        // For each basket, calculate surplus/deficit for each asset
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            console.log("\n--- Processing basket ---", basket);

            address[] memory assets = basketManager.basketAssets(basket);
            uint64[] memory targetWeights = BasketToken(basket).getTargetWeights();

            // Get the base asset index for this basket
            slot.baseAssetIndex = basketManager.basketTokenToBaseAssetIndex(basket);
            slot.baseAsset = assets[slot.baseAssetIndex];
            console.log("Base asset:", slot.baseAsset, "index:", slot.baseAssetIndex);

            // Calculate total USD value of the basket and base asset requirements for redemptions
            slot.totalValue = 0;
            slot.usdValues = new uint256[](assets.length);

            for (uint256 j = 0; j < assets.length; j++) {
                uint256 balance = basketManager.basketBalanceOf(basket, assets[j]);
                slot.usdValues[j] = _getPrimaryOracleQuote(eulerRouter, balance, assets[j], USD);
                slot.totalValue += slot.usdValues[j];
                console.log(
                    string.concat(
                        "Asset",
                        vm.toString(j),
                        ":",
                        vm.toString(assets[j]),
                        "Balance:",
                        vm.toString(balance),
                        "USD Value:",
                        vm.toString(slot.usdValues[j])
                    )
                );
            }
            console.log("Total basket USD value:", slot.totalValue);

            // Handle pending redemptions - need to set aside base asset
            slot.pendingRedeems = BasketToken(basket).totalPendingRedemptions();
            slot.totalSupply = BasketToken(basket).totalSupply();
            slot.redemptionValue = 0;

            console.log("Pending redemptions:", slot.pendingRedeems);
            console.log("Total supply:", slot.totalSupply);

            if (slot.pendingRedeems > 0 && slot.totalSupply > 0) {
                console.log("--- Processing redemptions ---");
                // Calculate the USD value needed for redemptions
                slot.redemptionValue =
                    FixedPointMathLib.fullMulDiv(slot.totalValue, slot.pendingRedeems, slot.totalSupply);
                console.log("Redemption USD value:", slot.redemptionValue);

                // Adjust the target value for base asset to account for redemptions
                slot.baseAssetTargetValue = FixedPointMathLib.fullMulDiv(
                    slot.totalValue - slot.redemptionValue, targetWeights[slot.baseAssetIndex], 1e18
                );
                slot.baseAssetNeededForRedemption =
                    _getPrimaryOracleQuote(eulerRouter, slot.redemptionValue, USD, assets[slot.baseAssetIndex]);
                slot.baseAssetTotalTarget = slot.baseAssetNeededForRedemption
                    + _getPrimaryOracleQuote(eulerRouter, slot.baseAssetTargetValue, USD, assets[slot.baseAssetIndex]);

                console.log("Base asset target value (excl. redemptions):", slot.baseAssetTargetValue);
                console.log("Base asset needed for redemptions:", slot.baseAssetNeededForRedemption);
                console.log("Base asset total target:", slot.baseAssetTotalTarget);

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
                    console.log("Base asset SURPLUS:", slot.currentBaseAssetAmount - slot.baseAssetTotalTarget);
                } else if (slot.currentBaseAssetAmount < slot.baseAssetTotalTarget) {
                    slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                        basket: basket,
                        asset: slot.baseAsset,
                        surplus: 0,
                        deficit: slot.baseAssetTotalTarget - slot.currentBaseAssetAmount,
                        currentAmount: slot.currentBaseAssetAmount,
                        targetAmount: slot.baseAssetTotalTarget
                    });
                    console.log("Base asset DEFICIT:", slot.baseAssetTotalTarget - slot.currentBaseAssetAmount);
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
                console.log("Adjusted total USD value (excl. redemptions):", slot.totalValue);
            }

            // Calculate surplus/deficit for non-base assets
            console.log("--- Processing non-base assets ---");
            for (uint256 j = 0; j < assets.length; j++) {
                if (j != slot.baseAssetIndex) {
                    // Skip base asset as it's already handled
                    slot.targetValue = FixedPointMathLib.fullMulDiv(slot.totalValue, targetWeights[j], 1e18);
                    slot.currentValue = slot.usdValues[j];

                    console.log(
                        string.concat(
                            "Asset",
                            vm.toString(assets[j]),
                            "Target weight:",
                            vm.toString(targetWeights[j]),
                            "Target USD value:",
                            vm.toString(slot.targetValue),
                            "Current USD value:",
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
                            "Asset",
                            vm.toString(assets[j]),
                            "Current amount:",
                            vm.toString(slot.currentAmount),
                            "Target amount:",
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
                        console.log("Asset", assets[j], "SURPLUS:", slot.currentAmount - slot.targetAmount);
                    } else if (slot.currentAmount < slot.targetAmount) {
                        slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                            basket: basket,
                            asset: assets[j],
                            surplus: 0,
                            deficit: slot.targetAmount - slot.currentAmount,
                            currentAmount: slot.currentAmount,
                            targetAmount: slot.targetAmount
                        });
                        console.log("Asset", assets[j], "DEFICIT:", slot.targetAmount - slot.currentAmount);
                    } else {
                        slot.surplusDeficits[slot.surplusDeficitCount] = SurplusDeficit({
                            basket: basket,
                            asset: assets[j],
                            surplus: 0,
                            deficit: 0,
                            currentAmount: slot.currentAmount,
                            targetAmount: slot.targetAmount
                        });
                        console.log("Asset", assets[j], "BALANCED");
                    }
                    slot.surplusDeficitCount++;
                }
            }
        }

        console.log("\n=== Generating internal trades ===");
        console.log("Total surplus/deficit records:", slot.surplusDeficitCount);

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

        console.log("Potential internal trades:", slot.potentialInternalTradeCount);

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

        console.log("Generated internal trades:", slot.internalTradeCount);

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

        console.log("\n=== Generating external trades ===");

        // Count remaining surplus/deficit for external trades
        slot.externalTradeCount = 0;
        for (uint256 i = 0; i < slot.surplusDeficitCount; i++) {
            if (slot.surplusDeficits[i].surplus > 0) {
                slot.externalTradeCount++;
                console.log(
                    string.concat(
                        "Basket",
                        vm.toString(slot.surplusDeficits[i].basket),
                        "still has surplus of asset",
                        vm.toString(slot.surplusDeficits[i].asset),
                        ":",
                        vm.toString(slot.surplusDeficits[i].surplus)
                    )
                );
            }
        }

        console.log("Potential external trades:", slot.externalTradeCount);

        // Generate external trades for remaining imbalances
        slot.externalTrades = new ExternalTrade[](slot.externalTradeCount);
        slot.currentExternalTrade = 0;

        for (uint256 i = 0; i < slot.surplusDeficitCount && slot.currentExternalTrade < slot.externalTradeCount; i++) {
            if (slot.surplusDeficits[i].surplus > 0) {
                // Find a deficit asset in the same basket to trade with
                slot.deficitAsset = address(0);
                slot.deficitAmount = 0;

                for (uint256 j = 0; j < slot.surplusDeficitCount; j++) {
                    if (
                        slot.surplusDeficits[j].deficit > 0
                            && slot.surplusDeficits[i].basket == slot.surplusDeficits[j].basket
                    ) {
                        slot.deficitAsset = slot.surplusDeficits[j].asset;
                        slot.deficitAmount = slot.surplusDeficits[j].deficit;
                        console.log(
                            "Found deficit asset",
                            slot.deficitAsset,
                            "in the same basket with deficit",
                            slot.deficitAmount
                        );
                        break;
                    }
                }

                if (slot.deficitAsset != address(0)) {
                    // Calculate trade parameters
                    slot.sellAmount = slot.surplusDeficits[i].surplus;
                    slot.sellValueUSD =
                        _getPrimaryOracleQuote(eulerRouter, slot.sellAmount, slot.surplusDeficits[i].asset, USD);

                    // Apply a 0.5% slippage for min amount (99.5% of expected)
                    slot.expectedBuyAmount =
                        _getPrimaryOracleQuote(eulerRouter, slot.sellValueUSD, USD, slot.deficitAsset);
                    slot.minBuyAmount = slot.expectedBuyAmount * 995 / 1000;

                    console.log(
                        string.concat(
                            "EXTERNAL TRADE PARAMS: Sell",
                            vm.toString(slot.sellAmount),
                            "of",
                            vm.toString(slot.surplusDeficits[i].asset),
                            "USD value:",
                            vm.toString(slot.sellValueUSD),
                            "Buy min",
                            vm.toString(slot.minBuyAmount),
                            "of",
                            vm.toString(slot.deficitAsset)
                        )
                    );

                    // Create BasketTradeOwnership array with single element
                    slot.tradeOwnerships = new BasketTradeOwnership[](1);
                    slot.singleOwnership = BasketTradeOwnership({
                        basket: slot.surplusDeficits[i].basket,
                        tradeOwnership: uint96(1e18) // 100% ownership
                     });
                    slot.tradeOwnerships[0] = slot.singleOwnership;

                    // Create external trade
                    slot.externalTrades[slot.currentExternalTrade] = ExternalTrade({
                        sellToken: slot.surplusDeficits[i].asset,
                        buyToken: slot.deficitAsset,
                        sellAmount: slot.sellAmount,
                        minAmount: slot.minBuyAmount,
                        basketTradeOwnership: slot.tradeOwnerships
                    });

                    console.log(
                        string.concat(
                            "EXTERNAL TRADE",
                            vm.toString(slot.currentExternalTrade),
                            "Basket:",
                            vm.toString(slot.surplusDeficits[i].basket),
                            "Sells:",
                            vm.toString(slot.surplusDeficits[i].asset),
                            "Buys:",
                            vm.toString(slot.deficitAsset)
                        )
                    );

                    slot.currentExternalTrade++;

                    // Update surplus/deficit
                    slot.surplusDeficits[i].surplus = 0;
                }
            }
        }

        console.log("Generated external trades:", slot.currentExternalTrade);

        // Resize external trades array to actual count
        if (slot.currentExternalTrade < slot.externalTradeCount) {
            ExternalTrade[] memory rightSizedExternalTrades = new ExternalTrade[](slot.currentExternalTrade);
            for (uint256 i = 0; i < slot.currentExternalTrade; i++) {
                rightSizedExternalTrades[i] = slot.externalTrades[i];
            }
            slot.externalTrades = rightSizedExternalTrades;
            console.log("Resized external trades array from", slot.externalTradeCount, "to", slot.currentExternalTrade);
        }

        // Return the final trade arrays
        internalTradesResult = slot.internalTrades;
        externalTradesResult = slot.externalTrades;

        console.log("\n=== Trade generation summary ===");
        console.log("Internal trades:", internalTradesResult.length);
        console.log("External trades:", externalTradesResult.length);
        console.log("=== End of trade generation ===\n");

        return (internalTradesResult, externalTradesResult);
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
        } else if (_isCurveEMAOracle(oracle)) {
            // Do nothing
        } else if (_isChainedERC4626Oracle(oracle)) {
            // Do nothing
        } else {
            revert InvalidOracle(oracle);
        }
    }

    // Updates the timestamp of a Pyth oracle response to the current block timestamp
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        vm.record();
        IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        (bytes32[] memory readSlots,) = vm.accesses(PYTH);
        // Second read slot contains the timestamp in the last 32 bits
        // key   "0x28b01e5f9379f2a22698d286ce7faa0c31f6e4041ee32933d99cfe45a4a8ced5":
        // value "0x0000000000000000071021bc0000003f435df940fffffff80000000067a59cb0",
        // Where timestamp is 0x67a59cb0
        // overwrite this by using vm.store(readSlots[1], modified state)
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData =
            bytes32((uint256(vm.load(PYTH, readSlots[1])) & ~uint256(0xFFFFFFFF)) | newPublishTime);
        vm.store(PYTH, readSlots[1], modifiedStorageData);

        // Verify the storage was updated.
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        require(res.publishTime == newPublishTime, "PythOracle timestamp was not updated correctly");
    }

    // Updates the timestamp of a ChainLink oracle response to the current block timestamp
    function _updateChainLinkOracleTimeStamp(address chainlinkOracle) internal {
        address aggregator = IChainlinkAggregatorV3Interface(chainlinkOracle).aggregator();
        vm.record();
        IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        (bytes32[] memory readSlots,) = vm.accesses(aggregator);
        // The third slot of the aggregator reads contains the timestamp in the first 32 bits
        // Format: 0x67a4876b67a48757000000000000000000000000000000000f806f93b728efc0
        // Where 0x67a4876b is the timestamp
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData = bytes32(
            (uint256(vm.load(aggregator, readSlots[2])) & ~uint256(0xFFFFFFFF << 224)) | (newPublishTime << 224)
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
    function validateCrossAdapterPath(address oracleAddr) private view {
        // Get the CrossAdapter's oracles
        address oracleBaseCross = CrossAdapter(oracleAddr).oracleBaseCross();
        address oracleCrossQuote = CrossAdapter(oracleAddr).oracleCrossQuote();

        // We need to check both chain paths to ensure one uses Pyth and one uses Chainlink
        bool baseCrossPyth = _isOraclePathPyth(oracleBaseCross);
        bool baseCrossChainlink = _isOraclePathChainlink(oracleBaseCross);
        bool crossQuotePyth = _isOraclePathPyth(oracleCrossQuote);
        bool crossQuoteChainlink = _isOraclePathChainlink(oracleCrossQuote);

        // Ensure we have at least one Pyth and one Chainlink oracle in the paths
        // Valid configurations:
        // 1. BaseCross = Pyth, CrossQuote = Chainlink
        // 2. BaseCross = Chainlink, CrossQuote = Pyth
        // 3. Both have mixed paths but together they ensure Pyth and Chainlink are used
        bool hasPyth = baseCrossPyth || crossQuotePyth;
        bool hasChainlink = baseCrossChainlink || crossQuoteChainlink;

        if (!(hasPyth && hasChainlink)) {
            revert InvalidOraclePath(CrossAdapter(oracleAddr).base());
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

        // Check if it's an AnchoredOracle with Pyth
        if (_isAnchoredOracle(oracle)) {
            revert OracleIsNotLinear(oracle);
        }

        // Check if it's a CrossAdapter with Pyth
        if (_isCrossAdapter(oracle)) {
            address oracleBaseCross = CrossAdapter(oracle).oracleBaseCross();
            address oracleCrossQuote = CrossAdapter(oracle).oracleCrossQuote();
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

        // Check if it's an AnchoredOracle with Chainlink
        if (_isAnchoredOracle(oracle)) {
            revert AnchorNotChainlink(oracle);
        }

        // Check if it's a CrossAdapter with Chainlink
        if (_isCrossAdapter(oracle)) {
            address oracleBaseCross = CrossAdapter(oracle).oracleBaseCross();
            address oracleCrossQuote = CrossAdapter(oracle).oracleCrossQuote();
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

    /// @notice Helper function to check if an oracle is a CurveEMAOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a CurveEMAOracle
    function _isCurveEMAOracle(address oracle) private view returns (bool) {
        try CurveEMAOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("CurveEMAOracle"));
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
}

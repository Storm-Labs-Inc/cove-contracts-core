// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "euler-price-oracle/lib/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "euler-price-oracle/lib/pyth-sdk-solidity/PythStructs.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Constants } from "test/utils/Constants.t.sol";
import { MockTradeAdapter } from "test/utils/mocks/MockTradeAdapter.sol";

import { Deployments } from "script/Deployments.s.sol";
import { BasketTokenDeployment, OracleOptions } from "script/Deployments.s.sol";

import { AnchoredOracle } from "src/AnchoredOracle.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

struct SurplusDeficit {
    uint256 surplusUSD; // USD value of surplus
    uint256 deficitUSD; // USD value of deficit
}

contract IntegrationTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    InternalTrade[] private tempInternalTrades;
    uint256 private internalTradeCount;

    mapping(address => uint256) public totalDeficitUSD;
    mapping(address => mapping(address => SurplusDeficit)) public surplusDeficitMap;
    mapping(address => string) public assetNames;

    BasketManager public bm;
    Deployments public deployments;
    address public mockTradeAdapter;
    uint256 public bitflag;

    mapping(address => bool) private assetExists; // Mapping to track added assets

    function setUp() public override {
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);

        deployments = new Deployments();
        deployments.deploy(false);

        bm = BasketManager(deployments.getAddress("BasketManager"));

        assetNames[ETH_WETH] = "WETH";
        vm.label(ETH_WETH, "WETH");
        assetNames[ETH_SUSDE] = "SUSDE";
        vm.label(ETH_SUSDE, "SUSDE");
        assetNames[ETH_WEETH] = "weETH";
        vm.label(ETH_WEETH, "weETH");
        assetNames[ETH_EZETH] = "ezETH";
        assetNames[ETH_RSETH] = "rsETH";
        assetNames[ETH_RETH] = "rETH";

        mockTradeAdapter = address(new MockTradeAdapter());
        vm.prank(deployments.admin());
        bm.setTokenSwapAdapter(address(mockTradeAdapter));

        address[] memory basketAssets = bm.basketAssets(bm.basketTokens()[0]);
        bitflag = AssetRegistry(deployments.getAddress("AssetRegistry")).getAssetsBitFlag(basketAssets);
    }

    function test_setUp() public view {
        assertNotEq(address(bm), address(0));
        assertNotEq(deployments.getAddress("AssetRegistry"), address(0));
        assertNotEq(deployments.getAddress("StrategyRegistry"), address(0));
        assertNotEq(deployments.getAddress("EulerRouter"), address(0));
        assertNotEq(deployments.getAddress("FeeCollector"), address(0));

        assertEq(bm.numOfBasketTokens(), 1);
    }

    function testFuzz_completeRebalance_processDeposits(uint256 numUsers, uint256 entropy) public {
        numUsers = bound(numUsers, 1, 100);

        address[] memory basketTokens = bm.basketTokens();

        for (uint256 i = 0; i < numUsers; ++i) {
            address user = vm.addr(i + 1);
            uint256 amount = uint256(keccak256(abi.encodePacked(i, entropy))) % (1000 ether - 1e4) + 1e4;
            for (uint256 j = 0; j < basketTokens.length; ++j) {
                _requestDepositToBasket(user, basketTokens[j], amount);
            }
        }

        _updatePythOracleTimeStamps();
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(bm.rebalanceStatus().basketHash, keccak256(abi.encodePacked(basketTokens)));

        ExternalTrade[] memory externalTradesLocal = new ExternalTrade[](0);
        InternalTrade[] memory internalTradesLocal = new InternalTrade[](0);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTradesLocal, externalTradesLocal, basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));

        vm.warp(block.timestamp + 15 minutes);
        bm.completeRebalance(externalTradesLocal, basketTokens);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function test_calculateExternalTrades() public {
        testFuzz_completeRebalance_processDeposits(100, 100);
        vm.warp(block.timestamp + REBALANCE_COOLDOWN_SEC);

        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 5e17; // 50% ETH_WETH
        newTargetWeights[1] = 1e17; // 50% ETH_SUSDE
        newTargetWeights[2] = 1e17; // 0% ETH_WEETH
        newTargetWeights[3] = 1e17; // 0% ETH_EZETH
        newTargetWeights[4] = 1e17; // 0% ETH_RSETH
        newTargetWeights[5] = 1e17; // 0% ETH_RETH
        uint64[][] memory targetWegihts = new uint64[][](1);
        targetWegihts[0] = newTargetWeights;

        address[] memory basketTokens = new address[](1);
        basketTokens[0] = bm.basketTokens()[0];

        _updatePythOracleTimeStamps();

        ManagedWeightStrategy strategy =
            ManagedWeightStrategy(deployments.getAddress("Gauntlet V1_ManagedWeightStrategy"));
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(bitflag, newTargetWeights);

        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, targetWegihts);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens);
        _giveAssetsToSwapAdapter(externalTrades);

        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");

        vm.warp(block.timestamp + 15 minutes);
        bm.completeRebalance(externalTrades, basketTokens);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function test_calculateInternalTrades() public {
        // Create a new basket to trade into
        address[] memory newBasketAssets0 = new address[](2);
        newBasketAssets0[0] = ETH_SUSDE;
        newBasketAssets0[1] = ETH_WEETH;
        address strategyAddress = deployments.getAddress("Gauntlet V1_ManagedWeightStrategy");
        uint256 basket0Bitflag = deployments.assetsToBitFlag(newBasketAssets0);
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        uint64[] memory intitialTargetWeights0 = new uint64[](2);
        intitialTargetWeights0[0] = 1e18;
        intitialTargetWeights0[1] = 0;

        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(basket0Bitflag, intitialTargetWeights0);
        vm.stopPrank();
        vm.startPrank(deployments.admin());
        vm.label(
            bm.createNewBasket("Test Basket0", "TEST0", address(ETH_SUSDE), basket0Bitflag, strategyAddress),
            "2AssetBasket0"
        );
        vm.stopPrank();
        // Fuzzes deposits into both baskets as well as externally trade to get all assets in the base basket
        test_calculateExternalTrades();
        // testFuzz_completeRebalance_processDeposits(100, 100);
        vm.warp(block.timestamp + REBALANCE_COOLDOWN_SEC);

        uint64[] memory newTargetWeights0 = new uint64[](2);
        newTargetWeights0[0] = 0;
        newTargetWeights0[1] = 1e18; // ETH_WEETH

        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 0; // 50%
        newTargetWeights[1] = 1e18; // 100 % add need for ETH_SUSDE
        newTargetWeights[2] = 0; // 0% remove this baskets need for ETH_WEETH
        newTargetWeights[3] = 0; // 0%
        newTargetWeights[4] = 0; // 0%
        newTargetWeights[5] = 0; // 0%

        uint64[][] memory newTargetWeightsTotal = new uint64[][](2);
        newTargetWeightsTotal[0] = newTargetWeights;
        newTargetWeightsTotal[1] = newTargetWeights0;

        address[] memory basketTokens = bm.basketTokens();

        _updatePythOracleTimeStamps();

        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(basket0Bitflag, newTargetWeights0);
        strategy.setTargetWeights(bitflag, newTargetWeights);
        vm.stopPrank();

        vm.prank(deployments.rebalanceProposer());
        console.log("Proposing rebalance");
        bm.proposeRebalance(basketTokens);

        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens);
        _giveAssetsToSwapAdapter(externalTrades);

        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");

        vm.warp(block.timestamp + 15 minutes);
        bm.completeRebalance(externalTrades, basketTokens);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function _findSurplusAndDeficits(address basketToken, uint64[] memory newTargetWeights) internal {
        address[] memory basketAssets = bm.basketAssets(basketToken);
        uint256 assetCount = basketAssets.length;

        require(newTargetWeights.length == assetCount, "Mismatched weights and assets");

        // Calculate current USD values of all basket assets
        (uint256[] memory currentValuesUSD, uint256 totalValueUSD) = _getCurrentUSDValue(basketToken, basketAssets);
        // Based on the totalUSD value of the basket find the desired values of each asset base on the new target
        // weights
        uint256[] memory desiredValuesUSD = _calculateDesiredValues(totalValueUSD, newTargetWeights);
        // Find the surplus and deficits of each asset
        (uint256[] memory surplusUSD, uint256[] memory deficitUSD) =
            _calculateDeficitSurplus(currentValuesUSD, desiredValuesUSD, assetCount);
        // Update the surplusDeficitMap for each asset to keep track of the surplus and deficits across baskets
        for (uint256 i = 0; i < assetCount; ++i) {
            if (surplusUSD[i] > 0 || deficitUSD[i] > 0) {
                console.log("Surplus/Deficit found");
                console.log("Asset:", basketAssets[i]);
                console.log("Asset name: ", assetNames[basketAssets[i]]);
                console.log("Basket:", basketToken);
                console.log("Surplus USD:", surplusUSD[i]);
                console.log("basketBalanceOf :", bm.basketBalanceOf(basketToken, basketAssets[i]));
                console.log("Deficit USD:", deficitUSD[i]);
                surplusDeficitMap[basketAssets[i]][basketToken] =
                    SurplusDeficit({ surplusUSD: surplusUSD[i], deficitUSD: deficitUSD[i] });
            }
        }
    }

    function _getCurrentUSDValue(
        address basketToken,
        address[] memory basketAssets
    )
        internal
        view
        returns (uint256[] memory currentValuesUSD, uint256 totalValueUSD)
    {
        uint256 assetCount = basketAssets.length;
        currentValuesUSD = new uint256[](assetCount);
        totalValueUSD = 0;

        for (uint256 i = 0; i < assetCount; ++i) {
            uint256 balance = bm.basketBalanceOf(basketToken, basketAssets[i]);
            if (balance == 0) {
                continue;
            }
            string memory assetName = assetNames[basketAssets[i]];
            AnchoredOracle assetOracle =
                AnchoredOracle(deployments.getAddress(string(abi.encodePacked(assetName, "_AnchoredOracle"))));
            currentValuesUSD[i] = assetOracle.getQuote(balance, basketAssets[i], USD);
            console.log("basket balanceOf: ", balance);
            console.log("usdValue :", currentValuesUSD[i]);
            totalValueUSD += currentValuesUSD[i];
        }
    }

    function _calculateDesiredValues(
        uint256 totalValueUSD,
        uint64[] memory newTargetWeights
    )
        internal
        pure
        returns (uint256[] memory desiredValuesUSD)
    {
        uint256 assetCount = newTargetWeights.length;
        desiredValuesUSD = new uint256[](assetCount);
        for (uint256 i = 0; i < assetCount; ++i) {
            desiredValuesUSD[i] = (totalValueUSD * uint256(newTargetWeights[i])) / 1e18;
        }
    }

    function _calculateDeficitSurplus(
        uint256[] memory currentValuesUSD,
        uint256[] memory desiredValuesUSD,
        uint256 assetCount
    )
        internal
        pure
        returns (uint256[] memory surplusUSD, uint256[] memory deficitUSD)
    {
        surplusUSD = new uint256[](assetCount);
        deficitUSD = new uint256[](assetCount);

        for (uint256 i = 0; i < assetCount; ++i) {
            if (currentValuesUSD[i] > desiredValuesUSD[i]) {
                surplusUSD[i] = currentValuesUSD[i] - desiredValuesUSD[i];
            } else if (desiredValuesUSD[i] > currentValuesUSD[i]) {
                deficitUSD[i] = desiredValuesUSD[i] - currentValuesUSD[i];
            }
        }
    }

    function _findInternalAndExternalTrades(
        address[] memory baskets,
        uint64[][] memory newTargetWeights
    )
        internal
        returns (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades)
    {
        require(baskets.length == newTargetWeights.length, "Mismatched baskets and weights");

        // Reset the temporary storage
        delete tempInternalTrades;
        internalTradeCount = 0;

        // Populate surplus and deficits for each asset
        for (uint256 i = 0; i < baskets.length; ++i) {
            _findSurplusAndDeficits(baskets[i], newTargetWeights[i]);
        }

        // Generate internal trades
        _generateInternalTrades(baskets);
        console.log("found n internal trades: ", internalTradeCount);

        // Copy to final array
        internalTrades = new InternalTrade[](internalTradeCount);
        for (uint256 i = 0; i < internalTradeCount; i++) {
            internalTrades[i] = tempInternalTrades[i];
        }

        // Generate external trades
        ExternalTrade[] memory externalTradesTemp = new ExternalTrade[](baskets.length * 10);
        uint256 externalTradeCount = _generateExternalTrades(baskets, externalTradesTemp);
        console.log("found n external trades: ", externalTradeCount);

        // Trim external trades array
        externalTrades = _trimExternalTradesArray(externalTradesTemp, externalTradeCount);
    }

    function _generateInternalTrades(address[] memory baskets) internal {
        uint256 basketCount = baskets.length;

        for (uint256 i = 0; i < basketCount; ++i) {
            address basketFrom = baskets[i];
            address[] memory assetsFrom = bm.basketAssets(basketFrom);

            for (uint256 j = 0; j < basketCount; ++j) {
                if (i == j) continue;
                address basketTo = baskets[j];

                for (uint256 k = 0; k < assetsFrom.length; ++k) {
                    address asset = assetsFrom[k];
                    _processInternalTrade(basketFrom, basketTo, asset);
                }
            }
        }
    }

    function _processInternalTrade(address basketFrom, address basketTo, address asset) internal {
        uint256 surplusFrom = surplusDeficitMap[asset][basketFrom].surplusUSD;
        uint256 deficitTo = surplusDeficitMap[asset][basketTo].deficitUSD;

        address[] memory basketToAssets = bm.basketAssets(basketTo);
        for (uint256 i = 0; i < basketToAssets.length; i++) {
            address reciprocalAsset = basketToAssets[i];
            if (reciprocalAsset == asset) continue;

            uint256 reciprocalSurplus = surplusDeficitMap[reciprocalAsset][basketTo].surplusUSD;
            uint256 reciprocalDeficit = surplusDeficitMap[reciprocalAsset][basketFrom].deficitUSD;

            if (reciprocalSurplus > 0 && reciprocalDeficit > 0) {
                _executeInternalTrade(
                    basketFrom,
                    basketTo,
                    asset,
                    reciprocalAsset,
                    surplusFrom,
                    deficitTo,
                    reciprocalSurplus,
                    reciprocalDeficit
                );
            }
        }
    }

    function _executeInternalTrade(
        address basketFrom,
        address basketTo,
        address asset,
        address reciprocalAsset,
        uint256 surplusFrom,
        uint256 deficitTo,
        uint256 reciprocalSurplus,
        uint256 reciprocalDeficit
    )
        internal
    {
        uint256 tradeUSD = _min(_min(surplusFrom, deficitTo), _min(reciprocalSurplus, reciprocalDeficit));

        if (tradeUSD == 0) return;

        uint256 sellAmount = _valueToAmount(asset, tradeUSD);
        uint256 minAmount = tradeUSD / _getAssetPrice(reciprocalAsset) * 10 ** ERC20(reciprocalAsset).decimals();

        InternalTrade memory trade = InternalTrade({
            fromBasket: basketFrom,
            sellToken: asset,
            buyToken: reciprocalAsset,
            toBasket: basketTo,
            sellAmount: sellAmount,
            minAmount: (minAmount * 95) / 100,
            maxAmount: (minAmount * 105) / 100
        });

        console.log("Two-sided Internal Trade Found:");
        console.log("From Basket:", trade.fromBasket);
        console.log("To Basket:", trade.toBasket);
        console.log("Sell Token:", trade.sellToken);
        console.log("Buy Token:", trade.buyToken);
        console.log("Amount:", trade.sellAmount);

        tempInternalTrades.push(trade);
        internalTradeCount++;

        // Update surplus and deficit maps
        surplusDeficitMap[asset][basketFrom].surplusUSD -= tradeUSD;
        surplusDeficitMap[asset][basketTo].deficitUSD -= tradeUSD;
        surplusDeficitMap[reciprocalAsset][basketTo].surplusUSD -= tradeUSD;
        surplusDeficitMap[reciprocalAsset][basketFrom].deficitUSD -= tradeUSD;
    }

    function _generateExternalTrades(
        address[] memory baskets,
        ExternalTrade[] memory externalTradesTemp
    )
        internal
        returns (uint256 externalTradeCount)
    {
        externalTradeCount = 0;
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            address[] memory assets = bm.basketAssets(basket);
            // Process each potential sell asset
            for (uint256 i = 0; i < assets.length; i++) {
                address sellAsset = assets[i];
                uint256 surplusUSD = surplusDeficitMap[sellAsset][basket].surplusUSD;

                if (surplusUSD == 0) continue;

                externalTradeCount =
                    _processSellAsset(basket, sellAsset, surplusUSD, assets, externalTradesTemp, externalTradeCount);
            }
        }
    }

    function _processSellAsset(
        address basket,
        address sellAsset,
        uint256 surplusUSD,
        address[] memory assets,
        ExternalTrade[] memory externalTradesTemp,
        uint256 tradeCount
    )
        internal
        returns (uint256)
    {
        // Look for matching deficits
        for (uint256 i = 0; i < assets.length; i++) {
            address buyAsset = assets[i];
            if (buyAsset == sellAsset) continue;

            uint256 deficitUSD = surplusDeficitMap[buyAsset][basket].deficitUSD;
            if (deficitUSD == 0) continue;

            uint256 tradeUSD = _min(surplusUSD, deficitUSD);

            tradeCount = _processExternalTrade(sellAsset, buyAsset, tradeUSD, basket, externalTradesTemp, tradeCount);

            // Update surplus/deficit maps
            surplusDeficitMap[sellAsset][basket].surplusUSD -= tradeUSD;
            surplusDeficitMap[buyAsset][basket].deficitUSD -= tradeUSD;

            // If we've used up all surplus, exit early
            if (surplusDeficitMap[sellAsset][basket].surplusUSD == 0) break;
        }

        return tradeCount;
    }

    // Takes a known surplus asset and a known deficit asset and adds the created external trade to externalTradesTemp.
    // Updates the total surpluses.
    function _processExternalTrade(
        address sellAsset,
        address buyAsset,
        uint256 usdAmount,
        address basket,
        ExternalTrade[] memory externalTradesTemp,
        uint256 externalTradeCount
    )
        internal
        returns (uint256)
    {
        uint256 sellAmount = _valueToAmount(sellAsset, usdAmount);
        uint256 minBuyAmount = _valueToAmount(buyAsset, usdAmount);

        // Check if thers is already an instance of the propose external trade and prepare basket trade ownerships
        // BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](baskets.length);
        uint256 externalTradeIndexPlusOne = _checkForExistingExternalTrade(sellAsset, buyAsset, externalTradesTemp);

        if (externalTradeIndexPlusOne == 0) {
            BasketTradeOwnership[] memory ownership = new BasketTradeOwnership[](1);
            ownership[0] = BasketTradeOwnership({ basket: basket, tradeOwnership: 1e18 });
            ExternalTrade memory externalTrade = ExternalTrade({
                sellToken: sellAsset,
                buyToken: buyAsset,
                sellAmount: sellAmount,
                minAmount: (minBuyAmount * 95) / 100,
                basketTradeOwnership: ownership
            });
            console.log("External trade selltoken: ", externalTrade.sellToken);
            console.log("External trade buytoken: ", externalTrade.buyToken);
            console.log("External trade sellAmount: ", externalTrade.sellAmount);
            console.log("External trade minAmount: ", externalTrade.minAmount);

            externalTradesTemp[externalTradeCount++] = externalTrade;
        } else {
            _updateExistingExternalTrade(externalTradesTemp, externalTradeIndexPlusOne - 1, basket, sellAmount);
        }
        return externalTradeCount;
    }

    function _updateExistingExternalTrade(
        ExternalTrade[] memory externalTradesTemp,
        uint256 tradeIndex,
        address basket,
        uint256 sellAmount
    )
        internal
        pure
    {
        ExternalTrade memory trade = externalTradesTemp[tradeIndex];
        uint256 newSellAmount = trade.sellAmount + sellAmount;
        BasketTradeOwnership[] memory newOwnerships = new BasketTradeOwnership[](trade.basketTradeOwnership.length + 1);

        // Calculate new ownership percentages
        uint256 totalProcessed = 0;
        for (uint256 i = 0; i < trade.basketTradeOwnership.length; i++) {
            BasketTradeOwnership memory ownership = trade.basketTradeOwnership[i];
            uint256 oldOwnerShipAmount = trade.sellAmount * ownership.tradeOwnership / 1e18;
            uint256 newOwnership = oldOwnerShipAmount * 1e18 / newSellAmount;
            newOwnerships[i].basket = ownership.basket;
            newOwnerships[i].tradeOwnership = uint96(newOwnership);
            totalProcessed += newOwnership;
        }

        // The last ownership gets the remaining percentage to ensure total = 100%
        uint256 lastOwnership = 1e18 - totalProcessed;
        newOwnerships[trade.basketTradeOwnership.length] =
            BasketTradeOwnership({ basket: basket, tradeOwnership: uint96(lastOwnership) });

        // Update trade
        trade.basketTradeOwnership = newOwnerships;
        trade.sellAmount = newSellAmount;
        trade.minAmount = (newSellAmount * 95) / 100;
        externalTradesTemp[tradeIndex] = trade;
    }

    function _checkForExistingExternalTrade(
        address sellAsset,
        address buyAsset,
        ExternalTrade[] memory externalTradesTemp
    )
        internal
        returns (uint256)
    {
        for (uint256 k = 0; k < externalTradesTemp.length; ++k) {
            ExternalTrade memory trade = externalTradesTemp[k];
            if (trade.sellToken == sellAsset && trade.buyToken == buyAsset) {
                return k + 1;
            }
        }
        return 0;
    }

    function _trimExternalTradesArray(
        ExternalTrade[] memory tradesTemp,
        uint256 count
    )
        internal
        pure
        returns (ExternalTrade[] memory trades)
    {
        trades = new ExternalTrade[](count);
        for (uint256 i = 0; i < count; ++i) {
            trades[i] = tradesTemp[i];
        }
    }

    function _valueToAmount(address asset, uint256 valueUSD) internal view returns (uint256 amount) {
        uint256 assetPriceUSD = _getAssetPrice(asset);
        uint256 assetDecimals = 10 ** ERC20(asset).decimals();
        amount = (valueUSD * assetDecimals) / assetPriceUSD;
    }

    function _getAssetPrice(address asset) internal view returns (uint256 price) {
        string memory assetName = assetNames[asset];
        AnchoredOracle assetOracle =
            AnchoredOracle(deployments.getAddress(string(abi.encodePacked(assetName, "_AnchoredOracle"))));
        price = assetOracle.getQuote(10 ** ERC20(asset).decimals(), asset, USD);
    }

    function _requestDepositToBasket(
        address user,
        address basket,
        uint256 amount
    )
        internal
        returns (uint256 requestId)
    {
        address asset = BasketToken(basket).asset();
        deal(asset, user, amount);
        vm.startPrank(user);
        IERC20(asset).approve(basket, amount);
        uint256 balanceBefore = IERC20(asset).balanceOf(basket);
        requestId = BasketToken(basket).requestDeposit(amount, user, user);
        assertEq(balanceBefore + amount, IERC20(asset).balanceOf(basket));
        vm.stopPrank();
    }

    function _giveAssetsToSwapAdapter(ExternalTrade[] memory trades) internal {
        for (uint256 i = 0; i < trades.length; ++i) {
            ExternalTrade memory trade = trades[i];
            airdrop(IERC20(trade.buyToken), mockTradeAdapter, trade.minAmount);
        }
    }

    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        res.publishTime = block.timestamp;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (pythPriceFeed)), abi.encode(res));
    }

    function _updatePythOracleTimeStamps() internal {
        bytes32[] memory pythPriceFeeds = new bytes32[](4);
        pythPriceFeeds[0] = PYTH_ETH_USD_FEED;
        pythPriceFeeds[1] = PYTH_SUSE_USD_FEED;
        pythPriceFeeds[2] = PYTH_WEETH_USD_FEED;
        pythPriceFeeds[3] = PYTH_RETH_USD_FEED;

        for (uint256 i = 0; i < pythPriceFeeds.length; ++i) {
            _updatePythOracleTimeStamp(pythPriceFeeds[i]);
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "@pyth/IPyth.sol";
import { PythStructs } from "@pyth/PythStructs.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { Deployments } from "script/Deployments.s.sol";
import { DeploymentsTest } from "script/Deployments_Test.s.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

struct SurplusDeficit {
    uint256 surplusUSD; // USD value of surplus
    uint256 deficitUSD; // USD value of deficit
}

contract IntegrationTest is BaseTest {
    using FixedPointMathLib for uint256;

    InternalTrade[] private tempInternalTrades;
    uint256 private internalTradeCount;

    mapping(address => mapping(address => SurplusDeficit)) public surplusDeficitMap;
    // Mapping to track expected changes in balances for each basket and asset
    mapping(address => mapping(address => int256)) public expectedBalanceChanges;
    mapping(address => mapping(address => int256)) public expectedFeeBalanceChanges;

    BasketManager public bm;
    Deployments public deployments;
    EulerRouter public eulerRouter;
    uint256 public baseBasketBitFlag;
    bytes32[] public pythPriceFeeds;
    address[] public chainlinkOracles;
    // @dev First basket deployed should include all assets
    address[] public baseBasketAssets;
    ERC20Mock public rewardToken;

    function setUp() public override {
        forkNetworkAt("mainnet", BLOCK_NUMBER_MAINNET_FORK);
        super.setUp();
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);

        vm.pauseGasMetering();
        deployments = new DeploymentsTest();
        deployments.deploy(false);
        vm.resumeGasMetering();

        bm = BasketManager(deployments.getAddress(deployments.buildBasketManagerName()));
        eulerRouter = EulerRouter(deployments.getAddress(deployments.buildEulerRouterName()));

        pythPriceFeeds = new bytes32[](6);
        pythPriceFeeds[0] = PYTH_ETH_USD_FEED;
        pythPriceFeeds[1] = PYTH_SUSDE_USD_FEED;
        pythPriceFeeds[2] = PYTH_WEETH_USD_FEED;
        pythPriceFeeds[3] = PYTH_RETH_USD_FEED;
        pythPriceFeeds[4] = PYTH_RSETH_USD_FEED;
        pythPriceFeeds[5] = PYTH_RETH_USD_FEED;
        // TODO: add rest of asset universe

        vm.label(PYTH, "PYTH_ORACLE_CONTRACT");

        chainlinkOracles = new address[](6);
        chainlinkOracles[0] = ETH_CHAINLINK_ETH_USD_FEED;
        vm.label(ETH_CHAINLINK_ETH_USD_FEED, "ETH_CHAINLINK_ETH_USD_FEED");
        chainlinkOracles[1] = ETH_CHAINLINK_SUSDE_USD_FEED;
        vm.label(ETH_CHAINLINK_SUSDE_USD_FEED, "ETH_CHAINLINK_SUSDE_USD_FEED");
        chainlinkOracles[2] = ETH_CHAINLINK_WEETH_ETH_FEED;
        vm.label(ETH_CHAINLINK_WEETH_ETH_FEED, "ETH_CHAINLINK_WEETH_ETH_FEED");
        chainlinkOracles[3] = ETH_CHAINLINK_EZETH_ETH_FEED;
        vm.label(ETH_CHAINLINK_EZETH_ETH_FEED, "ETH_CHAINLINK_EZETH_ETH_FEED");
        chainlinkOracles[4] = ETH_CHAINLINK_RSETH_ETH_FEED;
        vm.label(ETH_CHAINLINK_RSETH_ETH_FEED, "ETH_CHAINLINK_RSETH_ETH_FEED");
        chainlinkOracles[5] = ETH_CHAINLINK_RETH_ETH_FEED;
        vm.label(ETH_CHAINLINK_RETH_ETH_FEED, "ETH_CHAINLINK_RETH_ETH_FEED");
        // TODO: add rest of asset universe

        baseBasketAssets = bm.basketAssets(bm.basketTokens()[0]);
        baseBasketBitFlag = AssetRegistry(deployments.getAddress(deployments.buildAssetRegistryName())).getAssetsBitFlag(
            baseBasketAssets
        );
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
    }

    function test_setUp() public {
        IMasterRegistry masterRegistry = IMasterRegistry(COVE_MASTER_REGISTRY);
        assertNotEq(address(bm), address(0));
        assertEq(masterRegistry.resolveNameToLatestAddress("BasketManager"), address(bm));

        address assetRegistryAddress = deployments.getAddress(deployments.buildAssetRegistryName());
        assertNotEq(assetRegistryAddress, address(0));
        assertEq(masterRegistry.resolveNameToLatestAddress("AssetRegistry"), assetRegistryAddress);

        address strategyRegistryAddress = deployments.getAddress(deployments.buildStrategyRegistryName());
        assertNotEq(strategyRegistryAddress, address(0));
        assertEq(masterRegistry.resolveNameToLatestAddress("StrategyRegistry"), strategyRegistryAddress);

        address eulerRouterAddress = deployments.getAddress(deployments.buildEulerRouterName());
        assertNotEq(eulerRouterAddress, address(0));
        assertEq(masterRegistry.resolveNameToLatestAddress("EulerRouter"), eulerRouterAddress);

        address feeCollectorAddress = deployments.getAddress(deployments.buildFeeCollectorName());
        assertNotEq(feeCollectorAddress, address(0));
        assertEq(masterRegistry.resolveNameToLatestAddress("FeeCollector"), feeCollectorAddress);
        assertEq(bm.numOfBasketTokens(), 1);
    }

    // Creates a new basket with only two assets. Deposits are randomly given to both baskets. The baset basket is
    // rebalanced to have balances of all assets. New target weights are set to give an opportunity for the two
    // baskets to trade internally. The solver is run to find these trades. An assertion is made to ensure an internal
    // trade is present in the results. The final rebalance with the internal trade is executed and the final balances
    // validated.
    function test_completeRebalance_internalTrades() public {
        // 1. A new basket is created with assets ETH_SUSDE and ETH_WEETH
        address[] memory newBasketAssets0 = new address[](2);
        newBasketAssets0[0] = ETH_SUSDE;
        newBasketAssets0[1] = ETH_WEETH;
        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        uint256 basket0Bitflag = deployments.assetsToBitFlag(newBasketAssets0);
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        uint64[] memory initialTargetWeights0 = new uint64[](2);
        initialTargetWeights0[0] = 1e18;
        initialTargetWeights0[1] = 0;
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(basket0Bitflag, initialTargetWeights0);
        vm.prank(deployments.admin());
        address basket =
            bm.createNewBasket("Test Basket0", "TEST0", address(ETH_SUSDE), basket0Bitflag, strategyAddress);
        vm.snapshotGasLastCall("BasketManager.createNewBasket");
        vm.label(basket, "2AssetBasket0");

        // 2. Two rebalances are completed, one to process deposits for both baskets. This results in both baskets
        // having 100% of their assets allocated to their respective base assets. Another rebalance is completed only
        // including the base basket. New target weights are given for this rebalance so that the base basket has a
        // balance in each of its assets.
        _baseBasket_completeRebalance_externalTrade(100, 100);
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

        // 3. New target weights are set for both baskets. The base basket's SUSDE weight is increase to 100%, the new
        // baskets WEETH weight is increased to 100%. This create an opportunity for the two baskets to internally trade
        // the two tokens between each other. Rebalance Proposer calls proposeRebalance() with the base basket and the
        // newly created two asset basket.
        uint64[] memory newTargetWeights0 = new uint64[](2);
        newTargetWeights0[0] = 0; // 0% ETH_SUSDE
        newTargetWeights0[1] = 1e18; // 100% ETH_WEETH
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 0; // 0%
        newTargetWeights[1] = 1e18; // 100 % add need for ETH_SUSDE
        newTargetWeights[2] = 0; // 0%
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
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.stopPrank();
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        // 4. Tokenswaps are proposed with at least 1 guaranteed internal trade.
        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
        assertGt(internalTrades.length, 0);
        uint256[][] memory initialBalances = new uint256[][](basketTokens.length);
        address[][] memory basketAssets = new address[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address[] memory assets = basketAssets[i] = bm.basketAssets(basketTokens[i]);
            initialBalances[i] = new uint256[](assets.length);
            for (uint256 j = 0; j < assets.length; j++) {
                initialBalances[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
            }
        }
        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);

        // 5. TokenSwapExecutor calls executeTokenSwap() with the external trades found by the solver.
        // _completeSwapAdapterTrades() is called to mock a 100% successful external trade.
        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");
        _completeSwapAdapterTrades(externalTrades);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);

        // 6. completeRebalance() is called. The rebalance is confirmed to be completed and the internal balances are
        // verified to correctly reflect the results of each trade.
        bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
        assert(_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBalances));
    }

    // Completes an initial rebalance to process deposits, assets are 100% allocated to the baskets base asset. New
    // target weights are proposed that require an external trade to reach. The call to the CoWSwap adapter is not made
    // to simulate a failed trade. The rebalance is retried the max amount of times and then the same trades are
    // proposed again. The rebalance is confirmed to complete regardless.
    function test_completeRebalance_retriesOnFailedTrade() public {
        // 1. Initial target weights are set for the base basket. 100% of assets are allocated to the base asset.
        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        uint64[] memory initialTargetWeights0 = new uint64[](2);
        initialTargetWeights0[0] = 1e18;
        initialTargetWeights0[1] = 0;

        // 2. A rebalance is completed to process deposits, assets are 100% allocated to the baskets base asset.
        _completeRebalance_processDeposits(100, 100);
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

        // 3. New target weights are set to allocate 100% of the basket's assets to the ETH_SUSDE.
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 0; // 0%
        newTargetWeights[1] = 1e18; // 100 % add need for ETH_SUSDE
        newTargetWeights[2] = 0; // 0%
        newTargetWeights[3] = 0; // 0%
        newTargetWeights[4] = 0; // 0%
        newTargetWeights[5] = 0; // 0%
        uint64[][] memory newTargetWeightsTotal = new uint64[][](1);
        newTargetWeightsTotal[0] = newTargetWeights;
        address[] memory basketTokens = bm.basketTokens();
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.stopPrank();

        //4. A rebalance is proposed.
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        //5. proposeTokenSwap() is called with valid external trades to reach the new target weights. executeTokenSwap()
        // is called to create CoWSwap orders foe each of these external trades. completeRebalance() is called before
        // these orders can be fulfilled and result in the basket entering a retry state. The basket's rebalance does
        // not complete and instead reverts back to a state where additional token swaps must be proposed. This cycle is
        // completed retryLimit amount of times.
        uint256 retryLimit = bm.retryLimit();
        for (uint256 retryNum = 0; retryNum < retryLimit; retryNum++) {
            uint256[][] memory initialBalances = new uint256[][](basketTokens.length);
            address[][] memory basketAssets_ = new address[][](basketTokens.length);
            for (uint256 i = 0; i < basketTokens.length; i++) {
                address[] memory assets = basketAssets_[i] = bm.basketAssets(basketTokens[i]);
                initialBalances[i] = new uint256[](assets.length);
                for (uint256 j = 0; j < assets.length; j++) {
                    initialBalances[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
                }
            }
            (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
                _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();
            vm.prank(deployments.tokenSwapProposer());
            bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);

            vm.prank(deployments.tokenSwapExecutor());
            bm.executeTokenSwap(externalTrades, "");

            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            // Ensure that trades fails by not calling below
            // _completeSwapAdapterTrades(externalTrades);
            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();
            bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);

            // Rebalance enters retry state
            assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
            assertEq(uint8(bm.retryCount()), retryNum + 1);
            // Compare expected and actual balances
            assert(!_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBalances));
        }

        // 6. The basket has attempted to complete its token swaps the retryLimit amount of times. The same swaps are
        // proposed again and are not fulfilled.
        uint256[][] memory initialBals = new uint256[][](basketTokens.length);
        address[][] memory basketAssets_ = new address[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address[] memory assets = basketAssets_[i] = bm.basketAssets(basketTokens[i]);
            initialBals[i] = new uint256[](assets.length);
            for (uint256 j = 0; j < assets.length; j++) {
                initialBals[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
            }
        }
        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);
        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");
        // ensure trades still fail
        // _completeSwapAdapterTrades(externalTrades);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();

        // 7. completeRebalance() is called as the rebalance should complete regardless of reaching its target weights.
        bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
        assert(!_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBals));
    }

    // Completes two rebalances, one to process deposits and one to get balances of all assets in the base basket. Then
    // the price of one of the basket's assets is altered significantly. A rebalance is then propose with the same
    // target weights as the previous epoch. The rebalance is confirmed to account for this change in price.
    function test_completeRebalance_rebalancesOnPriceChange() public {
        // 1. Two rebalances are completed, one to process deposits, one to get balances of all assets in the base
        // basket.
        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        _baseBasket_completeRebalance_externalTrade(100, 1);
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

        // 2. The same target weights are proposed as the previous epoch. Currently the basket's assets are 100% aligned
        // with these weights.
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 5e17; // 50% ETH_WETH
        newTargetWeights[1] = 1e17; // 10% ETH_SUSDE
        newTargetWeights[2] = 1e17; // 10% ETH_WEETH
        newTargetWeights[3] = 1e17; // 10% ETH_EZETH
        newTargetWeights[4] = 1e17; // 10% ETH_RSETH
        newTargetWeights[5] = 1e17; // 10% ETH_RETH
        uint64[][] memory newTargetWeightsTotal = new uint64[][](1);
        newTargetWeightsTotal[0] = newTargetWeights;
        address[] memory basketTokens = bm.basketTokens();
        _updatePythOracleTimeStamps();
        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.stopPrank();

        // 3. The price of SUSDE is altered significantly
        _alterOraclePrice(PYTH_SUSDE_USD_FEED, ETH_CHAINLINK_SUSDE_USD_FEED, 600); // reduce SUSDE price by 40%

        // 4. Propose rebalance is called to confirm that the basket manager accounts for changes in the prices of its
        // assets when evaluating a potential rebalance.
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
    }

    // solhint-disable-next-line code-complexity
    function testFuzz_completeRebalance_multipleCycles(uint256 cycles) public {
        cycles = bound(cycles, 3, 51);
        //  even # of cycles returns to base state
        if (cycles % 2 == 1) {
            cycles += 1;
        }
        // 1. A new basket is created with assets ETH_SUSDE and ETH_WEETH
        address[] memory newBasketAssets0 = new address[](2);
        newBasketAssets0[0] = ETH_SUSDE;
        newBasketAssets0[1] = ETH_WEETH;
        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        uint256 basket0Bitflag = deployments.assetsToBitFlag(newBasketAssets0);
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        uint64[] memory initialTargetWeights0 = new uint64[](2);
        initialTargetWeights0[0] = 1e18;
        initialTargetWeights0[1] = 0;
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(basket0Bitflag, initialTargetWeights0);
        vm.prank(deployments.admin());
        address newBasket =
            bm.createNewBasket("Test Basket0", "TEST0", address(ETH_SUSDE), basket0Bitflag, strategyAddress);
        vm.label(newBasket, "2AssetBasket0");

        // 2. A rebalance is completed to process deposits, assets are 100% allocated to the baskets base asset.
        _completeRebalance_processDeposits(100, 100);

        // 3. Target weights are cycled between two states. One state has the base basket with 100% of its assets in
        // base asset and the other state has the base basket with 100% of its assets in the reciprocal asset. The new
        // basket has the opposite state of the base basket. This creates an opportunity for the two baskets to
        // internally trade the two tokens between each other.
        uint64[] memory newTargetWeights0 = new uint64[](2);
        uint64[][] memory newTargetWeightsTotal = new uint64[][](1);
        address[] memory basketTokens = new address[](1);
        uint256[][] memory initialBalances = new uint256[][](basketTokens.length);
        uint256[][] memory firstCycleBalances = new uint256[][](basketTokens.length);

        basketTokens[0] = newBasket;
        for (uint256 c = 0; c < cycles; ++c) {
            vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

            if (c % 2 == 0) {
                newTargetWeights0[0] = 0; // 0% ETH_SUSDE
                newTargetWeights0[1] = 1e18; // 100% ETH_WEETH
            } else {
                // return to past state
                newTargetWeights0[0] = 1e18; // 100% ETH_SUSDE
                newTargetWeights0[1] = 0; // 0% ETH_WEETH
            }
            newTargetWeightsTotal[0] = newTargetWeights0;
            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();
            vm.startPrank(GAUNTLET_STRATEGIST);
            strategy.setTargetWeights(basket0Bitflag, newTargetWeights0);
            vm.stopPrank();
            vm.prank(deployments.rebalanceProposer());
            bm.proposeRebalance(basketTokens);

            // 4. Tokenswaps are proposed with at least 1 guaranteed internal trade.
            (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
                _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);

            address[][] memory basketAssets = new address[][](basketTokens.length);
            for (uint256 i = 0; i < basketTokens.length; i++) {
                address[] memory assets = basketAssets[i] = bm.basketAssets(basketTokens[i]);
                initialBalances[i] = new uint256[](assets.length);
                if (c == 0) {
                    firstCycleBalances[i] = new uint256[](assets.length);
                }
                for (uint256 j = 0; j < assets.length; j++) {
                    initialBalances[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
                    if (c == 0) {
                        firstCycleBalances[i][j] = initialBalances[i][j];
                    }
                }
            }
            vm.prank(deployments.tokenSwapProposer());
            bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);

            // 5. TokenSwapExecutor calls executeTokenSwap() with the external trades found by the solver.
            // _completeSwapAdapterTrades() is called to mock a 100% successful external trade.
            vm.prank(deployments.tokenSwapExecutor());
            bm.executeTokenSwap(externalTrades, "");
            _completeSwapAdapterTrades(externalTrades);

            // 6. completeRebalance() is called. The rebalance is confirmed to be completed and the internal balances
            // are
            // verified to correctly reflect the results of each trade.
            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);
            assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
            assert(_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBalances));
        }
        // 7. Compare the balances of the first and last cycle to ensure that the balances have been correctly updated
        // after each cycle.
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address[] memory assets = bm.basketAssets(basketTokens[i]);
            for (uint256 j = 0; j < assets.length; j++) {
                // if the initial balance is 0, allow for 1 dust
                if (firstCycleBalances[i][j] == 0) {
                    assertApproxEqAbs(firstCycleBalances[i][j], IERC20(assets[j]).balanceOf(address(bm)), 1);
                } else {
                    // allow for small changes due to rounding during price calculations
                    assertApproxEqRel(firstCycleBalances[i][j], IERC20(assets[j]).balanceOf(address(bm)), 1e2);
                }
            }
        }
    }

    // solhint-disable-next-line code-complexity
    function test_completeRebalance_MultipleBaskets() public {
        uint256 cycles = 5;

        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);

        // 1. A new basket is created with assets ETH_SUSDE and ETH_WEETH
        address[] memory newBasketAssets0 = new address[](2);
        newBasketAssets0[0] = ETH_SUSDE;
        newBasketAssets0[1] = ETH_WEETH;
        uint256 basket0Bitflag = deployments.assetsToBitFlag(newBasketAssets0);
        uint64[] memory initialTargetWeights0 = new uint64[](2);
        initialTargetWeights0[0] = 1e18;
        initialTargetWeights0[1] = 0;
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(basket0Bitflag, initialTargetWeights0);
        vm.prank(deployments.admin());
        address newBasket =
            bm.createNewBasket("Test Basket0", "TEST0", address(ETH_SUSDE), basket0Bitflag, strategyAddress);
        vm.label(newBasket, "2AssetBasket0");
        address[] memory basketTokens = bm.basketTokens();

        // 2. A rebalance is completed to process deposits, assets are 100% allocated to the baskets' base assets.
        _completeRebalance_processDeposits(100, cycles);

        // 3. For each cycle set different target weights
        uint64[][] memory newTargetWeightsTotal = new uint64[][](basketTokens.length);
        uint256[][] memory initialBalances = new uint256[][](basketTokens.length);
        uint256[][] memory firstCycleBalances = new uint256[][](basketTokens.length);
        address user = vm.addr(1);
        for (uint256 i; i < basketTokens.length; i++) {
            // user claims deposit requests
            BasketToken basket = BasketToken(basketTokens[i]);
            uint256 depositRequest = basket.claimableDepositRequest(basket.lastDepositRequestId(user), user);
            vm.prank(user);
            basket.deposit(depositRequest, user, user);
            address[] memory assets = bm.basketAssets(basketTokens[i]);
            firstCycleBalances[i] = new uint256[](assets.length);
            for (uint256 j = 0; j < assets.length; j++) {
                firstCycleBalances[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
            }
        }

        for (uint256 c = 0; c < cycles; ++c) {
            vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

            for (uint256 i = 0; i < basketTokens.length; ++i) {
                address[] memory assets = bm.basketAssets(basketTokens[i]);
                uint64[] memory newTargetWeights = new uint64[](assets.length);

                if (c == cycles - 1) {
                    // Final cycle: return all assets to the base asset
                    newTargetWeights[0] = 1e18; // 100% to the base asset

                    // User requests redeem
                    vm.startPrank(user);
                    BasketToken basket = BasketToken(basketTokens[i]);
                    uint256 shares = basket.balanceOf(user);
                    basket.approve(address(basket), shares);
                    basket.requestRedeem(shares, user, user);
                    vm.stopPrank();
                } else {
                    // Select two indexes deterministically based on the cycle number
                    uint256 index1 = c % assets.length;
                    uint256 index2 = (c + 1) % assets.length;
                    newTargetWeights[index1] = 3e17; // 30%
                    newTargetWeights[index2] = 7e17; // 70%
                }

                newTargetWeightsTotal[i] = newTargetWeights;
                // Update the target weights for the basket
                vm.startPrank(GAUNTLET_STRATEGIST);
                uint256 basketBitFlag =
                    AssetRegistry(deployments.getAddress(deployments.buildAssetRegistryName())).getAssetsBitFlag(assets);
                strategy.setTargetWeights(basketBitFlag, newTargetWeights);
                vm.stopPrank();
            }

            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();

            vm.prank(deployments.rebalanceProposer());
            bm.proposeRebalance(basketTokens);

            // 4. Tokenswaps are proposed
            (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
                _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
            address[][] memory basketAssets = new address[][](basketTokens.length);
            for (uint256 i = 0; i < basketTokens.length; ++i) {
                address[] memory assets = basketAssets[i] = bm.basketAssets(basketTokens[i]);
                uint256[] memory balances = new uint256[](assets.length);
                for (uint256 j = 0; j < assets.length; j++) {
                    balances[j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
                }
                initialBalances[i] = balances;
            }

            vm.prank(deployments.tokenSwapProposer());
            bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);

            // 5. TokenSwapExecutor calls executeTokenSwap() with the external trades found by the solver.
            // _completeSwapAdapterTrades() is called to mock a 100% successful external trade.
            vm.prank(deployments.tokenSwapExecutor());
            bm.executeTokenSwap(externalTrades, "");
            _completeSwapAdapterTrades(externalTrades);

            // After execute token swap

            // 6. completeRebalance() is called. The rebalance is confirmed to be completed and the internal balances
            // are verified to correctly reflect the results of each trade.
            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);
            assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
            if (c != cycles - 1) {
                assertTrue(_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBalances));
            }
        }

        // 7. Confirm that end state of the basket is the same as the start state
        for (uint256 i = 0; i < basketTokens.length; ++i) {
            address[] memory assets = bm.basketAssets(basketTokens[i]);
            uint256 baseAssetIndex = bm.basketTokenToBaseAssetIndex(basketTokens[i]);
            for (uint256 j = 0; j < assets.length; j++) {
                uint256 currentBal = bm.basketBalanceOf(basketTokens[i], assets[j]);
                // account for missing assets due to user's redeem requests
                if (j == baseAssetIndex) {
                    uint256 claimableUserWithdraw = BasketToken(basketTokens[i]).maxWithdraw(user);
                    assertApproxEqRel(
                        firstCycleBalances[i][j],
                        IERC20(assets[j]).balanceOf(address(bm)) + claimableUserWithdraw,
                        10,
                        "First cycle balance mismatch for base asset"
                    );
                }
                // allow for dust due to rounding
                else if (currentBal == 1) {
                    assertApproxEqAbs(firstCycleBalances[i][j], currentBal, 1, "First cycle balance mismatch (dust)");
                } else {
                    assertApproxEqRel(
                        firstCycleBalances[i][j],
                        IERC20(assets[j]).balanceOf(address(bm)),
                        10,
                        "First cycle balance mismatch"
                    );
                }
            }
        }
    }

    function test_proRateRedeem_entireBasket_duringRebalance() public {
        // 1. One rebalance is comppleted to process deposits, assets are 100% allocated to the baskets' base assets.
        _completeRebalance_processDeposits(100, 100);

        // 2. Alice requests a deposit
        address alice = createUser("alice");
        uint256 privateKey = uint256(keccak256(abi.encodePacked("alice")));
        console.log("Alice address: %s", alice);
        console.log("Alice private key: %s", privateKey);
        console.log(uint256(1));
        BasketToken baseBasket = BasketToken(bm.basketTokens()[0]);
        uint256 aliceDepositAmount = 1e26;
        _requestDepositToBasket(alice, address(baseBasket), aliceDepositAmount);
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

        // 3. Another rebalance is proposed with target weights aimed at getting some of each asset in the basket.
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 5e17; // 50% ETH_WETH
        newTargetWeights[1] = 1e17; // 10% ETH_SUSDE
        newTargetWeights[2] = 1e17; // 10% ETH_WEETH
        newTargetWeights[3] = 1e17; // 10% ETH_EZETH
        newTargetWeights[4] = 1e17; // 10% ETH_RSETH
        newTargetWeights[5] = 1e17; // 10% ETH_RETH
        uint64[][] memory newTargetWeightsTotal = new uint64[][](1);
        newTargetWeightsTotal[0] = newTargetWeights;

        address[] memory basketTokens = new address[](1);
        basketTokens[0] = bm.basketTokens()[0];
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = bm.basketAssets(basketTokens[0]);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        ManagedWeightStrategy strategy =
            ManagedWeightStrategy(deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1")));
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.snapshotGasLastCall("ManagedWeightStrategy.setTargetWeights");

        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        vm.snapshotGasLastCall("proposeRebalance w/ single basket");

        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);
        vm.snapshotGasLastCall("proposeTokenSwap w/ single basket (no internal trades)");

        uint256[][] memory initialBalances = new uint256[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; ++i) {
            address[] memory assets = bm.basketAssets(basketTokens[i]);
            uint256[] memory balances = new uint256[](assets.length);
            for (uint256 j = 0; j < assets.length; j++) {
                balances[j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
            }
            initialBalances[i] = balances;
        }

        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");
        vm.snapshotGasLastCall("executeTokenSwap");

        _completeSwapAdapterTrades(externalTrades);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);

        bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);
        vm.snapshotGasLastCall("completeRebalance w/ single basket");
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
        assert(_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBalances));

        // 4. Alice claims her shares then executes a proRataRedeem, immediately trading her basket token shares for
        // each asset in the basket.
        vm.startPrank(alice);
        baseBasket.deposit(aliceDepositAmount, alice, alice);
        vm.snapshotGasLastCall("BasketToken.deposit");
        baseBasket.proRataRedeem(baseBasket.balanceOf(alice), alice, alice);
        vm.snapshotGasLastCall("BasketToken.proRataRedeem");
        vm.stopPrank();

        // After alice claims shares

        // 5. The basket then attempts to rebalance once more with the same target weights as last rebalance
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        assert(uint8(bm.rebalanceStatus().status) == uint8(Status.REBALANCE_PROPOSED));
    }

    function test_fallbackRedeem() public {
        // 1. Initial target weights are set for the base basket. 100% of assets are allocated to the base asset.
        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        uint64[] memory initialTargetWeights0 = new uint64[](2);
        initialTargetWeights0[0] = 1e18;
        initialTargetWeights0[1] = 0;

        // 2. A rebalance is completed to process deposits, assets are 100% allocated to the baskets base asset.
        _completeRebalance_processDeposits(100, 100);

        // 3. User claims their deposit request after successful rebalance
        address user = vm.addr(1);
        BasketToken basket = BasketToken(bm.basketTokens()[0]);
        uint256 depositRequest = basket.claimableDepositRequest(basket.lastDepositRequestId(user), user);
        vm.startPrank(user);
        uint256 shares = basket.deposit(depositRequest, user, user);
        basket.approve(address(basket), shares);
        console.log("basket: ", address(basket));
        uint256 redeemRequestId = basket.requestRedeem(shares, user, user);
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

        // 4. New target weights are set to allocate 100% of the basket's assets to the ETH_SUSDE.
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 0; // 0%
        newTargetWeights[1] = 1e18; // 100 % add need for ETH_SUSDE
        newTargetWeights[2] = 0; // 0%
        newTargetWeights[3] = 0; // 0%
        newTargetWeights[4] = 0; // 0%
        newTargetWeights[5] = 0; // 0%
        uint64[][] memory newTargetWeightsTotal = new uint64[][](1);
        newTargetWeightsTotal[0] = newTargetWeights;
        address[] memory basketTokens = bm.basketTokens();
        address[][] memory basketAssets = _getBasketAssets(basketTokens);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.stopPrank();

        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);

        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");

        _completeSwapAdapterTrades(externalTrades);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);

        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);

        // set new weights to be 100% in base basket
        newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 1e18; // 100%
        newTargetWeights[1] = 0; // 0 %
        newTargetWeights[2] = 0; // 0%
        newTargetWeights[3] = 0; // 0%
        newTargetWeights[4] = 0; // 0%
        newTargetWeights[5] = 0; // 0%
        newTargetWeightsTotal[0] = newTargetWeights;
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.stopPrank();

        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        (internalTrades, externalTrades) = _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);

        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");

        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        // do not complete trades, failed rebalance triggers fallback
        // _completeSwapAdapterTrades(externalTrades);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets);
        assert(basket.fallbackRedeemTriggered(redeemRequestId) == true);

        uint256 sharesBefore = basket.balanceOf(user);
        vm.prank(user);
        basket.claimFallbackShares(user, user);
        assert(basket.balanceOf(user) == sharesBefore + shares);
        // After redeem request
    }

    function test_farmingPlugin_ExternalRewards() public {
        // setup farming plugin
        rewardToken = new ERC20Mock();
        uint256 rewardAmount = 100e18;
        uint256 rewardPeriod = 1 weeks;
        BasketToken basketToken = BasketToken(bm.basketTokens()[0]);
        FarmingPlugin farmingPlugin = new FarmingPlugin(basketToken, rewardToken, COVE_OPS_MULTISIG);
        rewardToken.mint(COVE_OPS_MULTISIG, rewardAmount);

        // Start rewards
        vm.startPrank(COVE_OPS_MULTISIG);
        rewardToken.approve(address(farmingPlugin), rewardAmount);
        farmingPlugin.setDistributor(COVE_OPS_MULTISIG);
        farmingPlugin.startFarming(rewardAmount, rewardPeriod);
        vm.stopPrank();

        // Add farming plugin for first use
        address user = vm.addr(1);
        vm.prank(user);
        basketToken.addPlugin(address(farmingPlugin));
        //  A rebalance is completed to process deposits, assets are 100% allocated to the baskets base asset.
        _completeRebalance_processDeposits(100, 100);

        uint256 depositRequest = basketToken.claimableDepositRequest(basketToken.lastDepositRequestId(user), user);
        vm.prank(user);
        basketToken.deposit(depositRequest, user, user);

        vm.warp(vm.getBlockTimestamp() + rewardPeriod / 2);
        // state has claimable and currently accruing rewards

        vm.warp(vm.getBlockTimestamp() + farmingPlugin.farmInfo().finished);
    }

    function testFuzz_completeRebalance_harvestsManagementFee(uint16 fee) public {
        fee = uint16(bound(fee, 10, MAX_MANAGEMENT_FEE));
        address feeCollectorAddress = deployments.getAddress(deployments.buildFeeCollectorName());
        address strategyAddress = deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1"));
        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddress);
        uint64[] memory initialTargetWeights0 = new uint64[](2);
        initialTargetWeights0[0] = 1e18;
        initialTargetWeights0[1] = 0;

        // 2. A rebalance is completed to process deposits, assets are 100% allocated to the baskets base asset.
        _completeRebalance_processDeposits(100, 100);
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);
        // Set managementFee
        address[] memory basketTokens = bm.basketTokens();
        BasketToken basketToken = BasketToken(basketTokens[0]);
        vm.prank(COVE_OPS_MULTISIG);
        bm.setManagementFee(address(basketToken), fee);

        // 3. New target weights are set to allocate 100% of the basket's assets to the ETH_SUSDE.
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 0; // 0%
        newTargetWeights[1] = 1e18; // 100 % add need for ETH_SUSDE
        newTargetWeights[2] = 0; // 0%
        newTargetWeights[3] = 0; // 0%
        newTargetWeights[4] = 0; // 0%
        newTargetWeights[5] = 0; // 0%
        uint64[][] memory newTargetWeightsTotal = new uint64[][](1);
        newTargetWeightsTotal[0] = newTargetWeights;
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.startPrank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);
        vm.stopPrank();

        //4. A rebalance is proposed.
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        // Fees are harvested once during BasketToken.prepareForRebalance() call with basket manager's proposeRebalance
        // process
        uint256 managementFeeHarvestedTimestamp = basketToken.lastManagementFeeHarvestTimestamp();
        assertEq(managementFeeHarvestedTimestamp, vm.getBlockTimestamp());
        uint256 feeCollectorBalanceBefore = basketToken.balanceOf(feeCollectorAddress);

        //5. proposeTokenSwap() is called with valid external trades to reach the new target weights. executeTokenSwap()
        // is called to create CoWSwap orders foe each of these external trades. completeRebalance() is called before
        // these orders can be fulfilled and result in the basket entering a retry state. The basket's rebalance does
        // not complete and instead reverts back to a state where additional token swaps must be proposed. This cycle is
        // completed retryLimit amount of times.
        uint256 retryLimit = bm.retryLimit();
        for (uint256 retryNum = 0; retryNum < retryLimit; retryNum++) {
            uint256[][] memory initialBalances = new uint256[][](basketTokens.length);
            address[][] memory basketAssets_ = new address[][](basketTokens.length);
            for (uint256 i = 0; i < basketTokens.length; i++) {
                address[] memory assets = basketAssets_[i] = bm.basketAssets(basketTokens[i]);
                initialBalances[i] = new uint256[](assets.length);
                for (uint256 j = 0; j < assets.length; j++) {
                    initialBalances[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
                }
            }
            (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
                _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();
            vm.prank(deployments.tokenSwapProposer());
            bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);

            vm.prank(deployments.tokenSwapExecutor());
            bm.executeTokenSwap(externalTrades, "");

            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            // Ensure that trades fails by not calling below
            // _completeSwapAdapterTrades(externalTrades);
            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();
            bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);

            // Rebalance enters retry state
            assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
            assertEq(uint8(bm.retryCount()), retryNum + 1);
            // Compare expected and actual balances
            assert(!_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBalances));
        }

        // 6. The basket has attempted to complete its token swaps the retryLimit amount of times. The same swaps are
        // proposed again and are not fulfilled.
        uint256[][] memory initialBals = new uint256[][](basketTokens.length);
        address[][] memory basketAssets_ = new address[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address[] memory assets = basketAssets_[i] = bm.basketAssets(basketTokens[i]);
            initialBals[i] = new uint256[](assets.length);
            for (uint256 j = 0; j < assets.length; j++) {
                initialBals[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
            }
        }
        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, newTargetWeightsTotal);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);
        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");
        // ensure trades still fail
        // _completeSwapAdapterTrades(externalTrades);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        _updatePythOracleTimeStamps();
        _updateChainLinkOraclesTimeStamp();
        // The fee should not have been harvested since the initial proposeRebalance
        assertEq(basketToken.lastManagementFeeHarvestTimestamp(), managementFeeHarvestedTimestamp);
        // cache total supply for management fee calculation
        uint256 totalSupply = basketToken.totalSupply() - basketToken.balanceOf(feeCollectorAddress);

        // 7. completeRebalance() is called as the rebalance should complete regardless of reaching its target weights.
        bm.completeRebalance(externalTrades, basketTokens, newTargetWeightsTotal, basketAssets_);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
        assert(!_validateTradeResults(internalTrades, externalTrades, basketTokens, initialBals));
        // The fee should have been harvested since the rebalance has now completed
        assertEq(basketToken.lastManagementFeeHarvestTimestamp(), vm.getBlockTimestamp());
        // Ensure the correct fee was given
        uint256 feeCollectorBalanceAfter = basketToken.balanceOf(feeCollectorAddress);
        uint256 expectedFee = FixedPointMathLib.fullMulDiv(
            totalSupply,
            fee * (vm.getBlockTimestamp() - managementFeeHarvestedTimestamp),
            ((MANAGEMENT_FEE_DECIMALS - fee) * uint256(365 days))
        );
        assertEq(feeCollectorBalanceAfter, feeCollectorBalanceBefore + expectedFee);
    }

    function testFuzz_setManagementFee_collectsAccruedFee(uint16 fee) public {
        fee = uint16(bound(fee, 10, MAX_MANAGEMENT_FEE));
        address feeCollectorAddress = deployments.getAddress(deployments.buildFeeCollectorName());
        BasketToken basketToken = BasketToken(bm.basketTokens()[0]);
        _completeRebalance_processDeposits(100, 100);
        vm.prank(COVE_OPS_MULTISIG);
        bm.setManagementFee(address(basketToken), fee);
        uint256 managementFeeHarvestedTimestamp = basketToken.lastManagementFeeHarvestTimestamp();
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        assertEq(basketToken.balanceOf(feeCollectorAddress), 0);
        vm.prank(COVE_OPS_MULTISIG);
        bm.setManagementFee(address(basketToken), 0);
        // Ensure the correct fee was given
        uint256 feeCollectorBalanceAfter = basketToken.balanceOf(feeCollectorAddress);
        uint256 expectedFee = FixedPointMathLib.fullMulDiv(
            basketToken.totalSupply() - feeCollectorBalanceAfter,
            fee * (vm.getBlockTimestamp() - managementFeeHarvestedTimestamp),
            ((MANAGEMENT_FEE_DECIMALS - fee) * uint256(365 days))
        );
        assertEq(feeCollectorBalanceAfter, expectedFee);
    }

    /// INTERNAL HELPER FUNCTIONS

    // Requests and processes deposits into every basket
    function _completeRebalance_processDeposits(uint256 numUsers, uint256 entropy) internal {
        numUsers = bound(numUsers, 1, 100);

        address[] memory basketTokens = bm.basketTokens();

        for (uint256 i = 0; i < numUsers; ++i) {
            address user = vm.addr(i + 1);
            uint256 amount = uint256(keccak256(abi.encodePacked(i, entropy))) % (100_000 ether) + 1e22;
            for (uint256 j = 0; j < basketTokens.length; ++j) {
                _requestDepositToBasket(user, basketTokens[j], amount);
            }
        }

        uint64[][] memory targetWeights = new uint64[][](basketTokens.length);
        address[][] memory basketAssets = new address[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; i++) {
            targetWeights[i] = BasketToken(basketTokens[i]).getTargetWeights();
            basketAssets[i] = bm.basketAssets(basketTokens[i]);
        }

        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(bm.rebalanceStatus().basketHash, keccak256(abi.encode(basketTokens, targetWeights, basketAssets)));

        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        bm.completeRebalance(new ExternalTrade[](0), basketTokens, targetWeights, basketAssets);

        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    // Validates that basketBalanceOf is correctly updated with results of trading, returns true if balances are
    // correctly updated
    // solhint-disable-next-line code-complexity
    function _validateTradeResults(
        InternalTrade[] memory internalTrades,
        ExternalTrade[] memory externalTrades,
        address[] memory basketTokens,
        uint256[][] memory initialBalances
    )
        internal
        returns (bool)
    {
        uint256[][] memory currentBalances = new uint256[][](basketTokens.length);
        // Reset the expected balance changes mapping and capture current balances
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address[] memory assets = bm.basketAssets(basketTokens[i]);
            currentBalances[i] = new uint256[](assets.length);
            for (uint256 j = 0; j < assets.length; j++) {
                expectedBalanceChanges[basketTokens[i]][assets[j]] = 0;
                expectedFeeBalanceChanges[basketTokens[i]][assets[j]] = 0;
                currentBalances[i][j] = bm.basketBalanceOf(basketTokens[i], assets[j]);
            }
        }

        uint256 swapFee = bm.swapFee();
        // Process internal trades
        for (uint256 i = 0; i < internalTrades.length; i++) {
            InternalTrade memory trade = internalTrades[i];
            uint256 swapFeeAmount = trade.sellAmount.fullMulDiv(swapFee, 2e4);
            uint256 netSellAmount = trade.sellAmount - swapFeeAmount;
            uint256 usdBuyAmount = eulerRouter.getQuote(trade.sellAmount, trade.sellToken, USD);
            uint256 buyAmount = eulerRouter.getQuote(usdBuyAmount, USD, trade.buyToken);
            uint256 netBuyAmount = buyAmount - buyAmount.fullMulDiv(swapFee, 2e4);
            // Decrease the balance of the sell token in the fromBasket
            expectedBalanceChanges[trade.fromBasket][trade.sellToken] -= int256(trade.sellAmount);
            expectedBalanceChanges[trade.fromBasket][trade.buyToken] += int256(netBuyAmount);
            // Increase the balance of the buy token in the toBasket
            expectedBalanceChanges[trade.toBasket][trade.buyToken] -= int256(buyAmount);
            expectedBalanceChanges[trade.toBasket][trade.sellToken] += int256(netSellAmount);
        }

        // Process external trades
        for (uint256 i = 0; i < externalTrades.length; i++) {
            ExternalTrade memory trade = externalTrades[i];
            uint256 usdBuyAmount = eulerRouter.getQuote(trade.sellAmount, trade.sellToken, USD);
            uint256 buyAmount = eulerRouter.getQuote(usdBuyAmount, USD, trade.buyToken);
            for (uint256 j = 0; j < trade.basketTradeOwnership.length; j++) {
                BasketTradeOwnership memory ownership = trade.basketTradeOwnership[j];
                // Calculate the portion of the trade for this basket
                uint256 basketSellAmount = trade.sellAmount.fullMulDiv(ownership.tradeOwnership, 1e18);
                uint256 basketBuyAmount = buyAmount.fullMulDiv(ownership.tradeOwnership, 1e18);
                // Decrease the balance of the sell token in the basket
                expectedBalanceChanges[ownership.basket][trade.sellToken] -= int256(basketSellAmount);
                // Increase the balance of the buy token in the basket
                expectedBalanceChanges[ownership.basket][trade.buyToken] += int256(basketBuyAmount);
            }
        }

        // Compare expected changes with actual changes
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address[] memory assets = bm.basketAssets(basketTokens[i]);
            for (uint256 j = 0; j < assets.length; j++) {
                int256 expectedChange = expectedBalanceChanges[basketTokens[i]][assets[j]];
                int256 actualChange = int256(currentBalances[i][j]) - int256(initialBalances[i][j]);
                if (actualChange != expectedChange) {
                    console.log("expectedChange does not match actual change");
                    console.log("basket: ", basketTokens[i]);
                    console.log("asset: ", assets[j]);
                    console.log("actualChange: ", actualChange);
                    console.log("expectedChange: ", expectedChange);
                    return false;
                }
            }
        }
        return true; // All checks passed
    }

    // Processes deposits for all baskets, rebalances the base basket to include all assets.
    // For any new baskets created this will process their deposits if target weights are set.
    function _baseBasket_completeRebalance_externalTrade(uint256 numUsers, uint256 entropy) internal {
        _completeRebalance_processDeposits(numUsers, entropy);
        vm.warp(vm.getBlockTimestamp() + REBALANCE_COOLDOWN_SEC);

        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 5e17; // 50% ETH_WETH
        newTargetWeights[1] = 1e17; // 50% ETH_SUSDE
        newTargetWeights[2] = 1e17; // 0% ETH_WEETH
        newTargetWeights[3] = 1e17; // 0% ETH_EZETH
        newTargetWeights[4] = 1e17; // 0% ETH_RSETH
        newTargetWeights[5] = 1e17; // 0% ETH_RETH
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = newTargetWeights;

        address[] memory basketTokens = new address[](1);
        basketTokens[0] = bm.basketTokens()[0];

        _updatePythOracleTimeStamps();

        ManagedWeightStrategy strategy =
            ManagedWeightStrategy(deployments.getAddress(deployments.buildManagedWeightStrategyName("Gauntlet V1")));
        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(baseBasketBitFlag, newTargetWeights);

        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = bm.basketAssets(basketTokens[0]);

        (InternalTrade[] memory internalTrades, ExternalTrade[] memory externalTrades) =
            _findInternalAndExternalTrades(basketTokens, targetWeights);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens, targetWeights, basketAssets);

        vm.prank(deployments.tokenSwapExecutor());
        bm.executeTokenSwap(externalTrades, "");
        _completeSwapAdapterTrades(externalTrades);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);

        bm.completeRebalance(externalTrades, basketTokens, targetWeights, basketAssets);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    /// SOLVER FUNCTIONS

    // The solver's objective is to identify a series of internal and external trades that will realign the portfolio
    // with the newly specified target allocations. This is achieved by finding the surplus or deficit in USD value
    // for each asset within the baskets relative to their updated target allocations. Subsequently, the solver
    // creates a combination of internal and external trades to rectify these imbalances and achieve the desired
    // asset distribution.
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

    // Populates the surplusDeficitMap with the surplus and deficits of each asset in a basket compared to its current
    // target weights
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
                surplusDeficitMap[basketAssets[i]][basketToken] =
                    SurplusDeficit({ surplusUSD: surplusUSD[i], deficitUSD: deficitUSD[i] });
            }
        }
    }

    // Queries the current USD value of all basket assets and returns each assets value and the total value
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
            currentValuesUSD[i] = eulerRouter.getQuote(balance, basketAssets[i], USD);
            totalValueUSD += currentValuesUSD[i];
        }
    }

    // Given a total value and target weights, calculates the desired new target weight of each asset
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
            desiredValuesUSD[i] = totalValueUSD.fullMulDiv(uint256(newTargetWeights[i]), 1e18);
        }
    }

    // Given the current and desired values of each asset, calculates the surplus and deficits of each asset
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

    /// INTERNAL TRADE FUNCTIONS

    // Attempts to find internal trades between all baskets
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

    // Finds a matching surplus and deficit in two baskets and executes an internal trade between them
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

    // Creates an internal trade and updates the surplus and deficit maps
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
        uint256 tradeUSD = (surplusFrom.min(deficitTo)).min(reciprocalSurplus.min(reciprocalDeficit));

        if (tradeUSD == 0) return;

        uint256 sellAmount = _valueToAmount(asset, tradeUSD);
        if (sellAmount == 0) return;
        uint256 minAmount =
            tradeUSD.fullMulDiv(10 ** ERC20(reciprocalAsset).decimals(), _getAssetPrice(reciprocalAsset));
        if (minAmount == 0) return;

        InternalTrade memory trade = InternalTrade({
            fromBasket: basketFrom,
            sellToken: asset,
            buyToken: reciprocalAsset,
            toBasket: basketTo,
            sellAmount: sellAmount,
            minAmount: minAmount.fullMulDiv(95, 100),
            maxAmount: minAmount.fullMulDiv(105, 100)
        });

        tempInternalTrades.push(trade);
        internalTradeCount++;

        // Update surplus and deficit maps
        surplusDeficitMap[asset][basketFrom].surplusUSD -= tradeUSD;
        surplusDeficitMap[asset][basketTo].deficitUSD -= tradeUSD;
        surplusDeficitMap[reciprocalAsset][basketTo].surplusUSD -= tradeUSD;
        surplusDeficitMap[reciprocalAsset][basketFrom].deficitUSD -= tradeUSD;
    }

    /// EXTERNAL TRADE FUNCTIONS

    // Generates external trades between all baskets with remaining surplus/deficits
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
            for (uint256 j = 0; j < assets.length; j++) {
                address sellAsset = assets[j];

                if (surplusDeficitMap[sellAsset][basket].surplusUSD == 0) continue;

                externalTradeCount =
                    _processSellAsset(basket, sellAsset, assets, externalTradesTemp, externalTradeCount);
            }
        }
    }

    // Takes a sell asset and looks for matching deficits in other baskets. If found, processes the external trade and
    // updates the surplus/deficit maps.
    function _processSellAsset(
        address basket,
        address sellAsset,
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

            // Recalculate surplusUSD to ensure it reflects the current state
            uint256 surplusUSD = surplusDeficitMap[sellAsset][basket].surplusUSD;

            uint256 deficitUSD = surplusDeficitMap[buyAsset][basket].deficitUSD;
            if (deficitUSD == 0) continue;

            uint256 tradeUSD = surplusUSD.min(deficitUSD);
            if (tradeUSD == 0) continue;

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
        if (sellAmount == 0) return externalTradeCount;
        uint256 minBuyAmount = _valueToAmount(buyAsset, usdAmount);

        // Check if thers is already an instance of the propose external trade and prepare basket trade ownerships
        uint256 externalTradeIndexPlusOne = _checkForExistingExternalTrade(sellAsset, buyAsset, externalTradesTemp);

        if (externalTradeIndexPlusOne == 0) {
            BasketTradeOwnership[] memory ownership = new BasketTradeOwnership[](1);
            ownership[0] = BasketTradeOwnership({ basket: basket, tradeOwnership: 1e18 });
            ExternalTrade memory externalTrade = ExternalTrade({
                sellToken: sellAsset,
                buyToken: buyAsset,
                sellAmount: sellAmount,
                minAmount: minBuyAmount.fullMulDiv(95, 100),
                basketTradeOwnership: ownership
            });

            externalTradesTemp[externalTradeCount++] = externalTrade;
        } else {
            _updateExistingExternalTrade(externalTradesTemp, externalTradeIndexPlusOne - 1, basket, sellAmount);
        }
        return externalTradeCount;
    }

    // Updates the amount and basket trade ownerships of an existing external trade
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
            uint256 oldOwnerShipAmount = trade.sellAmount.fullMulDiv(ownership.tradeOwnership, 1e18);
            uint256 newOwnership = oldOwnerShipAmount.fullMulDiv(1e18, newSellAmount);
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
        trade.minAmount = newSellAmount.fullMulDiv(95, 100);
        externalTradesTemp[tradeIndex] = trade;
    }

    // Checks if an external trade already exists in the externalTradesTemp array
    function _checkForExistingExternalTrade(
        address sellAsset,
        address buyAsset,
        ExternalTrade[] memory externalTradesTemp
    )
        internal
        pure
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

    // Trims the external trades array to the correct size
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

    // Converts a USD value to an amount of an asset
    function _valueToAmount(address asset, uint256 valueUSD) internal returns (uint256 amount) {
        uint256 assetPriceUSD = _getAssetPrice(asset);
        uint256 assetDecimals = 10 ** ERC20(asset).decimals();
        amount = valueUSD.fullMulDiv(assetDecimals, assetPriceUSD);
    }

    // Gets the price of an asset in USD
    function _getAssetPrice(address asset) internal returns (uint256 price) {
        eulerRouter = EulerRouter(deployments.getAddress(deployments.buildEulerRouterName()));
        price = eulerRouter.getQuote(10 ** ERC20(asset).decimals(), asset, USD);
    }

    // Gets the assets in a basket
    function _getBasketAssets(address[] memory baskets) internal returns (address[][] memory basketAssets) {
        basketAssets = new address[][](baskets.length);
        for (uint256 i = 0; i < baskets.length; i++) {
            basketAssets[i] = bm.basketAssets(baskets[i]);
        }
    }

    /// GENERIC HELPER FUNCTIONS

    // Requests a deposit to a basket and returns the requestID
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
        vm.snapshotGasLastCall("BasketToken.requestDeposit");
        assertEq(balanceBefore + amount, IERC20(asset).balanceOf(basket));
        vm.stopPrank();
    }

    // Airdrops the tokens involved in an external trade to the mockTradeAdapter to simulate cowswap completing a trade
    // order.
    function _completeSwapAdapterTrades(ExternalTrade[] memory trades) internal {
        uint32 validTo = uint32(vm.getBlockTimestamp() + 60 minutes);
        for (uint256 i = 0; i < trades.length; ++i) {
            ExternalTrade memory trade = trades[i];
            bytes32 salt =
                keccak256(abi.encodePacked(trade.sellToken, trade.buyToken, trade.sellAmount, trade.minAmount, validTo));
            address swapContract = _predictDeterministicAddress(salt, address(bm));
            takeAway(IERC20(trade.sellToken), swapContract, trade.sellAmount);
            uint256 usdBuyAmount = eulerRouter.getQuote(trade.sellAmount, trade.sellToken, USD);
            uint256 buyAmount = eulerRouter.getQuote(usdBuyAmount, USD, trade.buyToken);

            if (trade.buyToken == ETH_WETH) {
                airdrop(IERC20(trade.buyToken), swapContract, buyAmount, false);
            } else {
                airdrop(IERC20(trade.buyToken), swapContract, buyAmount);
            }
        }
    }

    // Updates the timestamps of all ChainLink oracles
    function _updateChainLinkOraclesTimeStamp() internal {
        for (uint256 i = 0; i < chainlinkOracles.length; ++i) {
            _updateChainLinkOracleTimeStamp(chainlinkOracles[i]);
        }
    }

    // Updates the timestamps of all Pyth oracles
    function _updatePythOracleTimeStamps() internal {
        for (uint256 i = 0; i < pythPriceFeeds.length; ++i) {
            _updatePythOracleTimeStamp(pythPriceFeeds[i]);
        }
    }

    // Reduces the price of a Pyth oracle by a percentage
    function _alterOraclePrice(bytes32 pythPriceFeed, address chainlinkPriceFeed, uint256 alterPercent) internal {
        if (alterPercent == 1000) {
            // clear previous mocked price change calls
            vm.clearMockedCalls();
            _updatePythOracleTimeStamps();
            _updateChainLinkOraclesTimeStamp();
        }
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        res.price = int64(uint64(FixedPointMathLib.fullMulDiv(uint256(int256(res.price)), alterPercent, 1000)));
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (pythPriceFeed)), abi.encode(res));

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            IChainlinkAggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
        answer = int256(FixedPointMathLib.fullMulDiv(uint256(answer), alterPercent, 1000));
        vm.mockCall(
            chainlinkPriceFeed,
            abi.encodeWithSelector(IChainlinkAggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
    }
}
// slither-disable-end cyclomatic-complexity

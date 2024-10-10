// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { console } from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPyth } from "euler-price-oracle/lib/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "euler-price-oracle/lib/pyth-sdk-solidity/PythStructs.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { Status } from "src/types/BasketManagerStorage.sol";

import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { DeployUtils } from "utils/DeployUtils.sol";

contract IntegrationTest is BaseTest, DeployUtils {
    using FixedPointMathLib for uint256;

    mapping(string => address) public contracts;
    mapping(address => mapping(address => uint256)) public basketUserPendingDeposits;
    mapping(address => mapping(address => uint256)) public basketUserPendingRedeems;
    mapping(address => mapping(address => uint256)) public basketUserRequestId;
    BasketManager public bm;

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        vm.startPrank(COVE_DEPLOYER_ADDRESS);

        // USERS
        users["alice"] = createUser("alice");
        users["admin"] = COVE_COMMUNITY_MULTISIG;
        users["treasury"] = COVE_OPS_MULTISIG;
        users["pauser"] = COVE_OPS_MULTISIG;
        users["manager"] = COVE_OPS_MULTISIG;
        users["timelock"] = COVE_OPS_MULTISIG;
        users["rebalancer"] = COVE_OPS_MULTISIG;

        // REGISTRIES
        contracts["assetRegistry"] = address(new AssetRegistry(users["admin"]));
        contracts["strategyRegistry"] = address(new StrategyRegistry(users["admin"]));

        // BASKET MANAGER
        contracts["basketTokenImplementation"] = address(new BasketToken());
        contracts["eulerRouter"] = address(new EulerRouter(users["admin"]));
        bytes32 feeCollectorSalt = keccak256(abi.encodePacked("FeeCollector"));
        contracts["basketManager"] = _deployBasketManager(
            feeCollectorSalt,
            contracts["basketTokenImplementation"],
            contracts["eulerRouter"],
            contracts["strategyRegistry"],
            contracts["assetRegistry"],
            users["admin"],
            users["pauser"]
        );
        bm = BasketManager(contracts["basketManager"]);
        vm.label(contracts["basketManager"], "basketManager");
        contracts["feeCollector"] =
            _deployFeeCollector(feeCollectorSalt, users["admin"], contracts["basketManager"], users["treasury"]);
        vm.label(contracts["feeCollector"], "feeCollector");
        vm.stopPrank();
        vm.startPrank(users["admin"]);
        bm.grantRole(MANAGER_ROLE, users["manager"]);
        bm.grantRole(REBALANCER_ROLE, users["rebalancer"]);
        bm.grantRole(TIMELOCK_ROLE, users["timelock"]);
        vm.stopPrank();
    }

    function testFuzz_singleDepositor_completeRebalance(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, type(uint256).max);
        address admin = users["admin"];
        address alice = users["alice"];
        address[] memory assets = new address[](2);
        assets[0] = WETH;
        assets[1] = USD;
        string memory name = "WETH/USD";
        uint256 maxDivergence = 0.5e18;
        uint256 depositAmount = 1000e18;
        uint8[] memory assetIndexes = new uint8[](2);
        assetIndexes[0] = 0;
        assetIndexes[1] = 1;
        uint64[] memory weights = new uint64[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;
        vm.startPrank(admin);
        address anchoredOracle = _deployAnchoredOracleForPair(
            name,
            assets[0],
            assets[1],
            PYTH_ETH_USD_FEED,
            CHAINLINK_ETH_USD_FEED,
            maxDivergence,
            contracts["assetRegistry"],
            contracts["eulerRouter"]
        );
        vm.label(anchoredOracle, string.concat(name, "_AnchoredOracle"));
        vm.stopPrank();

        // Deploy basket and managed weight strategy
        address basketAddress = _setupBasketAndStrategy(name, address(0), assets, assetIndexes, weights);
        // User Requests deposit to basket
        _requestDepositToBasket(basketAddress, alice, depositAmount);

        // Rebalance is proposed
        address[] memory baskets = new address[](1);
        baskets[0] = basketAddress;
        uint40 currentEpoch = bm.rebalanceStatus().epoch;
        vm.prank(users["rebalancer"]);
        bm.proposeRebalance(baskets);

        // Rebalance is completed
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        _completeRebalanceWithTrades(baskets, externalTrades, internalTrades);

        // Check state after rebalance completes
        // Target weights not met due to no trading, epoch stays the same while retry count increments
        assertEq(uint256(bm.rebalanceStatus().status), uint256(Status.REBALANCE_PROPOSED));
        assertEq(bm.rebalanceStatus().epoch, currentEpoch);
        assertEq(bm.retryCount(), 1);
        console.log("basket total value: ", _calculateBasketValue(basketAddress));
    }

    // deals amount to user and deposits to basket, deposit amount kept track basketUserDeposits[basket][user]
    // returns requestId of deposit, used to track status of deposit request within basket token contract
    function _requestDepositToBasket(
        address basket,
        address user,
        uint256 amount
    )
        internal
        returns (uint256 requestId)
    {
        address asset = bm.basketAssets(basket)[0];
        basketUserPendingDeposits[basket][user] += amount;
        airdrop(IERC20(asset), user, amount, false);
        vm.startPrank(user);
        IERC20(asset).approve(basket, amount);
        requestId = BasketToken(basket).requestDeposit(amount, user, user);
        basketUserRequestId[basket][user] = requestId;
        vm.stopPrank();
    }

    // approves basket to spend amount of asset and requests redeem from basket
    function _requestRedeemFromBasket(
        address basket,
        address user,
        uint256 amount
    )
        internal
        returns (uint256 requestId)
    {
        basketUserPendingRedeems[basket][user] += amount;
        vm.startPrank(user);
        IERC20(basket).approve(basket, amount);
        requestId = BasketToken(basket).requestRedeem(amount, user, user);
        basketUserRequestId[basket][user] = requestId;
        vm.stopPrank();
    }

    // Completes a rebalance with given trades
    // If no trades are given, completes rebalance without any trades
    function _completeRebalanceWithTrades(
        address[] memory baskets,
        ExternalTrade[] memory externalTrades,
        InternalTrade[] memory internalTrades
    )
        internal
    {
        assertEq(uint256(bm.rebalanceStatus().status), uint256(Status.REBALANCE_PROPOSED), "Rebalance not proposed");
        _updatePythOracleTimeStamp(PYTH_ETH_USD_FEED);
        if (externalTrades.length > 0 || internalTrades.length > 0) {
            bm.proposeTokenSwap(internalTrades, externalTrades, baskets);
            // TODO: mocking / executing trades
        }
        vm.warp(block.timestamp + 15 minutes);
        _updatePythOracleTimeStamp(PYTH_ETH_USD_FEED);
        // Rebalance is completed
        vm.prank(users["rebalancer"]);
        bm.completeRebalance(externalTrades, baskets);
    }

    // Deploys a basket and sets its intial target weights
    // If strategy is address(0) a new ManagedWeightStrategy is deployed
    function _setupBasketAndStrategy(
        string memory name,
        address strategy,
        address[] memory assets,
        uint8[] memory assetIndexes,
        uint64[] memory initialWeights
    )
        internal
        returns (address basketAddress)
    {
        address admin = users["admin"];
        address mwStrategy = strategy == address(0) ? address(new ManagedWeightStrategy(admin, address(bm))) : strategy;
        uint256 bitFlag = _includeAssets(assetIndexes);
        vm.prank(admin);
        StrategyRegistry(contracts["strategyRegistry"]).grantRole(_WEIGHT_STRATEGY_ROLE, mwStrategy);
        vm.mockCall(
            mwStrategy, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag), abi.encode(true)
        );
        vm.prank(users["manager"]);
        basketAddress = bm.createNewBasket(string.concat(name, "_basketToken"), name, assets[0], bitFlag, mwStrategy);
        contracts[string.concat(name, "_Basket")] = basketAddress;
        vm.prank(admin);
        ManagedWeightStrategy(mwStrategy).setTargetWeights(bitFlag, initialWeights);
    }

    // Oracles are stuck on one block, mock updating oracle data with same price but with a valid publish time
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        res.publishTime = block.timestamp;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (pythPriceFeed)), abi.encode(res));
    }

    // Calculates the total value of a basket in USD including pending deposits
    function _calculateBasketValue(address basket) internal view returns (uint256 value) {
        address[] memory assets = bm.basketAssets(basket);
        uint256 pendingDeposits = BasketToken(basket).totalPendingDeposits();
        for (uint256 i; i < assets.length; i++) {
            uint256 balance = bm.basketBalanceOf(basket, assets[i]);
            if (i == 0) {
                balance += pendingDeposits;
            }
            if (balance == 0) {
                continue;
            }
            value += EulerRouter(contracts["eulerRouter"]).getQuote(balance, assets[i], USD);
        }
    }

    // Below WIP basically a bad solver, maybe python script is better solution for this
    // Finds external trades needed to reach a successful rebalance and proposes them.
    // Requires that proposeRebalance has already been called.
    // Amounts & target balances in same order as assets in baskets
    // 1. calls same oracles / does same calcs in same block as _calculateTargetBalances() in BM
    // 2. returns array of per-basket asset difference between current and target values.
    // 3. if given to findSuccessfulExternalTrades() will return trades that should result in successful rebalance
    function _logDifferenceInTargetWeights(
        address[] memory baskets,
        uint256[] memory amounts,
        address[] memory strategies
    )
        public
    {
        for (uint256 i; i < baskets.length; i++) {
            BasketToken basket = BasketToken(baskets[i]);
            address[] memory assets = bm.basketAssets(address(basket));
            uint256 epoch = basket.nextDepositRequestId(); // TODO check this is correct for epoch
            uint64[] memory targetWeights =
                ManagedWeightStrategy(strategies[i]).getTargetWeights(uint40(epoch), basket.bitFlag());
            uint256[] memory currentValues = new uint256[](assets.length);
            uint256 totalbasketValue = 0;
            for (uint256 j; j < assets.length; j++) {
                uint256 usdPrice = EulerRouter(contracts["eulerRouter"]).getQuote(amounts[i], assets[j], USD);
                currentValues[i] = usdPrice;
                totalbasketValue += usdPrice;
            }
            uint256[] memory currentWeights = new uint256[](assets.length);
            for (uint256 j; j < assets.length; j++) {
                currentWeights[i] = currentValues[i] * 1e18 / totalbasketValue;
            }
            for (uint256 j; j < assets.length; j++) {
                if (targetWeights[i] > currentWeights[i]) {
                    uint256 buy = (targetWeights[i] - currentWeights[i]) * totalbasketValue / 1e18; // TODO: check
                    console.log("target weight higher than current by :", targetWeights[i] - currentWeights[i]);
                    console.log("target weight higher than current by : $", buy);
                } else {
                    uint256 sell = (currentWeights[i] - targetWeights[i]) * totalbasketValue / 1e18; // TODO: check
                    console.log("target weight lower than current by :", currentWeights[i] - targetWeights[i]);
                    console.log("target weight lower than current by : $", sell);
                }
            }
        }
    }
}

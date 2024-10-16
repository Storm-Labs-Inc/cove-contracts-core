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
import { Constants } from "test/utils/Constants.t.sol";

import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { Deployments } from "script/Deployments.s.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

// Steps for completing a rebalance
// 1. Propose Rebalance
// - permissioned to the _REBALANCER_ROLE
// - Requirements for a rebalance to happen:
// - - any pending deposits / redeems
// - - have an imbalance in target vs current weights for basket larger than $500
// - - call proposeRebalance() with array of target basket tokens
// - - *note currently you can propose any number of baskets as long as one meets the above requirement. This is so
// all provided baskets are considered for internal trades. This may involve additional checks in the future
// - if successful the rebalance status is updated to REBALANCE_PROPOSED and timer is started. Basket tokens
// involved
// in this rebalance have their requestIds incremented so that any future deposit/redeem request are handled by the
// next redemption cycle.
// 2. Propose token swaps
// - permissioned to the _REBALANCER_ROLE
// - provide arrays of internal/external token swaps
// - these trades MUST result in the targeted weights ($ wise) for this call to succeed.
// - if successful the rebalance status is TOKEN_SWAP_PROPOSED
// 3. Execute Token swaps
// - permissioned to the _REBALANCER_ROLE
// - if external trades are proposed they must be executed on the token swap adapter. This can only happen after a
// set amount of time has passed to allow for the trades to happen. Calling execute token swap can result in any
// amount of trade success. The function returns all tokens back to the basket manager.
// - when token swaps are executed the status is updated to TOKEN_SWAP_EXECUTED
// 4. Complete Rebalance
// - permissionless
// - This must be called at least 15 minutes after propose token swap has been called.
// - If external trades have been executed gets the results and updates internal accounting
// - Processes internal trades and pending redeptions.
// - *note in the instance the target weights have not been met by the time of calling completeRebalance() a retry
// is initiated. In this case the status is set to REBALANCE_PROPOSED to allow for additional internal / external
// trades to be proposed and the steps above repeated. If the retry cycle happens the maximum amount of times the
// rebalance is completed regardless. If pending redemptions cannot be fulfilled because of an in-complete rebalance
// the basket tokens are notified and users with pending redemptions must claim their shares back and request a
// redeem once again.

contract IntegrationTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    mapping(string => address) public contracts;
    mapping(address => mapping(address => uint256)) public basketUserPendingDeposits;
    mapping(address => mapping(address => uint256)) public basketUserPendingRedeems;
    mapping(address => mapping(address => uint256)) public basketUserRequestId;
    BasketManager public bm;
    Deployments public deployments;

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        // Allow cheatcodes for contract deployed by deploy script
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);
        vm.startPrank(COVE_DEPLOYER_ADDRESS);
        deployments = new Deployments();
        deployments.deploy(false);
        vm.stopPrank();
        contracts["BasketManager"] = deployments.checkDeployment("BasketManager");
        vm.label(contracts["BasketManager"], "BasketManager");
        bm = BasketManager(contracts["BasketManager"]);
        contracts["AssetRegistry"] = deployments.checkDeployment("AssetRegistry");
        vm.label(contracts["AssetRegistry"], "AssetRegistry");
        contracts["StrategyRegistry"] = deployments.checkDeployment("StrategyRegistry");
        vm.label(contracts["StrategyRegistry"], "StrategyRegistry");
        contracts["EulerRouter"] = deployments.checkDeployment("EulerRouter");
        vm.label(contracts["EulerRouter"], "EulerRouter");
        contracts["FeeCollector"] = deployments.checkDeployment("FeeCollector");
        vm.label(contracts["FeeCollector"], "FeeCollector");
        vm.startPrank(COVE_OPS_MULTISIG);
        users["alice"] = createUser("alice");
        users["admin"] = deployments.admin();
        users["rebalancer"] = deployments.rebalancer();
        users["manager"] = deployments.manager();
    }

    function test_setUp() public {
        assert(deployments.checkDeployment("BasketManager") != address(0));
        deployments.deployAnchoredOracleForPair(
            "Test", WETH, USD, PYTH_ETH_USD_FEED, 15 minutes, 500, CHAINLINK_ETH_USD_FEED, 1 days, 0.5e18, false
        );
        assert(deployments.checkDeployment("Test_AnchoredOracle") != address(0));
    }

    function testFuzz_singleDepositor_completeRebalance(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, type(uint256).max / 1e36);
        address[] memory assets = new address[](2);
        assets[0] = WETH;
        assets[1] = USD;
        string memory name = "WETH/USD";
        uint256 maxDivergence = 0.5e18;
        uint256 pythMaxStaleness = 15 minutes;
        uint256 maxConfWidth = 500;
        uint256 chainLinkMaxStaleness = 1 days;
        // uint256 depositAmount = 1000e18; // TODO: remove
        uint8[] memory assetIndexes = new uint8[](2);
        assetIndexes[0] = 0;
        assetIndexes[1] = 1;
        uint64[] memory weights = new uint64[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;
        vm.startPrank(users["admin"]);
        deployments.deployAnchoredOracleForPair(
            name,
            assets[0],
            assets[1],
            PYTH_ETH_USD_FEED,
            pythMaxStaleness,
            maxConfWidth,
            CHAINLINK_ETH_USD_FEED,
            chainLinkMaxStaleness,
            maxDivergence,
            false
        );
        address anchoredOracle = deployments.getAddress(string.concat(name, "_AnchoredOracle"));
        vm.label(anchoredOracle, string.concat(name, "_AnchoredOracle"));
        vm.stopPrank();
        // Deploy basket and managed weight strategy
        address basketAddress = _setupBasketAndStrategy(name, address(0), assets, assetIndexes, weights);
        // User Requests deposit to basket
        _requestDepositToBasket(basketAddress, users["alice"], depositAmount);

        // Rebalance is proposed
        address[] memory baskets = new address[](1);
        baskets[0] = basketAddress;
        uint40 currentEpoch = bm.rebalanceStatus().epoch;
        _updatePythOracleTimeStamp(PYTH_ETH_USD_FEED);
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
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;
        address[] memory strategies = new address[](1);
        strategies[0] = contracts[string.concat(name, "_ManagedWeightStrategy")];
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0;
        _logDifferenceInTargetWeights(baskets, epochs, amounts, strategies);
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
        if (strategy == address(0)) {
            strategy = address(new ManagedWeightStrategy(admin, contracts["BasketManager"]));
            contracts[string.concat(name, "_ManagedWeightStrategy")] = strategy;
            vm.label(strategy, string.concat(name, "_ManagedWeightStrategy"));
        }
        uint256 bitFlag = deployments.includeAssets(assetIndexes);
        vm.prank(admin);
        StrategyRegistry(contracts["StrategyRegistry"]).grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
        vm.mockCall(
            strategy, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag), abi.encode(true)
        );
        vm.prank(users["manager"]);
        basketAddress = bm.createNewBasket(string.concat(name, "_basketToken"), name, assets[0], bitFlag, strategy);
        contracts[string.concat(name, "_Basket")] = basketAddress;
        vm.prank(admin);
        ManagedWeightStrategy(strategy).setTargetWeights(bitFlag, initialWeights);
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
            value += EulerRouter(contracts["EulerRouter"]).getQuote(balance, assets[i], USD);
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
        uint256[] memory epochs,
        uint256[] memory amounts,
        address[] memory strategies
    )
        public
    {
        for (uint256 i; i < baskets.length; i++) {
            BasketToken basket = BasketToken(baskets[i]);
            address[] memory assets = bm.basketAssets(address(basket));
            // uint256 epoch = basket.nextDepositRequestId() - 2; // TODO check this is correct for epoch
            uint64[] memory targetWeights =
                ManagedWeightStrategy(strategies[i]).getTargetWeights(uint40(epochs[0]), basket.bitFlag());
            uint256[] memory currentValues = new uint256[](assets.length);
            uint256 totalbasketValue = 0;
            for (uint256 j; j < assets.length; j++) {
                uint256 usdPrice = EulerRouter(contracts["EulerRouter"]).getQuote(amounts[i], assets[j], USD);
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
                    uint256 sell = (currentWeights[i] - targetWeights[i]) * totalbasketValue / 1e18; // TODO:
                    console.log("target weight lower than current by :", currentWeights[i] - targetWeights[i]);
                    console.log("target weight lower than current by : $", sell);
                }
            }
        }
    }
}

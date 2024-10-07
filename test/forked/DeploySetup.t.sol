// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "@pyth/IPyth.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { PythStructs } from "@pyth/PythStructs.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";

import { Create2 } from "@openzeppelin-upgradeable/lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
// import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";
import { ExternalTrade } from "src/types/Trades.sol";

import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { console } from "forge-std/console.sol";
import { AnchoredOracle } from "src/AnchoredOracle.sol";

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

contract DeploySetup is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    mapping(string => address) public contracts;
    mapping(address => mapping(address => uint256)) public basketUserPendingDeposits;
    mapping(address => mapping(address => uint256)) public basketUserPendingRedeems;
    mapping(address => mapping(address => uint256)) public basketUserRequestId;
    address[] public assets;

    /// Steps for completeing a rebalance
    // 1. Propose Rebalance
    // - permissioned to the _REBALANCER_ROLE
    // - Requirements for a rebalance to happen:
    // - - any pending deposits / redeems
    // - - have an inbalance in target vs current weights for basket larger than $500
    // - - call proposeRebalance() with array of target basket tokens
    // - - *note currently you can propose any number of baskets as long as one meets the above requirement. This is so
    // all provided baskets are considered for internal trades. This may involve additional checks in the future
    // - if succesful the rebalance status is updated to REBALANCE_PROPOSED and timer is started. Basket tokens involved
    // in this rebalance have their requestIds incremented so that any future deposit/redeem request are handled by the
    // next redemption cycle.
    // 2. Propose token swaps
    // - permissioned to the _REBALANCER_ROLE
    // - provide arrays of internal/external token swaps
    // - these trades MUST result in the targeted weights ($ wise) for this call to succeed.
    // - if succesful the rebalance status is TOKEN_SWAP_PROPOSED
    // 3. Execute Token swaps
    // - permissioned to the _REBALANCER_ROLE
    // - if external trades are proposed they must be executed on the token swap adapter. This can only happen after a
    // set amount of time has passed to allow for the trades to happen. Calling execute token swap can result in any
    // amount of trade success. The function returns all tokens back to the basket manager.
    // - when token swaps are executed the status is updated to TOKEN_SWAP_EXECUTED
    // 4. Complete Rebalance
    // - permissionless
    // - This must be called at least 15 mintues after propose token swap has been called.
    // - If external trades have been executed gets the results and updates internal accounting
    // - Processes internal trades and pending redeptions.
    // - *note in the instance the target weights have not been met by the time of calling completeRebalance() a retry
    // is initiated. In this case the status is set to REBALANCE_PROPOSED to allow for additional internal / external
    // trades to be proposed and the steps above repeated. If the retry cycle happens the maximum amount of times the
    // rebalance is completed regardless. If pending redemptions cannot be fulfilled because of an in-complete rebalance
    // the basket tokens are notifed and users with pending redemptions must claim their shares back and request a
    // redeem once again.

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();

        // USERS
        super.setUp();
        users["alice"] = createUser("alice");
        users["admin"] = createUser("admin");
        users["treasury"] = createUser("treasury");
        users["pauser"] = createUser("pauser");
        users["manager"] = createUser("manager");
        users["rebalancer"] = createUser("rebalancer");

        // REGISTRIES
        contracts["assetRegistry"] = address(new AssetRegistry(users["admin"]));
        contracts["strategyRegistry"] = address(new StrategyRegistry(users["admin"]));

        // COWSWAP ADAPTER

        // BASKET MANAGER
        contracts["basketTokenImplementation"] = address(new BasketToken());
        vm.label(contracts["basketTokenImplementation"], "basketTokenImplementation");
        contracts["eulerRouter"] = address(new EulerRouter(users["admin"]));
        vm.label(contracts["eulerRouter"], "eulerRouter");
        // Compute the address of the FeeCollector using Create2
        bytes32 salt = keccak256(abi.encodePacked(users["admin"], users["treasury"]));
        bytes memory feeCollectorBytecode = type(FeeCollector).creationCode;
        bytes memory feeCollectorInitCode = abi.encodePacked(
            feeCollectorBytecode,
            abi.encode(users["admin"], address(0), users["treasury"]) // Pass a placeholder for basketManager
        );
        bytes32 feeCollectorCodeHash = keccak256(feeCollectorInitCode);
        address feeCollectorAddress = Create2.computeAddress(salt, feeCollectorCodeHash);
        // Now deploy the BasketManager with the known FeeCollector address
        BasketManager basketManager = new BasketManager(
            contracts["basketTokenImplementation"],
            contracts["eulerRouter"],
            contracts["strategyRegistry"],
            contracts["assetRegistry"],
            users["admin"],
            users["pauser"],
            feeCollectorAddress // Pass the computed address
        );
        contracts["basketManager"] = address(basketManager);
        vm.label(contracts["basketManager"], "basketManager");

        // FEE COLLECTOR
        // Now deploy the FeeCollector using Create2, passing the actual basketManager address
        feeCollectorInitCode = abi.encodePacked(
            feeCollectorBytecode, abi.encode(users["admin"], contracts["basketManager"], users["treasury"])
        );
        contracts["feeCollector"] = Create2.deploy(0, salt, feeCollectorInitCode);
        vm.label(contracts["feeCollector"], "feeCollector");
        vm.startPrank(users["admin"]);
        basketManager.grantRole(MANAGER_ROLE, users["manager"]);
        basketManager.grantRole(REBALANCER_ROLE, users["rebalancer"]);
        basketManager.grantRole(PAUSER_ROLE, users["pauser"]);
        basketManager.grantRole(TIMELOCK_ROLE, users["timelock"]);
        vm.stopPrank();
    }

    function testFuzz_singleDepositor_completeRebalance(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, type(uint256).max);

        BasketManager bm = BasketManager(contracts["basketManager"]);
        address[] memory assets = new address[](2);
        assets[0] = WETH;
        assets[1] = USD;
        string memory name = "WETH/USD";
        uint8[] memory assetIndexes = new uint8[](2);
        assetIndexes[0] = 0;
        assetIndexes[1] = 1;
        uint256 bitFlag = _includeAssets(assetIndexes);
        address basketAddress =
            _deployBasket("WETH/USD", assets, bitFlag, PYTH_ETH_USD_FEED, CHAINLINK_ETH_USD_FEED, 0.5e18);
        BasketToken basket = BasketToken(basketAddress);
        console.log(basketAddress);
        address[] memory baskets = new address[](1);
        baskets[0] = basketAddress;
        uint64[] memory weights = new uint64[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;
        vm.prank(users["admin"]);
        ManagedWeightStrategy(contracts[string.concat("mwStrategy_", name)]).setTargetWeights(bitFlag, weights);
        uint256 depositAmount = 1000e18;
        _requestDepositToBasket(basketAddress, users["alice"], depositAmount);
        vm.prank(users["rebalancer"]);
        bm.proposeRebalance(baskets);
        vm.warp(block.timestamp + 15 minutes);
        _updatePythOracleTimeStamp(PYTH_ETH_USD_FEED);
        ExternalTrade[] memory trades = new ExternalTrade[](0);
        vm.prank(users["rebalancer"]);
        bm.completeRebalance(trades, baskets);
        uint256 balanceBefore = basket.balanceOf(users["alice"]);
        vm.prank(users["alice"]);
        basket.deposit(depositAmount, users["alice"], users["alice"]);
        uint256 balanceAfter = basket.balanceOf(users["alice"]);
        assertGt(balanceAfter, balanceBefore);
    }

    /// INTERNAL FUNCTIONS ///

    // name like: "ETH/USD"
    function _deployAnchoredOracleForPair(
        string memory name,
        address baseAsset,
        address quoteAsset,
        bytes32 pythPriceFeed,
        address chainLinkPriceFeed,
        uint256 maxDivergence
    )
        public
        returns (address anchoredOracle)
    {
        PythOracle primary = new PythOracle(Constants.PYTH, baseAsset, quoteAsset, pythPriceFeed, 15 minutes, 500);
        ChainlinkOracle anchor = new ChainlinkOracle(baseAsset, quoteAsset, chainLinkPriceFeed, 1 days);
        string memory oracleName = string.concat(name, "_AnchoredOracle");
        console.log(address(primary));
        console.log(address(anchor));
        contracts[oracleName] = address(new AnchoredOracle(address(primary), address(anchor), maxDivergence));
        console.log("deploying: ", oracleName);
        console.log("deployed anchored oracle at: ", contracts[oracleName]);
        vm.label(contracts[oracleName], oracleName);
        vm.startPrank(users["admin"]);
        AssetRegistry assetRegistry = AssetRegistry(contracts["assetRegistry"]);
        // if asset already added will revert
        try assetRegistry.addAsset(baseAsset) { } catch { }
        try assetRegistry.addAsset(quoteAsset) { } catch { }
        assets.push(baseAsset);
        assets.push(quoteAsset);
        EulerRouter(contracts["eulerRouter"]).govSetConfig(baseAsset, quoteAsset, contracts[oracleName]);
        EulerRouter(contracts["eulerRouter"]).govSetConfig(quoteAsset, baseAsset, contracts[oracleName]);
        vm.stopPrank();
    }

    // name like: "ETH/USD"
    // root asset considered to be first in assets[]
    function _deployBasket(
        string memory name,
        address[] memory assets,
        uint256 bitFlag,
        bytes32 pythPriceFeed,
        address chainLinkPriceFeed,
        uint256 maxDivergence
    )
        public
        returns (address basketToken)
    {
        address strategy = address(new ManagedWeightStrategy(users["admin"], contracts["basketManager"]));
        vm.mockCall(
            strategy, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag), abi.encode(true)
        );
        contracts[string.concat("mwStrategy_", name)] = strategy;
        vm.prank(users["admin"]);
        StrategyRegistry(contracts["strategyRegistry"]).grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
        if (contracts[string.concat(name, "_AnchoredOracle")] == address(0)) {
            _deployAnchoredOracleForPair(name, assets[0], assets[1], pythPriceFeed, chainLinkPriceFeed, maxDivergence);
        }
        BasketManager basketManager = BasketManager(contracts["basketManager"]);
        vm.prank(users["manager"]);
        basketToken =
            basketManager.createNewBasket(string.concat(name, "_basketToken"), name, assets[0], bitFlag, strategy);
        contracts[string.concat(name, "_Basket")] = basketToken;
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
        address asset = BasketManager(contracts["basketManager"]).basketAssets(basket)[0];
        console.log(asset);
        basketUserPendingDeposits[basket][user] += amount;
        airdrop(IERC20(asset), user, amount, false);
        vm.startPrank(user);
        IERC20(asset).approve(basket, amount);
        requestId = BasketToken(basket).requestDeposit(amount, user, user);
        basketUserRequestId[basket][user] = requestId;
        vm.stopPrank();
    }

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

    // Below WIP basically a bad solver, maybe python script is better solution for this
    // Finds external trades needed to reach a successfull rebalance and proposes them.
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
        BasketManager bm = BasketManager(contracts["basketManager"]);
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
                    uint256 buy = (targetWeights[i] - currentWeights[i]) * totalbasketValue / 1e18; // TODO check
                    console.log("target weight higher than current by :", targetWeights[i] - currentWeights[i]);
                    console.log("target weight higher than current by : $", buy);
                } else {
                    uint256 sell = (currentWeights[i] - targetWeights[i]) * totalbasketValue / 1e18; // TODO check
                    console.log("target weight lower than current by :", currentWeights[i] - targetWeights[i]);
                    console.log("target weight lower than current by : $", sell);
                }
            }
        }
    }

    function _calculateBasketValue(address basket) internal view returns (uint256 value) {
        BasketManager bm = BasketManager(contracts["basketManager"]);
        address[] memory assets = bm.basketAssets(basket);
        uint256 pendingDeposits = BasketToken(basket).totalPendingDeposits();
        for (uint256 i; i < assets.length; i++) {
            uint256 balance = bm.basketBalanceOf(basket, assets[i]);
            if (i == 0) {
                balance += pendingDeposits;
            }
            value += EulerRouter(contracts["eulerRouter"]).getQuote(IERC20(assets[i]).balanceOf(basket), assets[i], USD);
        }
    }

    // Include asset index in bitflag
    function _includeAssets(uint8[] memory assetIndices) internal pure returns (uint256 bitFlag) {
        for (uint256 i = 0; i < assetIndices.length; i++) {
            bitFlag |= 1 << assetIndices[i];
        }
    }

    // Oracles are stuck on one block, mock updating oracle data with same price but with a valid publish time
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        res.publishTime = block.timestamp;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (pythPriceFeed)), abi.encode(res));
    }
}

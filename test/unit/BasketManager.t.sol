// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { BasketManager } from "src/BasketManager.sol";

import { BasketToken } from "src/BasketToken.sol";

import { console } from "forge-std/console.sol";
import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { Errors } from "src/libraries/Errors.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Constants } from "test/utils/Constants.t.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

contract BasketManagerTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    BasketManager public basketManager;
    MockPriceOracle public mockPriceOracle;
    EulerRouter public eulerRouter;
    address public alice;
    address public admin;
    address public feeCollector;
    address public manager;
    address public timelock;
    address public rebalancer;
    address public pauser;
    address public rootAsset;
    address public pairAsset;
    address public basketTokenImplementation;
    address public strategyRegistry;
    address public tokenSwapAdapter;

    address public constant USD_ISO_4217_CODE = address(840);

    struct TradeTestParams {
        uint256 sellWeight;
        uint256 depositAmount;
        uint256 baseAssetWeight;
        address pairAsset;
    }

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        admin = createUser("admin");
        feeCollector = createUser("feeCollector");
        pauser = createUser("pauser");
        manager = createUser("manager");
        rebalancer = createUser("rebalancer");
        rootAsset = address(new ERC20Mock());
        vm.label(rootAsset, "rootAsset");
        pairAsset = address(new ERC20Mock());
        vm.label(pairAsset, "pairAsset");
        basketTokenImplementation = createUser("basketTokenImplementation");
        mockPriceOracle = new MockPriceOracle();
        vm.label(address(mockPriceOracle), "mockPriceOracle");
        eulerRouter = new EulerRouter(admin);
        strategyRegistry = createUser("strategyRegistry");
        basketManager = new BasketManager(
            basketTokenImplementation, address(eulerRouter), strategyRegistry, admin, feeCollector, pauser
        );
        vm.startPrank(admin);
        mockPriceOracle.setPrice(rootAsset, USD_ISO_4217_CODE, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(pairAsset, USD_ISO_4217_CODE, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, rootAsset, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, pairAsset, 1e18); // set price to 1e18
        eulerRouter.govSetConfig(rootAsset, USD_ISO_4217_CODE, address(mockPriceOracle));
        eulerRouter.govSetConfig(pairAsset, USD_ISO_4217_CODE, address(mockPriceOracle));
        basketManager.grantRole(MANAGER_ROLE, manager);
        basketManager.grantRole(REBALANCER_ROLE, rebalancer);
        basketManager.grantRole(PAUSER_ROLE, pauser);
        basketManager.grantRole(TIMELOCK_ROLE, timelock);
        vm.stopPrank();

        tokenSwapAdapter = createUser("tokenSwapAdapter");
        vm.label(address(basketManager), "basketManager");
    }

    function testFuzz_constructor(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address admin_,
        address feeCollector_,
        address pauser_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(eulerRouter_ != address(0));
        vm.assume(strategyRegistry_ != address(0));
        vm.assume(admin_ != address(0));
        vm.assume(feeCollector_ != address(0));
        vm.assume(pauser_ != address(0));
        BasketManager bm = new BasketManager(
            basketTokenImplementation_, eulerRouter_, strategyRegistry_, admin_, feeCollector_, pauser_
        );
        assertEq(address(bm.eulerRouter()), eulerRouter_);
        assertEq(address(bm.strategyRegistry()), strategyRegistry_);
        assertEq(address(bm.feeCollector()), feeCollector_);
        assertEq(bm.hasRole(DEFAULT_ADMIN_ROLE, admin_), true);
        assertEq(bm.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(bm.hasRole(PAUSER_ROLE, pauser_), true);
        assertEq(bm.getRoleMemberCount(PAUSER_ROLE), 1);
    }

    function testFuzz_constructor_revertWhen_ZeroAddress(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address admin_,
        address feeCollector_,
        address pauser_,
        uint256 flag
    )
        public
    {
        // Use flag to determine which address to set to zero
        flag = bound(flag, 0, 16);
        if (flag & 1 == 0) {
            basketTokenImplementation_ = address(0);
        }
        if (flag & 2 == 0) {
            eulerRouter_ = address(0);
        }
        if (flag & 4 == 0) {
            strategyRegistry_ = address(0);
        }
        if (flag & 8 == 0) {
            admin_ = address(0);
        }
        if (flag & 16 == 0) {
            feeCollector_ = address(0);
        }

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BasketManager(basketTokenImplementation_, eulerRouter_, strategyRegistry_, admin_, feeCollector_, pauser_);
    }

    function testFuzz_constructor_revertWhen_pasuerZeroAddress(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address admin_,
        address feeCollector_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(eulerRouter_ != address(0));
        vm.assume(strategyRegistry_ != address(0));
        vm.assume(admin_ != address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BasketManager(
            basketTokenImplementation_, eulerRouter_, strategyRegistry_, admin_, feeCollector_, address(0)
        );
    }

    function testFuzz_constructor_revertWhen_feeCollectorZeroAddress(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address admin_,
        address pauser_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(eulerRouter_ != address(0));
        vm.assume(strategyRegistry_ != address(0));
        vm.assume(admin_ != address(0));
        vm.assume(pauser_ != address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BasketManager(basketTokenImplementation_, eulerRouter_, strategyRegistry_, admin_, address(0), pauser_);
    }

    function test_unpause() public {
        vm.prank(pauser);
        basketManager.pause();
        assertTrue(basketManager.paused(), "contract not paused");
        vm.prank(admin);
        basketManager.unpause();
        assertFalse(basketManager.paused(), "contract not unpaused");
    }

    function test_pause_revertWhen_notPauser() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.Unauthorized.selector));
        basketManager.pause();
    }

    function test_unpause_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), DEFAULT_ADMIN_ROLE));
        basketManager.unpause();
    }

    function testFuzz_createNewBasket(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, admin)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(strategyRegistry, abi.encodeWithSelector(StrategyRegistry.getAssets.selector), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, address(rootAsset), bitFlag, strategy);
        assertEq(basketManager.numOfBasketTokens(), 1);
        address[] memory tokens = basketManager.basketTokens();
        assertEq(tokens[0], basket);
        assertEq(basketManager.basketIdToAddress(keccak256(abi.encodePacked(bitFlag, strategy))), basket);
        assertEq(basketManager.basketTokenToRebalanceAssetToIndex(basket, address(rootAsset)), 0);
        assertEq(basketManager.basketTokenToIndex(basket), 0);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenMaxExceeded(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        bitFlag = bound(bitFlag, 0, type(uint256).max - 257);
        strategy = address(uint160(bound(uint160(strategy), 0, type(uint160).max - 257)));
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            strategyRegistry, abi.encodeWithSelector(StrategyRegistry.supportsBitFlag.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(strategyRegistry, abi.encodeWithSelector(StrategyRegistry.getAssets.selector), abi.encode(assets));
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            bitFlag += 1;
            strategy = address(uint160(strategy) + 1);
            basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
            assertEq(basketManager.numOfBasketTokens(), i + 1);
        }
        vm.expectRevert(BasketManagerUtils.BasketTokenMaxExceeded.selector);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenAlreadyExists(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, admin)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(strategyRegistry, abi.encodeWithSelector(StrategyRegistry.getAssets.selector), abi.encode(assets));
        vm.startPrank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
        vm.expectRevert(BasketManagerUtils.BasketTokenAlreadyExists.selector);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_StrategyRegistryDoesNotSupportStrategy(
        uint256 bitFlag,
        address strategy
    )
        public
    {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, admin)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(false)
        );
        vm.expectRevert(BasketManagerUtils.StrategyRegistryDoesNotSupportStrategy.selector);
        vm.startPrank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_CallerIsNotManager(address caller) public {
        vm.assume(!basketManager.hasRole(MANAGER_ROLE, caller));
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        vm.prank(caller);
        vm.expectRevert(_formatAccessControlError(caller, MANAGER_ROLE));
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_AssetListEmpty() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](0);
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, admin)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(strategyRegistry, abi.encodeCall(StrategyRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.AssetListEmpty.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_BaseAssetMismatch() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address wrongAsset = address(new ERC20Mock());
        address[] memory assets = new address[](1);
        assets[0] = wrongAsset;

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, admin)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(strategyRegistry, abi.encodeCall(StrategyRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.BaseAssetMismatch.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_BaseAssetIsZeroAddress() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.prank(manager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        basketManager.createNewBasket(name, symbol, address(0), bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_paused() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = address(0);

        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, address(0), bitFlag, strategy);
    }

    function test_basketTokenToIndex() public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            strategyRegistry, abi.encodeWithSelector(StrategyRegistry.supportsBitFlag.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(strategyRegistry, abi.encodeWithSelector(StrategyRegistry.getAssets.selector), abi.encode(assets));
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, address(uint160(i)));
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i);
        }

        for (uint256 i = 0; i < 256; i++) {
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i);
        }
    }

    function test_basketTokenToIndex_revertWhen_BasketTokenNotFound() public {
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(address(0));
    }

    function testFuzz_basketTokenToIndex_revertWhen_BasketTokenNotFound(address basket) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            strategyRegistry, abi.encodeWithSelector(StrategyRegistry.supportsBitFlag.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(strategyRegistry, abi.encodeWithSelector(StrategyRegistry.getAssets.selector), abi.encode(assets));
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, address(uint160(i)));
            vm.assume(baskets[i] != basket);
        }

        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(basket);
    }

    function test_proposeRebalance_processesDeposits() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.rebalanceStatus().basketHash, keccak256(abi.encodePacked(targetBaskets)));
    }

    function test_proposeRebalance_revertWhen_depositTooLittle_RebalanceNotRequired() public {
        address basket = _setupBasketAndMocks(100);
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;

        vm.expectRevert(BasketManagerUtils.RebalanceNotRequired.selector);
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_noDeposits_RebalanceNotRequired() public {
        address basket = _setupBasketAndMocks(0);
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;

        vm.expectRevert(BasketManagerUtils.RebalanceNotRequired.selector);
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_MustWaitForRebalanceToComplete() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.startPrank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_BasketTokenNotFound(address fakeBasket) public {
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = fakeBasket;
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_CallerIsNotRebalancer(address caller) public {
        vm.assume(!basketManager.hasRole(REBALANCER_ROLE, caller));
        address[] memory targetBaskets = new address[](1);
        vm.expectRevert(_formatAccessControlError(caller, REBALANCER_ROLE));
        vm.prank(caller);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_processesDeposits_revertWhen_paused() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_completeRebalance_passWhen_redeemingShares() public {
        uint256 intialDepositAmount = 10_000;
        uint256 initialSplit = 5e17; // 50 / 50 between both baskets
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, intialDepositAmount);
        address basket = targetBaskets[0];

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets);
    }

    function testFuzz_completeRebalance_externalTrade(uint256 initialDepositAmount, uint256 sellWeight) public {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        uint256 sellWeight = bound(sellWeight, 0, 1e18); // TODO: doulbe check this value
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];

        // Mock calls for executeTokenSwap
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1st position is the result of a 100% successful trade
        claimedAmounts[0] = [initialDepositAmount * sellWeight / 1e18, 0];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.prank(rebalancer);
        basketManager.completeRebalance(trades, targetBaskets);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_retries_whenExternalTrade_fails(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 1e17, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];

        // Mock calls for executeTokenSwap
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 0th place is the result of a 100% un-successful trade
        claimedAmounts[0] = [0, initialDepositAmount * sellWeight / 1e18];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        assertEq(basketManager.retryCount(), uint256(0));
        vm.prank(rebalancer);
        basketManager.completeRebalance(trades, targetBaskets);
        // When target weights are not met the status returns to REBALANCE_PROPOSED to allow additional token swaps to
        // be proposed
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.retryCount(), uint256(1));
    }

    // function test_completeRebalance_triggers_notifyFailedRebalance_when_retryLimitReached(
    //     uint256 initialDepositAmount,
    //     uint256 sellWeight
    // )
    //     public
    // {
    //     _setTokenSwapAdapter();
    //     // Setup basket and target weights
    //     TradeTestParams memory params;
    //     params.depositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
    //     params.depositAmount = 10_000; // TODO remove
    //     params.sellWeight = bound(sellWeight, 1e17, 1e18);
    //     params.sellWeight = 5e17; // 50/50 // TODO remove
    //     params.baseAssetWeight = 1e18 - params.sellWeight;
    //     params.pairAsset = pairAsset;
    //     address[][] memory basketAssets = new address[][](1);
    //     basketAssets[0] = new address[](2);
    //     basketAssets[0][0] = rootAsset;
    //     basketAssets[0][1] = params.pairAsset;
    //     uint256[] memory initialDepositAmounts = new uint256[](1);
    //     initialDepositAmounts[0] = params.depositAmount;
    //     uint256[][] memory targetWeights = new uint256[][](2);
    //     targetWeights[0] = new uint256[](2);
    //     targetWeights[0][0] = params.baseAssetWeight;
    //     targetWeights[0][1] = params.sellWeight;
    //     address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
    //     // Propose the rebalance
    //     vm.prank(rebalancer);
    //     basketManager.proposeRebalance(baskets);

    //     // for (uint8 i = 0; i < _MAX_RETRIES; i++) {
    //     for (uint8 i = 0; i < 2; i++) {
    //         // 0 for the last input will guarentee the trade will be 100% unsuccessful
    //         _proposeAndCompleteExternalTrades(baskets, params.depositAmount, params.sellWeight, 0);
    //         assertEq(basketManager.retryCount(), uint256(i + 1));
    //         assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
    //     }
    //     // We have reached max retries, if the next proposed token swap does not meet target weights the rebalance
    // will
    //     // successfully complete. If funds are not available for pending withdraws the basket token will be notified
    //     // of a failed rebalance.
    // }

    function test_completeRebalance_revertWhen_NoRebalanceInProgress() public {
        vm.expectRevert(BasketManagerUtils.NoRebalanceInProgress.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), new address[](0));
    }

    function test_completeRebalance_revertWhen_BasketsMismatch() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), new address[](0));
    }

    function test_completeRebalance_revertWhen_TooEarlyToCompleteRebalance() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.TooEarlyToCompleteRebalance.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets);
    }

    function test_completeRebalance_revertWhen_paused() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets);
    }

    // TODO: Write a fuzz test that generalizes the number of external trades
    // Currently the test only tests 1 external trades at a time.
    function testFuzz_proposeTokenSwap_externalTrade(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
        returns (ExternalTrade[] memory, address[] memory)
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        vm.assume(depositAmount < type(uint256).max / 1e36);
        params.depositAmount = depositAmount;
        // TODO: below is not behaving as expected, possible foundry bug.
        // params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        // vm.prank(admin);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint256[][] memory targetWeights = new uint256[][](2);
        targetWeights[0] = new uint256[](2);
        targetWeights[0][0] = params.baseAssetWeight;
        targetWeights[0][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);

        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(block.timestamp));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));
        return (externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_externalTrade_ExternalTradeSlippage(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 1, 1e18 - 1); // Ensure non-zero sell weight
        params.depositAmount = bound(depositAmount, 1000, type(uint256).max / 1e36); // Ensure non-zero deposit
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint256[][] memory targetWeights = new uint256[][](2);
        targetWeights[0] = new uint256[](2);
        targetWeights[0][0] = params.baseAssetWeight;
        targetWeights[0][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });

        uint256 sellAmount = params.depositAmount * params.sellWeight / 1e18;
        uint256 minAmount = sellAmount * 1.06e18 / 1e18; // Set minAmount 6% higher than sellAmount

        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: sellAmount,
            minAmount: minAmount,
            basketTradeOwnership: tradeOwnerships
        });

        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.ExternalTradeSlippage.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_internalTrade(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
        returns (address[] memory baskets)
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36);
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        _setPrices(params.pairAsset);

        // Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = params.depositAmount;
        depositAmounts[1] = params.depositAmount;
        uint256[][] memory initialWeights = new uint256[][](2);
        initialWeights[0] = new uint256[](2);
        initialWeights[0][0] = params.baseAssetWeight;
        initialWeights[0][1] = params.sellWeight;
        initialWeights[1] = new uint256[](2);
        initialWeights[1][0] = params.baseAssetWeight;
        initialWeights[1][1] = params.sellWeight;
        baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        // Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 0.995e18 / 1e18,
            maxAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 1.005e18 / 1e18
        });
        uint256 basket0RootAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[0], rootAsset);
        uint256 basket0PairAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[0], params.pairAsset);
        uint256 basket1RootAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[1], rootAsset);
        uint256 basket1PairAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[1], params.pairAsset);
        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(block.timestamp));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));
        assertEq(
            basketManager.basketBalanceOf(baskets[0], rootAsset),
            basket0RootAssetBalanceOfBefore - internalTrades[0].sellAmount
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[0], params.pairAsset),
            basket0PairAssetBalanceOfBefore + internalTrades[0].sellAmount
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[1], rootAsset),
            basket1RootAssetBalanceOfBefore + internalTrades[0].sellAmount
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[1], params.pairAsset),
            basket1PairAssetBalanceOfBefore - internalTrades[0].sellAmount
        );
    }

    function testFuzz_proposeTokenSwap_revertWhen_CallerIsNotRebalancer(address caller) public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        vm.assume(!basketManager.hasRole(REBALANCER_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, REBALANCER_ROLE));
        vm.prank(caller);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
    }

    function test_proposeTokenSwap_revertWhen_MustWaitForRebalance() public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
    }

    function test_proposeTokenSwap_revertWhen_BaketMisMatch() public {
        test_proposeRebalance_processesDeposits();
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_internalTradeBasketNotFound(
        uint256 sellWeight,
        uint256 depositAmount,
        address mismatchAssetAddress
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        vm.assume(mismatchAssetAddress != rootAsset);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        initialDepositAmounts[1] = params.depositAmount;
        uint256[][] memory initialWeights = new uint256[][](2);
        initialWeights[0] = new uint256[](2);
        initialWeights[0][0] = params.baseAssetWeight;
        initialWeights[0][1] = params.sellWeight;
        initialWeights[1] = new uint256[](2);
        initialWeights[1][0] = params.baseAssetWeight;
        initialWeights[1][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalancer);

        // Propose the rebalance
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: address(1), // add incorrect basket address
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.ElementIndexNotFound.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_internalTradeAmmountTooBig(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 sellAmount
    )
        public
    {
        /// Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36 - 1);
        sellAmount = bound(sellAmount, 0, type(uint256).max / 1e36 - 1);
        // Minimum deposit amount must be greater than 500 for a rebalance to be valid
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);

        /// Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = params.depositAmount;
        depositAmounts[1] = params.depositAmount - 1;
        uint256[][] memory initialWeights = new uint256[][](2);
        initialWeights[0] = new uint256[](2);
        initialWeights[0][0] = params.baseAssetWeight;
        initialWeights[0][1] = params.sellWeight;
        initialWeights[1] = new uint256[](2);
        initialWeights[1][0] = params.baseAssetWeight;
        initialWeights[1][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        /// Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        // Assume for the case where the sell amount is greater than the balance of the from basket, thus providing
        // invalid input to the function
        vm.assume(sellAmount > basketManager.basketBalanceOf(baskets[0], rootAsset));
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: sellAmount,
            minAmount: 0,
            maxAmount: type(uint256).max
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        // Assume for the case where the amount bought is greater than the balance of the to basket, thus providing
        // invalid input to the function
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: basketManager.basketBalanceOf(baskets[0], rootAsset),
            minAmount: 0,
            maxAmount: type(uint256).max
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_externalTradeBasketNotFound(
        uint256 sellWeight,
        uint256 depositAmount,
        address mismatchAssetAddress
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint256[][] memory targetWeights = new uint256[][](2);
        targetWeights[0] = new uint256[](2);
        targetWeights[0][0] = params.baseAssetWeight;
        targetWeights[0][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        vm.assume(mismatchAssetAddress != baskets[0]);

        // Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: mismatchAssetAddress, tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.ElementIndexNotFound.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_InternalTradeMinMaxAmountNotReached(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        initialDepositAmounts[1] = params.depositAmount;
        uint256[][] memory initialWeights = new uint256[][](2);
        initialWeights[0] = new uint256[](2);
        initialWeights[0][0] = params.baseAssetWeight;
        initialWeights[0][1] = params.sellWeight;
        initialWeights[1] = new uint256[](2);
        initialWeights[1][0] = params.baseAssetWeight;
        initialWeights[1][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalancer);

        // Propose the rebalance
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18 + 1,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.InternalTradeMinMaxAmountNotReached.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_internalTrade_revertWhen_TargetWeightsNotMet(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 deviation
    )
        public
    {
        uint256 max_weight_deviation = 0.05e18 + 1;
        /// Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18 - max_weight_deviation);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36);
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        deviation = bound(deviation, max_weight_deviation, params.baseAssetWeight);
        vm.assume(params.baseAssetWeight + deviation < 1e18);
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);

        // Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = params.depositAmount;
        depositAmounts[1] = params.depositAmount;
        uint256[][] memory initialWeights = new uint256[][](2);
        initialWeights[0] = new uint256[](2);
        initialWeights[0][0] = params.baseAssetWeight;
        initialWeights[0][1] = params.sellWeight;
        initialWeights[1] = new uint256[](2);
        initialWeights[1][0] = params.baseAssetWeight;
        initialWeights[1][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        // Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        uint256 deviatedTradeAmount = params.depositAmount.fullMulDiv(1e18 - params.baseAssetWeight - deviation, 1e18);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: deviatedTradeAmount,
            minAmount: deviatedTradeAmount.fullMulDiv(0.995e18, 1e18),
            maxAmount: deviatedTradeAmount.fullMulDiv(1.005e18, 1e18)
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_assetNotInBasket(uint256 sellWeight, uint256 depositAmount) public {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        initialDepositAmounts[1] = params.depositAmount;
        uint256[][] memory initialWeights = new uint256[][](2);
        initialWeights[0] = new uint256[](2);
        initialWeights[0][0] = params.baseAssetWeight;
        initialWeights[0][1] = params.sellWeight;
        initialWeights[1] = new uint256[](2);
        initialWeights[1][0] = params.baseAssetWeight;
        initialWeights[1][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: address(new ERC20Mock()),
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 0.995e18 / 1e18,
            maxAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 1.005e18 / 1e18
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.AssetNotFoundInBasket.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_Paused() public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
    }

    function testFuzz_executeTokenSwap_revertWhen_CallerIsNotRebalancer(
        address caller,
        ExternalTrade[] calldata trades,
        bytes calldata data
    )
        public
    {
        _setTokenSwapAdapter();
        vm.assume(!basketManager.hasRole(REBALANCER_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, REBALANCER_ROLE));
        vm.prank(caller);
        basketManager.executeTokenSwap(trades, data);
    }

    function testFuzz_executeTokenSwap_revertWhen_Paused(ExternalTrade[] calldata trades, bytes calldata data) public {
        _setTokenSwapAdapter();
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(trades, data);
    }

    function testFuzz_proposeTokenSwap_externalTrade_revertWhen_AmountsIncorrect(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 sellAmount
    )
        public
    {
        /// Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);

        /// Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint256[][] memory targetWeights = new uint256[][](2);
        targetWeights[0] = new uint256[](2);
        targetWeights[0][0] = params.baseAssetWeight;
        targetWeights[0][1] = params.sellWeight;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        /// Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        vm.assume(sellAmount > basketManager.basketBalanceOf(baskets[0], rootAsset));
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: sellAmount,
            minAmount: sellAmount.fullMulDiv(0.995e18, 1e18),
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_externalTrade_revertWhen_TargetWeightsNotMet(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 deviation
    )
        public
    {
        /// Setup fuzzing bounds
        uint256 max_weight_deviation = 0.05e18 + 1;
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18 - max_weight_deviation);
        params.depositAmount = bound(depositAmount, 1e18, type(uint256).max) / 1e36;
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        deviation = bound(deviation, max_weight_deviation, params.baseAssetWeight);
        vm.assume(params.baseAssetWeight + deviation < 1e18);
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        /// Setup basket and target weights
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[][] memory weightsPerBasket = new uint256[][](1);
        // Deviate from the target weights
        weightsPerBasket[0] = new uint256[](2);
        weightsPerBasket[0][0] = params.baseAssetWeight;
        weightsPerBasket[0][1] = params.sellWeight;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, weightsPerBasket, initialDepositAmounts);

        /// Propose the rebalance
        vm.prank(rebalancer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        uint256 deviatedTradeAmount = params.depositAmount.fullMulDiv(1e18 - params.baseAssetWeight - deviation, 1e18);
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: deviatedTradeAmount,
            minAmount: deviatedTradeAmount.fullMulDiv(0.995e18, 1e18),
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(rebalancer);
        vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);
    }

    function testFuzz_proRataRedeem(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        redeemAmount = bound(redeemAmount, 1, depositAmount);
        uint256 initialSplit = 5e17;
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, depositAmount);
        address basket = targetBaskets[0];
        // Mimic the fulfillDeposit call and transfer the depositing assets to the basket
        ERC20Mock(rootAsset).mint(address(basketManager), depositAmount * (1e18 - initialSplit) / 1e18 + 1);
        ERC20Mock(pairAsset).mint(address(basketManager), depositAmount * initialSplit / 1e18 + 1);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount));
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets);

        // Redeem some shares
        vm.prank(basket);
        basketManager.proRataRedeem(depositAmount, redeemAmount, address(this));
        assertApproxEqAbs(ERC20Mock(rootAsset).balanceOf(address(this)), redeemAmount * (1e18 - initialSplit) / 1e18, 1);
        assertApproxEqAbs(ERC20Mock(pairAsset).balanceOf(address(this)), redeemAmount * initialSplit / 1e18, 1);
    }

    function test_proRataRedeem_revertWhen_CannotBurnMoreSharesThanTotalSupply(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        uint256 initialSplit = 5e17;
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, depositAmount);
        address basket = targetBaskets[0];
        // Mimic the fulfillDeposit call and transfer the depositing assets to the basket
        ERC20Mock(rootAsset).mint(address(basketManager), depositAmount * (1e18 - initialSplit) / 1e18 + 1);
        ERC20Mock(pairAsset).mint(address(basketManager), depositAmount * initialSplit / 1e18 + 1);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount));
        vm.prank(rebalancer);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets);

        // Redeem some shares
        vm.expectRevert(BasketManagerUtils.CannotBurnMoreSharesThanTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(depositAmount, depositAmount + 1, address(this));
    }

    function test_proRataRedeem_revertWhen_CallerIsNotBasketToken() public {
        vm.expectRevert(_formatAccessControlError(address(this), BASKET_TOKEN_ROLE));
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroTotalSupply() public {
        address basket = _setupBasketAndMocks(10_000);
        vm.expectRevert(BasketManagerUtils.ZeroTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroBurnedShares() public {
        address basket = _setupBasketAndMocks();
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(BasketManagerUtils.ZeroBurnedShares.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 0, address(this));
    }

    function test_proRataRedeem_revertWhen_ZeroAddress() public {
        address basket = _setupBasketAndMocks();
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(0));
    }

    function test_proRataRedeem_revertWhen_MustWaitForRebalanceToComplete() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(this));
    }

    function test_proRataRedeem_revertWhen_Paused() public {
        address basket = _setupBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function testFuzz_setTokenSwapAdapter(address newTokenSwapAdapter) public {
        vm.assume(newTokenSwapAdapter != address(0));
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(newTokenSwapAdapter);
        assertEq(basketManager.tokenSwapAdapter(), newTokenSwapAdapter);
    }

    function test_setTokenSwapAdapter_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(address(0));
    }

    function test_setTokenSwapAdapter_revertWhen_CalledByNonTimelock() public {
        vm.expectRevert(_formatAccessControlError(address(this), TIMELOCK_ROLE));
        vm.prank(address(this));
        basketManager.setTokenSwapAdapter(address(0));
    }

    function testFuzz_setTokenSwapAdapter_revertWhen_MustWaitForRebalanceToComplete(address newSwapAdapter) public {
        vm.assume(newSwapAdapter != address(0));
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManager.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(newSwapAdapter);
    }

    function testFuzz_executeTokenSwap(uint256 sellWeight, uint256 depositAmount) public {
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Mock calls
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));
    }

    function testFuzz_executeTokenSwap_revertWhen_ExecuteTokenSwapFailed(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Mock calls
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCallRevert(
            address(tokenSwapAdapter), abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector), ""
        );
        // Execute
        vm.prank(rebalancer);
        vm.expectRevert(BasketManager.ExecuteTokenSwapFailed.selector);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_ExternalTradesHashMismatch(
        uint256 sellWeight,
        uint256 depositAmount,
        ExternalTrade[] memory badTrades
    )
        public
    {
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);
        vm.assume(keccak256(abi.encode(badTrades)) != keccak256(abi.encode(trades)));

        // Execute
        vm.expectRevert(BasketManager.ExternalTradesHashMismatch.selector);
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(badTrades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_TokenSwapNotProposed(ExternalTrade[] memory trades) public {
        _setTokenSwapAdapter();
        vm.expectRevert(BasketManager.TokenSwapNotProposed.selector);
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_ZeroAddress(uint256 sellWeight, uint256 depositAmount) public {
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Execute
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_setManagementFee(uint16 fee) public {
        vm.assume(fee <= _MAX_MANAGEMENT_FEE);
        vm.prank(timelock);
        basketManager.setManagementFee(fee);
        assertEq(basketManager.managementFee(), fee);
    }

    function testFuzz_setManagementFee_revertsWhen_calledByNonTimelock(address caller) public {
        vm.assume(caller != timelock);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setManagementFee(10);
    }

    function testFuzz_setManagementFee_revertWhen_invalidManagementFee(uint16 fee) public {
        vm.assume(fee > _MAX_MANAGEMENT_FEE);
        vm.expectRevert(BasketManager.InvalidManagementFee.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(fee);
    }

    function testFuzz_setManagementfee_revertWhen_MustWaitForRebalanceToComplete(uint16 fee) public {
        vm.assume(fee <= _MAX_MANAGEMENT_FEE);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(fee);
    }

    /// Internal functions
    function _setTokenSwapAdapter() internal {
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(tokenSwapAdapter);
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint256[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts
    )
        internal
        returns (address[] memory baskets)
    {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));

        uint256 numBaskets = assetsPerBasket.length;
        baskets = new address[](numBaskets);

        for (uint256 i = 0; i < numBaskets; i++) {
            address[] memory assets = assetsPerBasket[i];
            uint256[] memory weights = weightsPerBasket[i];
            address baseAsset = assets[0];
            mockPriceOracle.setPrice(assets[i], baseAsset, 1e18);
            mockPriceOracle.setPrice(baseAsset, assets[i], 1e18);
            bitFlag = bitFlag + i;
            strategy = address(uint160(uint160(strategy) + i));
            vm.mockCall(
                basketTokenImplementation,
                abi.encodeCall(BasketToken.initialize, (IERC20(baseAsset), name, symbol, bitFlag, strategy, admin)),
                new bytes(0)
            );
            vm.mockCall(
                strategyRegistry,
                abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)),
                abi.encode(true)
            );
            vm.mockCall(strategyRegistry, abi.encodeCall(StrategyRegistry.getAssets, (bitFlag)), abi.encode(assets));
            vm.prank(manager);
            baskets[i] = basketManager.createNewBasket(name, symbol, baseAsset, bitFlag, strategy);

            vm.mockCall(
                baskets[i], abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(initialDepositAmounts[i])
            );
            vm.mockCall(baskets[i], abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
            vm.mockCall(baskets[i], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
            vm.mockCall(baskets[i], abi.encodeCall(BasketToken.getTargetWeights, ()), abi.encode(weights));
        }
    }

    function _setupBasketAndMocks() internal returns (address basket) {
        address[][] memory assetsPerBasket = new address[][](1);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        uint256[][] memory weightsPerBasket = new uint256[][](1);
        weightsPerBasket[0] = new uint256[](2);
        weightsPerBasket[0][0] = 0.05e18;
        weightsPerBasket[0][1] = 0.05e18;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = 10_000;
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        basket = baskets[0];
    }

    function _setupBasketAndMocks(uint256 depositAmount) internal returns (address basket) {
        address[][] memory assetsPerBasket = new address[][](1);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        uint256[][] memory weightsPerBasket = new uint256[][](1);
        weightsPerBasket[0] = new uint256[](2);
        weightsPerBasket[0][0] = 0.05e18;
        weightsPerBasket[0][1] = 0.05e18;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = depositAmount;
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        basket = baskets[0];
    }

    function _setPrices(address asset) internal {
        mockPriceOracle.setPrice(asset, USD_ISO_4217_CODE, 1e18);
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, asset, 1e18);
        vm.startPrank(admin);
        eulerRouter.govSetConfig(asset, USD_ISO_4217_CODE, address(mockPriceOracle));
        eulerRouter.govSetConfig(rootAsset, asset, address(mockPriceOracle));
        vm.stopPrank();
    }

    function _proposeAndCompleteExternalTrades(
        address[] memory baskets,
        uint256 depositAmount,
        uint256 sellWeight,
        uint256 tradeSuccess
    )
        internal
    {
        address basket = baskets[0];
        // Setup the trade and propose token swap
        TradeTestParams memory params;
        params.pairAsset = pairAsset;
        params.sellWeight = sellWeight;
        params.depositAmount = depositAmount;
        params.baseAssetWeight = 1e18 - params.sellWeight;
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets);

        // Mock calls for executeTokenSwap
        uint256 numTrades = externalTrades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(externalTrades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(rebalancer);
        basketManager.executeTokenSwap(externalTrades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.prepareForRebalance, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(params.depositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // tradeSuccess => 1e18 for a 100% successful trade, 0 for 100% unsuccesful trade
        // 0 in the 1st place is the result of a 100% successful trade
        // 0 in the 0th place is the result of a 100% un-successful trade
        claimedAmounts[0] = [
            (params.depositAmount * params.baseAssetWeight / 1e18) * (1e18 - tradeSuccess),
            (params.depositAmount * sellWeight / 1e18) * tradeSuccess
        ];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.prank(rebalancer);
        basketManager.completeRebalance(externalTrades, baskets);
        // When target weights are not met the status returns to REBALANCE_PROPOSED to allow additional token swaps
        // to be proposed
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { console } from "forge-std/console.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";
import { MockTarget } from "test/utils/mocks/MockTarget.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

contract BasketManagerTest is BaseTest {
    using FixedPointMathLib for uint256;

    BasketManager public basketManager;
    MockPriceOracle public mockPriceOracle;
    EulerRouter public eulerRouter;
    address public alice;
    address public admin;
    address public feeCollector;
    address public protocolTreasury;
    address public manager;
    address public timelock;
    address public rebalanceProposer;
    address public tokenswapProposer;
    address public tokenswapExecutor;
    address public pauser;
    address public rootAsset;
    address public pairAsset;
    address public basketTokenImplementation;
    address public strategyRegistry;
    address public tokenSwapAdapter;
    address public assetRegistry;
    address public mockTarget;

    uint64[][] private _targetWeights;

    address public constant USD_ISO_4217_CODE = address(840);

    struct TradeTestParams {
        uint256 sellWeight;
        uint256 depositAmount;
        uint256 baseAssetWeight;
        address pairAsset;
    }

    function setUp() public override {
        super.setUp();
        vm.warp(1 weeks);
        alice = createUser("alice");
        admin = createUser("admin");
        timelock = createUser("timelock");
        feeCollector = createUser("feeCollector");
        protocolTreasury = createUser("protocolTreasury");
        vm.mockCall(
            feeCollector, abi.encodeWithSelector(bytes4(keccak256("protocolTreasury()"))), abi.encode(protocolTreasury)
        );
        pauser = createUser("pauser");
        manager = createUser("manager");
        rebalanceProposer = createUser("rebalanceProposer");
        tokenswapProposer = createUser("tokenswapProposer");
        tokenswapExecutor = createUser("tokenswapExecutor");

        tokenSwapAdapter = createUser("tokenSwapAdapter");
        assetRegistry = createUser("assetRegistry");
        rootAsset = address(new ERC20Mock());
        vm.label(rootAsset, "rootAsset");
        pairAsset = address(new ERC20Mock());
        vm.label(pairAsset, "pairAsset");
        basketTokenImplementation = createUser("basketTokenImplementation");
        mockPriceOracle = new MockPriceOracle();
        mockTarget = address(new MockTarget());
        eulerRouter = new EulerRouter(EVC, admin);
        strategyRegistry = createUser("strategyRegistry");
        basketManager = new BasketManager(
            basketTokenImplementation, address(eulerRouter), strategyRegistry, assetRegistry, admin, feeCollector
        );
        // Admin actions
        vm.startPrank(admin);
        mockPriceOracle.setPrice(rootAsset, USD_ISO_4217_CODE, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(pairAsset, USD_ISO_4217_CODE, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, rootAsset, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, pairAsset, 1e18); // set price to 1e18
        eulerRouter.govSetConfig(rootAsset, USD_ISO_4217_CODE, address(mockPriceOracle));
        eulerRouter.govSetConfig(pairAsset, USD_ISO_4217_CODE, address(mockPriceOracle));
        basketManager.grantRole(MANAGER_ROLE, manager);
        basketManager.grantRole(REBALANCE_PROPOSER_ROLE, rebalanceProposer);
        basketManager.grantRole(TOKENSWAP_PROPOSER_ROLE, tokenswapProposer);
        basketManager.grantRole(TOKENSWAP_EXECUTOR_ROLE, tokenswapExecutor);
        basketManager.grantRole(PAUSER_ROLE, pauser);
        basketManager.grantRole(TIMELOCK_ROLE, timelock);
        basketManager.grantRole(PAUSER_ROLE, pauser);
        vm.stopPrank();
        vm.label(address(basketManager), "basketManager");

        vm.mockCall(
            assetRegistry,
            abi.encodeWithSelector(AssetRegistry.getAssetStatus.selector, mockTarget),
            abi.encode(AssetRegistry.AssetStatus.DISABLED)
        );
    }

    function testFuzz_constructor(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address assetRegistry_,
        address admin_,
        address feeCollector_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(eulerRouter_ != address(0));
        vm.assume(strategyRegistry_ != address(0));
        vm.assume(admin_ != address(0));
        vm.assume(feeCollector_ != address(0));
        vm.assume(assetRegistry_ != address(0));
        BasketManager bm = new BasketManager(
            basketTokenImplementation_, eulerRouter_, strategyRegistry_, assetRegistry_, admin_, feeCollector_
        );
        assertEq(address(bm.eulerRouter()), eulerRouter_);
        assertEq(address(bm.strategyRegistry()), strategyRegistry_);
        assertEq(address(bm.assetRegistry()), assetRegistry_);
        assertEq(address(bm.feeCollector()), feeCollector_);
        assertEq(bm.hasRole(DEFAULT_ADMIN_ROLE, admin_), true);
        assertEq(bm.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
    }

    /// forge-config: default.fuzz.runs = 2048
    function testFuzz_constructor_revertWhen_ZeroAddress(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address assetRegistry_,
        address admin_,
        address feeCollector_,
        uint256 flag
    )
        public
    {
        // Use flag to determine which address to set to zero
        vm.assume(flag <= 2 ** 6 - 2);
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
        if (flag & 32 == 0) {
            assetRegistry_ = address(0);
        }

        vm.expectRevert(BasketManager.ZeroAddress.selector);
        new BasketManager(
            basketTokenImplementation_, eulerRouter_, strategyRegistry_, assetRegistry_, admin_, feeCollector_
        );
    }

    function test_unpause() public {
        vm.prank(pauser);
        basketManager.pause();
        assertTrue(basketManager.paused(), "contract not paused");
        vm.prank(admin);
        basketManager.unpause();
        assertFalse(basketManager.paused(), "contract not unpaused");
    }

    function test_pause_revertWhen_notPaused() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.Unauthorized.selector));
        basketManager.pause();
    }

    function test_unpause_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), DEFAULT_ADMIN_ROLE));
        basketManager.unpause();
    }

    function test_execute() public {
        vm.prank(timelock);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(protocolTreasury), 100e18);
        basketManager.execute{ value: 1 ether }(mockTarget, data, 1 ether);
        assertEq(MockTarget(payable(mockTarget)).value(), 1 ether, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), data, "execute failed");
    }

    function test_execute_passWhen_zeroValue() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(protocolTreasury), 100e18);
        vm.prank(timelock);
        basketManager.execute{ value: 0 }(mockTarget, data, 0);
        assertEq(MockTarget(payable(mockTarget)).value(), 0, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), data, "execute failed");
    }

    function testFuzz_execute(bytes4 selector, bytes32 data, address data2, uint256 value) public {
        vm.assume(selector != MockTarget.fail.selector);
        bytes memory fullData = abi.encodeWithSelector(selector, data, data2);
        assertEq(fullData.length, 68, "data packing failed");
        hoax(timelock, value);
        basketManager.execute{ value: value }(mockTarget, fullData, value);
        assertEq(MockTarget(payable(mockTarget)).value(), value, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), fullData, "execute failed");
    }

    function test_execute_revertWhen_executionFailed() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.fail.selector);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ExecutionFailed.selector));
        vm.prank(timelock);
        basketManager.execute{ value: 1 ether }(mockTarget, data, 1 ether);
    }

    function test_execute_revertWhen_callerIsNotTimelock() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(protocolTreasury), 100e18);
        vm.expectRevert(_formatAccessControlError(admin, TIMELOCK_ROLE));
        vm.prank(admin);
        basketManager.execute{ value: 1 ether }(mockTarget, data, 1 ether);
    }

    function test_execute_revertWhen_zeroAddress() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(protocolTreasury), 100e18);
        vm.expectRevert(BasketManager.ZeroAddress.selector);
        vm.prank(timelock);
        basketManager.execute{ value: 1 ether }(address(0), data, 1 ether);
    }

    function test_execute_revertWhen_AssetExistsInUniverse() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(protocolTreasury), 100e18);
        vm.mockCall(
            assetRegistry,
            abi.encodeWithSelector(AssetRegistry.getAssetStatus.selector, mockTarget),
            abi.encode(AssetRegistry.AssetStatus.ENABLED)
        );
        vm.expectRevert(BasketManager.AssetExistsInUniverse.selector);
        vm.prank(timelock);
        basketManager.execute{ value: 1 ether }(mockTarget, data, 1 ether);
    }

    function test_rescue() public {
        ERC20 shitcoin = new ERC20Mock();
        deal(address(shitcoin), address(basketManager), 1e18);
        vm.mockCall(
            assetRegistry,
            abi.encodeWithSelector(AssetRegistry.getAssetStatus.selector, address(shitcoin)),
            abi.encode(AssetRegistry.AssetStatus.DISABLED)
        );
        vm.prank(admin);
        basketManager.rescue(IERC20(address(shitcoin)), alice, 1e18);
        assertEq(shitcoin.balanceOf(alice), 1e18, "rescue failed");
    }

    function test_rescue_ETH() public {
        deal(address(basketManager), 1e18);
        vm.mockCall(
            assetRegistry,
            abi.encodeWithSelector(AssetRegistry.getAssetStatus.selector, address(0)),
            abi.encode(AssetRegistry.AssetStatus.DISABLED)
        );
        vm.prank(admin);
        basketManager.rescue(IERC20(address(0)), alice, 1e18);
        // createUser deals new addresses 100 ETH
        assertEq(alice.balance, 100 ether + 1e18, "rescue failed");
    }

    function test_rescue_revertWhen_notAdmin() public {
        vm.prank(alice);
        vm.expectRevert(_formatAccessControlError(address(alice), DEFAULT_ADMIN_ROLE));
        basketManager.rescue(IERC20(address(0)), admin, 1e18);
    }

    function test_rescue_revertWhen_assetNotDisabled() public {
        ERC20 shitcoin = new ERC20Mock();
        deal(address(shitcoin), address(basketManager), 1e18);
        vm.mockCall(
            assetRegistry,
            abi.encodeWithSelector(AssetRegistry.getAssetStatus.selector, address(shitcoin)),
            abi.encode(AssetRegistry.AssetStatus.ENABLED)
        );
        vm.expectRevert(BasketManager.AssetExistsInUniverse.selector);
        vm.prank(admin);
        basketManager.rescue(IERC20(address(shitcoin)), alice, 1e18);
    }

    function testFuzz_createNewBasket(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        // Set the default management fee
        vm.prank(timelock);
        basketManager.setManagementFee(address(0), 3000);
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));

        // Predict the address of the clone using vm.computeAddress
        address predictedBasket = vm.computeCreateAddress(address(basketManager), vm.getNonce(address(basketManager)));
        vm.expectEmit();
        emit BasketManager.BasketCreated(predictedBasket, name, symbol, rootAsset, bitFlag, strategy);

        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, address(rootAsset), bitFlag, strategy);
        assertEq(basketManager.numOfBasketTokens(), 1);
        address[] memory tokens = basketManager.basketTokens();
        assertEq(tokens[0], basket);
        assertEq(basketManager.basketIdToAddress(keccak256(abi.encodePacked(bitFlag, strategy))), basket);
        assertEq(basketManager.getAssetIndexInBasket(basket, address(rootAsset)), 0);
        assertEq(basketManager.basketTokenToIndex(basket), 0);
        assertEq(basketManager.basketAssets(basket), assets);
        assertEq(basketManager.managementFee(basket), 3000);
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
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.getAssets.selector), abi.encode(assets));
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            bitFlag += 1;
            strategy = address(uint160(strategy) + 1);
            vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
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
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
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
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
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
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.AssetListEmpty.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_HasPausedAssets() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(true));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.AssetNotEnabled.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_passesWhen_BaseAssetNotFirst() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address wrongAsset = address(new ERC20Mock());
        address[] memory assets = new address[](2);
        assets[0] = wrongAsset;
        assets[1] = rootAsset;

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_baseAssetNotIncluded(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = pairAsset;
        // Set the default management fee
        vm.prank(timelock);
        basketManager.setManagementFee(address(0), 3000);
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        // Mock the call to getAssets to not include base asset
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.BaseAssetMismatch.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, address(rootAsset), bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_BaseAssetIsZeroAddress() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.prank(manager);
        vm.expectRevert(BasketManager.ZeroAddress.selector);
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
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.getAssets.selector), abi.encode(assets));
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
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.getAssets.selector), abi.encode(assets));
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, address(uint160(i)));
            vm.assume(baskets[i] != basket);
        }

        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(basket);
    }

    function test_proposeRebalance_processesDeposits() public returns (address basket) {
        basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(basketManager.rebalanceStatus().proposalTimestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.rebalanceStatus().basketMask, 1);
        assertEq(
            basketManager.rebalanceStatus().basketHash,
            keccak256(abi.encode(targetBaskets, _targetWeights, basketAssets))
        );
    }

    function testFuzz_proposeRebalance_processDeposits_passesWhen_targetBalancesMet(uint256 initialDepositAmount)
        public
    {
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        address[][] memory assetsPerBasket = new address[][](1);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        uint64[][] memory weightsPerBasket = new uint64[][](1);
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = 1e18;
        weightsPerBasket[0][1] = 0;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = initialDepositAmount;
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        address[][] memory basketAssets = _getBasketAssets(baskets);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(
            basketManager.rebalanceStatus().basketHash, keccak256(abi.encode(baskets, weightsPerBasket, basketAssets))
        );
    }

    function test_proposeRebalance_revertWhen_HasPausedAssets() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (1)), abi.encode(true));
        vm.expectRevert(BasketManagerUtils.AssetNotEnabled.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_MustWaitForRebalanceToComplete() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.startPrank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_BasketTokenNotFound(address fakeBasket) public {
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = fakeBasket;
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_CallerIsNotRebalancer(address caller) public {
        vm.assume(!basketManager.hasRole(REBALANCE_PROPOSER_ROLE, caller));
        address[] memory targetBaskets = new address[](1);
        vm.expectRevert(_formatAccessControlError(caller, REBALANCE_PROPOSER_ROLE));
        vm.prank(caller);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_ZeroTotalSupply() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;

        // Mock total supply to be 0
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 0));

        vm.expectRevert(BasketManagerUtils.ZeroTotalSupply.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_processesDeposits_revertWhen_paused() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertsWhen_tooEarlyToProposeRebalance() public {
        address basket = testFuzz_completeRebalance_externalTrade(1e18, 5e18);
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.expectRevert(BasketManagerUtils.TooEarlyToProposeRebalance.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_completeRebalance_passWhen_redeemingShares(uint16 fee) public {
        uint256 intialDepositAmount = 10_000;
        uint256 initialSplit = 5e17; // 50 / 50 between both baskets
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, intialDepositAmount, fee);
        address basket = targetBaskets[0];
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(
            basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(intialDepositAmount, 0)
        );
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectEmit();
        emit BasketManagerUtils.RebalanceCompleted(basketManager.rebalanceStatus().epoch);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);

        vm.warp(vm.getBlockTimestamp() + 1 weeks + 1);
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 10_000));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.mockCall(
            targetBaskets[1], abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 10_000)
        );
        vm.mockCall(targetBaskets[1], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);
    }

    function testFuzz_completeRebalance_externalTrade(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
        returns (address basket)
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 0, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        basket = targetBaskets[0];

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
        vm.expectEmit();
        emit BasketManager.TokenSwapExecuted(basketManager.rebalanceStatus().epoch, trades);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1 index is the result of a 100% successful trade
        claimedAmounts[0] = [0, initialDepositAmount * sellWeight / 1e18];
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.expectEmit();
        emit BasketManagerUtils.RebalanceCompleted(basketManager.rebalanceStatus().epoch);
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights, basketAssets);
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
        vm.expectEmit();
        emit BasketManager.TokenSwapExecuted(basketManager.rebalanceStatus().epoch, trades);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1 index is the result of a 100% un-successful trade
        claimedAmounts[0] = [initialDepositAmount * sellWeight / 1e18, 0];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        assertEq(basketManager.retryCount(), uint256(0));
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights, basketAssets);
        // When target weights are not met the status returns to REBALANCE_PROPOSED to allow additional token swaps to
        // be proposed
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.retryCount(), uint256(1));
    }

    function testFuzz_completeRebalance_passesWhen_retryLimitReached(
        uint256 initialDepositAmount,
        uint256 pairAssetWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        pairAssetWeight = bound(pairAssetWeight, 1e17, 1e18);
        uint256 baseAssetWeight = 1e18 - pairAssetWeight;

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = initialDepositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(baseAssetWeight);
        targetWeights[0][1] = uint64(pairAssetWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        uint256 sellAmount = initialDepositAmount * pairAssetWeight / 1e18;
        uint256 retryLimit = basketManager.retryLimit();

        for (uint8 i = 0; i < retryLimit; i++) {
            // 0 for the last input will guarantee the trade will be 100% unsuccessful
            _swapFirstBasketRootAssetToPairAsset(baskets, targetWeights, sellAmount, 0);
            assertEq(basketManager.retryCount(), uint256(i + 1));
            assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(basketManager.retryCount(), retryLimit);

        // We have reached max retries, if the next proposed token swap does not meet target weights the rebalance
        // will completed with the current balances.
        _swapFirstBasketRootAssetToPairAsset(baskets, targetWeights, sellAmount, 0);
        assertEq(basketManager.retryCount(), uint256(0));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_fulfillsRedeems(
        uint256 depositAmount,
        uint64 pairAssetWeight,
        uint256 redeemingShares
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        depositAmount = bound(depositAmount, 1e18, type(uint256).max / 1e54);

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(1e18);
        targetWeights[0][1] = uint64(0);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        address basket = baskets[0];
        BasketManager bm = basketManager;
        // Propose the rebalance and process the deposits
        vm.prank(rebalanceProposer);
        bm.proposeRebalance(baskets);

        // Assume the basket token total supply was increased by the deposit
        vm.mockCall(basket, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(depositAmount));

        // Complete the rebalance
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        bm.completeRebalance(new ExternalTrade[](0), baskets, targetWeights, basketAssets);
        vm.warp(vm.getBlockTimestamp() + 60 minutes);

        // Update target weights
        pairAssetWeight = uint64(bound(pairAssetWeight, 5e17, 1e18));
        targetWeights[0][0] = 1e18 - pairAssetWeight;
        targetWeights[0][1] = pairAssetWeight;
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.getTargetWeights.selector), abi.encode(targetWeights[0]));

        // Mock a pending redemption between 10% and 90% of the total deposit amount.
        // This range ensures:
        // 1. Redemption is large enough to meaningfully test redemption logic (>10%)
        // 2. Remaining shares are sufficient to test rebalancing (>10%)
        // 3. Avoids edge cases like complete withdrawals which could mask rebalancing issues
        // Note: Using max redemption would make completeRebalance succeed incorrectly by
        // withdrawing everything, rather than properly testing the rebalancing logic we want to test which is
        // verifying that the basket can properly rebalance its remaining assets while handling redemptions
        redeemingShares = bound(redeemingShares, depositAmount / 10, depositAmount * 9 / 10);
        vm.mockCall(
            basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, redeemingShares)
        );

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        bm.proposeRebalance(baskets);

        // Calculate the amount of rootAsset to sell:
        // 1. Take 90% of deposit (depositAmount * 9/10) to account for 10% redemption
        // 2. Multiply by target weight of pairAsset to determine how much needs to be swapped
        // 3. Divide by 1e18 to normalize the fixed-point arithmetic
        uint256 sellAmount = (depositAmount - redeemingShares) * pairAssetWeight / 1e18;
        uint256 retryLimit = bm.retryLimit();

        for (uint8 i = 0; i < retryLimit; i++) {
            // The last parameter (0) represents the percentage of tokens successfully traded, in 1e18 precision (0 =
            // 0%, 1e18 = 100%)
            _swapFirstBasketRootAssetToPairAsset(baskets, targetWeights, sellAmount, 0);
            assertEq(bm.retryCount(), uint256(i + 1));
            assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(bm.retryCount(), retryLimit);

        // We have reached max retries, even if the next proposed token swap does not meet target weights, the rebalance
        // will terminate.
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: pairAsset,
            sellAmount: sellAmount,
            // Calculate minAmount based on reduced sellAmount with 0.5% slippage
            // Assumes 1:1 exchange rate. TODO: write additional tests with fuzzed prices
            minAmount: sellAmount * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        bm.proposeTokenSwap(new InternalTrade[](0), externalTrades, baskets, targetWeights, basketAssets);

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
        vm.prank(tokenswapExecutor);
        bm.executeTokenSwap(externalTrades, "");

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes);

        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // tradeSuccess => 1e18 for a 100% successful trade, 0 for 100% unsuccessful trade
        // 0 in the 0th place is the result of a 100% un-successful trade
        // 0 in the 1st place is the result of a 100% successful trade
        // We mock a partially successful trade so that target weights are not met and but enough tokens are available
        // to meet pending redemptions
        // TODO: write additional tests with fuzzed prices, currently assumes 1:1 exchange rate
        uint256 successfulSellAmount = sellAmount * 7e17 / 1e18;
        uint256 successfulBuyAmount = successfulSellAmount;
        claimedAmounts[0] = [sellAmount - successfulSellAmount, successfulBuyAmount];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );

        // Check that fulfillRedeem will be called for our desired shares.
        vm.expectCall(basket, abi.encodeCall(BasketToken.fulfillRedeem, redeemingShares));
        bm.completeRebalance(externalTrades, baskets, targetWeights, basketAssets);
        assertEq(bm.retryCount(), uint256(0));
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_calls_fallbackRedeemTrigger_onFailure(
        uint256 depositAmount,
        uint64 pairAssetWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        depositAmount = bound(depositAmount, 1e18, type(uint256).max / 1e54);
        pairAssetWeight = uint64(bound(pairAssetWeight, 1e17, 1e18));
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(1e18 - pairAssetWeight);
        targetWeights[0][1] = uint64(pairAssetWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        address basket = baskets[0];

        // Process deposits
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Assume the basket token total supply was increased by the deposit, assuming rootAsset has price of 1
        vm.mockCall(basket, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(depositAmount));

        // Swap rootAsset to pairAsset based on target weight difference
        _swapFirstBasketRootAssetToPairAsset(
            baskets, targetWeights, depositAmount * (1e18 - targetWeights[0][0]) / 1e18, 1e18
        );

        // Mock a redemption of all of the shares
        vm.mockCall(
            basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, depositAmount)
        );

        // Propose a new rebalance
        vm.warp(vm.getBlockTimestamp() + 60 minutes);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        uint256 retryLimit = basketManager.retryLimit();

        // Fail the rebalance by not meeting target weights
        for (uint8 i = 0; i < retryLimit; i++) {
            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            basketManager.completeRebalance(new ExternalTrade[](0), baskets, targetWeights, basketAssets);

            assertEq(basketManager.retryCount(), uint256(i + 1));
            assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        // Check we reached the configured max retries
        assertEq(basketManager.retryCount(), uint256(basketManager.retryLimit()));

        // Call completeRebalance to get out of the retry loop
        vm.warp(vm.getBlockTimestamp() + 60 minutes);
        vm.expectCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector, uint256(0)));
        basketManager.completeRebalance(new ExternalTrade[](0), baskets, targetWeights, basketAssets);

        // Check the retry count has been reset and we are back to NOT_STARTED status
        assertEq(basketManager.retryCount(), uint256(0));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function test_completeRebalance_revertWhen_NoRebalanceInProgress() public {
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
        vm.expectRevert(BasketManagerUtils.NoRebalanceInProgress.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), new address[](0), new uint64[][](0), new address[][](0));
    }

    function test_completeRebalance_revertWhen_BasketsMismatch() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        uint64[][] memory targetWeights = new uint64[][](1);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), new address[](0), targetWeights, basketAssets);
    }

    function test_completeRebalance_retriesWhen_TimeoutAfterProposeRebalance() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);
        uint256 retryCount = basketManager.retryCount();
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);

        // Confirm the rebalance status has been reset with a retry count increased
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.retryCount(), retryCount + 1);
    }

    function test_completeRebalance_revertWhen_TargetWeightsMismatch() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, new uint64[][](0), basketAssets);
    }

    function test_completeRebalance_revertWhen_TooEarlyToCompleteRebalance() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

        vm.expectRevert(BasketManagerUtils.TooEarlyToCompleteRebalance.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);
    }

    function test_completeRebalance_revertWhen_paused() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 10_000));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);
    }

    function testFuzz_completeRebalance_revertWhen_ExternalTradeMismatch(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 0, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

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
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 0 index is the result of a 100% successful trade
        claimedAmounts[0] = [0, initialDepositAmount * sellWeight / 1e18];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.expectRevert(BasketManagerUtils.ExternalTradeMismatch.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);
    }

    function testFuzz_completeRebalance_retriesWhen_TokenSwapNotExecuted(
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
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights, basketAssets);
        assertEq(basketManager.retryCount(), 1);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
    }

    function testFuzz_completeRebalance_passesWhen_TokenSwapNotExecuted_retryLimitReached(
        uint256 initialDepositAmount,
        uint256 pairAssetWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        pairAssetWeight = bound(pairAssetWeight, 1e17, 1e18);

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;

        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = initialDepositAmount;

        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(1e18 - pairAssetWeight);
        targetWeights[0][1] = uint64(pairAssetWeight);

        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        uint256 sellAmount = initialDepositAmount * pairAssetWeight / 1e18;
        uint256 retryLimit = basketManager.retryLimit();

        for (uint8 i = 0; i < retryLimit; i++) {
            // 0 for the last input will guarantee the trade will be 100% unsuccessful
            _swapFirstBasketRootAssetToPairAsset(baskets, targetWeights, sellAmount, 0);
            assertEq(basketManager.retryCount(), uint256(i + 1));
            assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(basketManager.retryCount(), retryLimit);

        // We have reached max retries, if the next proposed token swap does not execute the rebalance
        // will successfully complete.
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: pairAsset,
            sellAmount: sellAmount,
            minAmount: sellAmount * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, targetWeights, basketAssets);
        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        // Token swaps have not been executed
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        uint256 rootAssetBasketBalance = basketManager.basketBalanceOf(baskets[0], rootAsset);
        uint256 pairAssetBasketBalance = basketManager.basketBalanceOf(baskets[0], pairAsset);

        // Complete the rebalance without executing the token swaps
        basketManager.completeRebalance(externalTrades, baskets, _targetWeights, basketAssets);
        assertEq(basketManager.retryCount(), uint256(0));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));

        // Verify basket balances remain unchanged after completing rebalance without executing swaps
        assertEq(basketManager.basketBalanceOf(baskets[0], rootAsset), rootAssetBasketBalance);
        assertEq(basketManager.basketBalanceOf(baskets[0], pairAsset), pairAssetBasketBalance);
    }

    function testFuzz_completeRebalance_revertWhen_completeTokenSwapFailed(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 0, 1e18);
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
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1st position is the result of a 100% successful trade
        claimedAmounts[0] = [initialDepositAmount * sellWeight / 1e18, 0];
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);
        vm.mockCallRevert(
            address(tokenSwapAdapter), abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector), ""
        );
        vm.expectRevert(BasketManagerUtils.CompleteTokenSwapFailed.selector);
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights, basketAssets);
    }

    // solhint-disable-next-line code-complexity
    function test_completeRebalance_withMultipleAssets() public {
        _setTokenSwapAdapter();
        // Setup baskets with 4 assets each
        address[][] memory basketAssets = new address[][](2);
        address thirdAsset = address(new ERC20Mock());
        address fourthAsset = address(new ERC20Mock());
        for (uint256 i = 0; i < 2; i++) {
            basketAssets[i] = new address[](4);
            basketAssets[i][0] = rootAsset;
            basketAssets[i][1] = pairAsset;
            basketAssets[i][2] = thirdAsset;
            basketAssets[i][3] = fourthAsset;
        }

        // Set prices for the 2 new ERC20Mock assets
        vm.startPrank(admin);
        for (uint256 i = 0; i < 2; i++) {
            mockPriceOracle.setPrice(basketAssets[i][2], USD_ISO_4217_CODE, 1e18); // new asset 1
            mockPriceOracle.setPrice(basketAssets[i][3], USD_ISO_4217_CODE, 1e18); // new asset 2
            mockPriceOracle.setPrice(USD_ISO_4217_CODE, basketAssets[i][2], 1e18);
            mockPriceOracle.setPrice(USD_ISO_4217_CODE, basketAssets[i][3], 1e18);
            eulerRouter.govSetConfig(basketAssets[i][2], USD_ISO_4217_CODE, address(mockPriceOracle));
            eulerRouter.govSetConfig(basketAssets[i][3], USD_ISO_4217_CODE, address(mockPriceOracle));
        }
        vm.stopPrank();

        // Setup target weights for each basket (must sum to 1e18)
        uint64[][] memory targetWeights = new uint64[][](2);
        for (uint256 i = 0; i < 2; i++) {
            targetWeights[i] = new uint64[](4);
            targetWeights[i][0] = 0.4e18;
            targetWeights[i][1] = 0.3e18;
            targetWeights[i][2] = 0.2e18;
            targetWeights[i][3] = 0.1e18;
        }

        // Setup initial deposit amounts for each basket
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = 1000e18;
        initialDepositAmounts[1] = 3000e18;
        uint256 totalDepositAmount = 0;
        for (uint256 i = 0; i < initialDepositAmounts.length; i++) {
            totalDepositAmount += initialDepositAmounts[i];
        }

        // Create baskets and setup mocks
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Increase total supply of each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            vm.mockCall(
                baskets[i], abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(initialDepositAmounts[i])
            );
        }

        // Verify rebalance status
        RebalanceStatus memory status = basketManager.rebalanceStatus();

        assertEq(uint8(status.status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(status.timestamp, block.timestamp);
        assertEq(status.proposalTimestamp, block.timestamp);
        assertEq(status.epoch, 0);
        assertEq(status.retryCount, 0);
        assertEq(status.basketHash, keccak256(abi.encode(baskets, targetWeights, basketAssets)));
        assertEq(status.basketMask, 3); // Binary 11 for two baskets

        // Propose token swap
        vm.prank(tokenswapProposer);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](3);

        // Setup external trades to achieve target weights
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](2);
        for (uint256 i = 0; i < tradeOwnerships.length; i++) {
            tradeOwnerships[i] = BasketTradeOwnership({
                basket: baskets[i],
                tradeOwnership: uint64(initialDepositAmounts[i] * 1e18 / totalDepositAmount)
            });
        }
        for (uint256 i = 0; i < 3; i++) {
            uint256 sellAmount = totalDepositAmount * targetWeights[0][i + 1] / 1e18;
            externalTrades[i] = ExternalTrade({
                sellToken: basketAssets[0][0],
                buyToken: basketAssets[0][i + 1],
                sellAmount: sellAmount,
                minAmount: sellAmount * 99 / 100, // 1% slippage
                basketTradeOwnership: tradeOwnerships
            });
        }

        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, targetWeights, basketAssets);

        // Verify token swap status
        status = basketManager.rebalanceStatus();
        assertEq(uint8(status.status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(status.timestamp, block.timestamp);
        assertEq(status.epoch, 0);
        assertEq(status.retryCount, 0);
        assertEq(status.basketHash, keccak256(abi.encode(baskets, targetWeights, basketAssets)));
        assertEq(status.basketMask, 3);
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));

        // Mock successful token swap execution
        vm.mockCall(
            tokenSwapAdapter, abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector), abi.encode(true)
        );

        // Execute token swap
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(externalTrades, "");

        // Verify token swap execution status
        status = basketManager.rebalanceStatus();
        assertEq(uint8(status.status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](externalTrades.length);
        // TODO: Test additional cases where price is not 1:1
        for (uint256 i = 0; i < externalTrades.length; i++) {
            uint256 sellAmount = externalTrades[i].sellAmount;
            uint256 buyAmount = sellAmount; // Assumes 1:1 price ratio
            claimedAmounts[i] = [0, buyAmount]; // First element 0 means no sellToken is claimed back, indicating
                // successful trade
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );

        // Read balances before completeRebalance and verify initial state
        for (uint256 i = 0; i < baskets.length; i++) {
            for (uint256 j = 0; j < basketAssets[i].length; j++) {
                uint256 balancesBefore = basketManager.basketBalanceOf(baskets[i], basketAssets[i][j]);
                if (basketAssets[i][j] == rootAsset) {
                    assertEq(
                        balancesBefore,
                        initialDepositAmounts[i],
                        "Root asset balance should match initial deposit amount"
                    );
                } else {
                    assertEq(balancesBefore, 0, "Non-root assets should have 0 balance");
                }
            }
        }

        // Complete rebalance
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        vm.prank(rebalanceProposer);
        basketManager.completeRebalance(externalTrades, baskets, targetWeights, basketAssets);

        // Verify final rebalance status
        status = basketManager.rebalanceStatus();
        assertEq(uint8(status.status), uint8(Status.NOT_STARTED));
        assertEq(status.timestamp, vm.getBlockTimestamp());
        assertEq(status.proposalTimestamp, 0);
        assertEq(status.epoch, 1);
        assertEq(status.retryCount, 0);
        assertEq(status.basketHash, bytes32(0));
        assertEq(status.basketMask, 0);
        assertEq(basketManager.externalTradesHash(), bytes32(0));

        // Verify final balances match target weights
        for (uint256 i = 0; i < baskets.length; i++) {
            for (uint256 j = 0; j < basketAssets[i].length; j++) {
                uint256 finalBalance = basketManager.basketBalanceOf(baskets[i], basketAssets[i][j]);
                uint256 expectedBalance = initialDepositAmounts[i] * targetWeights[i][j] / 1e18;
                assertEq(finalBalance, expectedBalance, "Final balance should match expected balance");
            }
        }

        // Redeem all existing base asset from the first basket
        uint256 redeemAmount = 400e18;
        vm.mockCall(
            baskets[0], abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, redeemAmount)
        );

        address[] memory redeemBaskets = new address[](1);
        redeemBaskets[0] = baskets[0];
        uint64[][] memory redeemTargetWeights = new uint64[][](1);
        redeemTargetWeights[0] = targetWeights[0];
        address[][] memory redeemBasketAssets = new address[][](1);
        redeemBasketAssets[0] = basketAssets[0];

        vm.warp(vm.getBlockTimestamp() + 60 minutes);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(redeemBaskets);

        // Do not trade anything and intentionally enter retry loop
        uint256 retryLimit = basketManager.retryLimit();
        uint40 epoch = basketManager.rebalanceStatus().epoch;
        for (uint256 i = 0; i < retryLimit; i++) {
            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            vm.expectEmit();
            emit BasketManagerUtils.RebalanceRetried(epoch, i + 1);
            basketManager.completeRebalance(
                new ExternalTrade[](0), redeemBaskets, redeemTargetWeights, redeemBasketAssets
            );
        }

        // Since the retries all failed, the next complete rebalance will process redeems if it can and exit the
        // rebalancing status
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        vm.expectCall(baskets[0], abi.encodeCall(BasketToken.fulfillRedeem, (redeemAmount)));
        vm.expectEmit();
        emit BasketManagerUtils.RebalanceCompleted(epoch);
        basketManager.completeRebalance(new ExternalTrade[](0), redeemBaskets, redeemTargetWeights, redeemBasketAssets);

        // Check the base asset balance was reduced
        assertEq(
            basketManager.basketBalanceOf(baskets[0], rootAsset),
            0,
            "Base asset balance should be reduced by redeem amount"
        );
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
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
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
        vm.expectEmit();
        emit BasketManager.TokenSwapProposed(basketManager.rebalanceStatus().epoch, internalTrades, externalTrades);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);

        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(vm.getBlockTimestamp()));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));
        return (externalTrades, baskets);
    }

    function test_proposeTokenSwap_externalTrade_multipleBaskets() public {
        TradeTestParams memory params;
        params.depositAmount = 77;
        // New dummy asset for new basket
        address dummyAsset = address(new ERC20Mock());
        // vm.startPrank(admin);
        _setPrices(dummyAsset);
        _setTokenSwapAdapter();

        // Setup basket and target weights
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](3);
        basketAssets[1][0] = rootAsset;
        basketAssets[1][1] = params.pairAsset;
        basketAssets[1][2] = dummyAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        // 2nd basket will have smaller deposit amount to force calculation in external trade ownership
        uint256 depositAmount2 = 33;
        initialDepositAmounts[1] = depositAmount2;
        // Setup target weights to force trades into pair asset
        uint64[][] memory targetWeights = new uint64[][](2);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = 0;
        targetWeights[0][1] = uint64(1e18);
        targetWeights[1] = new uint64[](3);
        targetWeights[1][0] = 0;
        targetWeights[1][1] = uint64(1e18);
        targetWeights[1][2] = 0;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](2);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(0.7e18) });
        tradeOwnerships[1] = BasketTradeOwnership({ basket: baskets[1], tradeOwnership: uint96(0.3e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: 110,
            minAmount: 110,
            basketTradeOwnership: tradeOwnerships
        });
        vm.expectEmit();
        emit BasketManager.TokenSwapProposed(basketManager.rebalanceStatus().epoch, internalTrades, externalTrades);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);

        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(vm.getBlockTimestamp()));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));

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
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(externalTrades, "");

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(baskets[0], abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(baskets[1], abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(baskets[0], abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(baskets[1], abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(baskets[0], abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(baskets[1], abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(baskets[0], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(params.depositAmount));
        vm.mockCall(baskets[1], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount2));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](1);
        claimedAmounts[0] = [0, uint256(111)];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        basketManager.completeRebalance(externalTrades, baskets, targetWeights, basketAssets);
        assertEq(basketManager.basketBalanceOf(baskets[0], pairAsset), 77);
        // Previous implementation the 1 dust would be lost.
        assertEq(basketManager.basketBalanceOf(baskets[1], pairAsset), 34);
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
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
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

        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ExternalTradeSlippage.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);

        // Price of buy asset reduces
        vm.startPrank(admin);
        mockPriceOracle.setPrice(params.pairAsset, USD_ISO_4217_CODE, 9e17);
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, params.pairAsset, 1.1e18);
        vm.stopPrank();

        // Set minAmount to a valid value
        minAmount = sellAmount * 0.995e18 / 1e18;

        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: sellAmount,
            minAmount: minAmount,
            basketTradeOwnership: tradeOwnerships
        });

        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ExternalTradeSlippage.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
    }

    function testFuzz_proposeTokenSwap_externalTrade_revertsWhen_tradeOwnershipMisMatch(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        vm.assume(depositAmount < type(uint256).max / 1e36);
        params.depositAmount = depositAmount;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18 - 1) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.OwnershipSumMismatch.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
    }

    function _setupForPriceDeviationBoundTests(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 baseAssetWeight
    )
        internal
        returns (address[] memory baskets, ExternalTrade[] memory externalTrades, address[][] memory basketAssets)
    {
        // Setup basket assets and weights
        basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;

        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(baseAssetWeight);
        targetWeights[0][1] = uint64(sellWeight);

        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = depositAmount;

        baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup trade parameters
        uint256 sellAmount = depositAmount * sellWeight / 1e18;
        uint256 minAmount = sellAmount * 0.995e18 / 1e18;

        externalTrades = new ExternalTrade[](1);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: pairAsset,
            sellAmount: sellAmount,
            minAmount: minAmount,
            basketTradeOwnership: tradeOwnerships
        });
    }

    function test_findPriceDeviationBounds() public {
        // Setup test parameters
        uint256 sellWeight = 8e17; // 0.8e18
        uint256 depositAmount = 10e18;
        uint256 baseAssetWeight = 1e18 - sellWeight;

        (address[] memory baskets, ExternalTrade[] memory externalTrades, address[][] memory basketAssets) =
            _setupForPriceDeviationBoundTests(sellWeight, depositAmount, baseAssetWeight);

        // Find negative price deviation bound
        int256 left = -1e18;
        int256 right = 0;
        int256 negativeBuyAssetThreshold;

        while (right - left > 1) {
            int256 mid = (left + right) / 2;
            uint256 snapshotId = vm.snapshotState();
            _changePrice(pairAsset, mid);

            vm.prank(tokenswapProposer);
            try basketManager.proposeTokenSwap(
                new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets
            ) {
                right = mid;
            } catch {
                left = mid;
            }
            negativeBuyAssetThreshold = right;
            vm.revertToState(snapshotId);
        }

        // Find positive price deviation bound
        left = 0;
        right = 100e18;
        int256 positiveBuyAssetThreshold;

        while (right - left > 1) {
            int256 mid = (left + right) / 2;
            uint256 snapshotId = vm.snapshotState();
            _changePrice(pairAsset, mid);

            vm.prank(tokenswapProposer);
            try basketManager.proposeTokenSwap(
                new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets
            ) {
                left = mid;
            } catch {
                right = mid;
            }
            positiveBuyAssetThreshold = left;
            vm.revertToState(snapshotId);
        }

        // Find negative price deviation bound
        left = -1e18;
        right = 0;
        int256 negativeSellAssetThreshold;

        while (right - left > 1) {
            int256 mid = (left + right) / 2;
            uint256 snapshotId = vm.snapshotState();
            _changePrice(rootAsset, mid);

            vm.prank(tokenswapProposer);
            try basketManager.proposeTokenSwap(
                new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets
            ) {
                right = mid;
            } catch {
                left = mid;
            }
            negativeSellAssetThreshold = right;
            vm.revertToState(snapshotId);
        }

        // Find positive price deviation bound for root asset
        left = 0;
        right = 100e18;
        int256 positiveSellAssetThreshold;

        while (right - left > 1) {
            int256 mid = (left + right) / 2;
            uint256 snapshotId = vm.snapshotState();
            _changePrice(rootAsset, mid);

            vm.prank(tokenswapProposer);
            try basketManager.proposeTokenSwap(
                new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets
            ) {
                left = mid;
            } catch {
                right = mid;
            }
            positiveSellAssetThreshold = left;
            vm.revertToState(snapshotId);
        }

        // Price deviation thresholds for pair asset (buy asset from external market) that trigger a revert
        // Negative threshold: -4.52% (-0.0452e18)
        // Positive threshold: +5.53% (+0.0553e18)
        console.log("Negative buy asset threshold: ", negativeBuyAssetThreshold); // -45226130653266333
        console.log("Positive buy asset threshold: ", positiveBuyAssetThreshold); // 55276381909547738
        // Price deviation thresholds for root asset (sell asset from external market) that trigger a revert
        // Negative threshold: -5.24% (-0.0524e18)
        // Positive threshold: +4.74% (+0.0474e18)
        console.log("Negative sell asset threshold: ", negativeSellAssetThreshold); //-52380952380952381
        console.log("Positive sell asset threshold: ", positiveSellAssetThreshold); // 47368421052631580
    }

    function testFuzz_proposeTokenSwap_revertWhen_externalTrade_buyAssetPriceChanges_outsideDeviation(
        uint256 sellWeight,
        uint256 depositAmount,
        int256 priceDeviation
    )
        public
    {
        // Setup fuzzing bounds
        sellWeight = bound(sellWeight, 5e17, 1e18 - 1); // Ensure non-zero sell weight
        depositAmount = bound(depositAmount, 2e18, type(uint256).max / 1e36); // Ensure non-zero deposit
        vm.assume(depositAmount * sellWeight / 1e18 > 500);
        // Assume price deviation is either:
        // 1) Between -100% and -4.52% (negative deviation beyond threshold)
        // 2) Between +5.53% and +10000% (positive deviation beyond threshold)
        vm.assume(
            (priceDeviation > -1e18 && priceDeviation < -45_226_130_653_266_333)
                || (priceDeviation > 55_276_381_909_547_738 && priceDeviation < 100e18)
        );

        uint256 baseAssetWeight = 1e18 - sellWeight;
        (address[] memory baskets, ExternalTrade[] memory externalTrades, address[][] memory basketAssets) =
            _setupForPriceDeviationBoundTests(sellWeight, depositAmount, baseAssetWeight);

        // Price of buy asset changes
        _changePrice(pairAsset, priceDeviation);

        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ExternalTradeSlippage.selector);
        basketManager.proposeTokenSwap(new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets);
    }

    function testFuzz_proposeTokenSwap_passWhen_externalTrade_buyAssetPriceChanges_withinDeviation(
        uint256 sellWeight,
        uint256 depositAmount,
        int256 priceDeviation
    )
        public
    {
        // Setup fuzzing bounds
        sellWeight = bound(sellWeight, 5e17, 1e18 - 1); // Ensure non-zero sell weight
        depositAmount = bound(depositAmount, 2e18, type(uint256).max / 1e36); // Ensure non-zero deposit
        vm.assume(depositAmount * sellWeight / 1e18 > 500);
        // Bound price deviation between -4.5226% and +5.5276% to test valid price changes
        vm.assume((priceDeviation >= -45_226_130_653_266_333) && (priceDeviation <= 55_276_381_909_547_738));

        uint256 baseAssetWeight = 1e18 - sellWeight;
        (address[] memory baskets, ExternalTrade[] memory externalTrades, address[][] memory basketAssets) =
            _setupForPriceDeviationBoundTests(sellWeight, depositAmount, baseAssetWeight);

        // Price of buy asset changes
        _changePrice(pairAsset, priceDeviation);

        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_externalTrade_sellAssetPriceChanges_outsideDeviation(
        uint256 sellWeight,
        uint256 depositAmount,
        int256 priceDeviation
    )
        public
    {
        // Setup fuzzing bounds
        sellWeight = bound(sellWeight, 5e17, 1e18 - 1); // Ensure non-zero sell weight
        depositAmount = bound(depositAmount, 2e18, type(uint256).max / 1e36); // Ensure non-zero deposit
        vm.assume(depositAmount * sellWeight / 1e18 > 500);
        // Assume price deviation is either:
        // 1) Between -100% and -5.24% (negative deviation beyond threshold)
        // 2) Between +4.74% and +10000% (positive deviation beyond threshold)
        vm.assume(
            (priceDeviation > -1e18 && priceDeviation < -52_380_952_380_952_381)
                || (priceDeviation > 47_368_421_052_631_580 && priceDeviation < 100e18)
        );

        uint256 baseAssetWeight = 1e18 - sellWeight;
        (address[] memory baskets, ExternalTrade[] memory externalTrades, address[][] memory basketAssets) =
            _setupForPriceDeviationBoundTests(sellWeight, depositAmount, baseAssetWeight);

        // Price of sell asset changes
        _changePrice(rootAsset, priceDeviation);

        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ExternalTradeSlippage.selector);
        basketManager.proposeTokenSwap(new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets);
    }

    function testFuzz_proposeTokenSwap_passWhen_externalTrade_sellAssetPriceChanges_withinDeviation(
        uint256 sellWeight,
        uint256 depositAmount,
        int256 priceDeviation
    )
        public
    {
        // Setup fuzzing bounds
        sellWeight = bound(sellWeight, 5e17, 1e18 - 1); // Ensure non-zero sell weight
        depositAmount = bound(depositAmount, 2e18, type(uint256).max / 1e36); // Ensure non-zero deposit
        vm.assume(depositAmount * sellWeight / 1e18 > 500);
        // Bound price deviation between -5.24% and +4.74% to test valid price changes
        vm.assume((priceDeviation >= -52_380_952_380_952_381) && (priceDeviation <= 47_368_421_052_631_580));

        uint256 baseAssetWeight = 1e18 - sellWeight;
        (address[] memory baskets, ExternalTrade[] memory externalTrades, address[][] memory basketAssets) =
            _setupForPriceDeviationBoundTests(sellWeight, depositAmount, baseAssetWeight);

        // Price of sell asset changes
        _changePrice(rootAsset, priceDeviation);

        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(new InternalTrade[](0), externalTrades, baskets, _targetWeights, basketAssets);
    }

    // TODO: Write a fuzz test that generalizes the number of internal trades
    function testFuzz_proposeTokenSwap_internalTrade(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
        returns (address[] memory baskets)
    {
        return testFuzz_proposeTokenSwap_internalTrade(sellWeight, depositAmount, 0);
    }

    function testFuzz_proposeTokenSwap_internalTrade(
        uint256 sellWeight,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
        returns (address[] memory baskets)
    {
        vm.assume(swapFee <= MAX_SWAP_FEE);
        vm.prank(timelock);
        basketManager.setSwapFee(swapFee);
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36);
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;

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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Mimic the intended behavior of processing deposits on proposeRebalance
        ERC20Mock(rootAsset).mint(address(basketManager), params.depositAmount);
        ERC20Mock(params.pairAsset).mint(address(basketManager), params.depositAmount);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 0.95e18 / 1e18,
            maxAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 1.05e18 / 1e18
        });
        uint256 basket0RootAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[0], rootAsset);
        uint256 basket0PairAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[0], params.pairAsset);
        uint256 basket1RootAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[1], rootAsset);
        uint256 basket1PairAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[1], params.pairAsset);
        vm.expectEmit();
        emit BasketManager.TokenSwapProposed(basketManager.rebalanceStatus().epoch, internalTrades, externalTrades);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(vm.getBlockTimestamp()));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));

        uint256 swapFeeAmount = internalTrades[0].sellAmount.fullMulDiv(swapFee, 2e4);
        uint256 netSellAmount = internalTrades[0].sellAmount - swapFeeAmount;
        uint256 buyAmount = internalTrades[0].sellAmount; // Assume 1:1 price
        uint256 netBuyAmount = buyAmount - buyAmount.fullMulDiv(swapFee, 2e4);

        assertEq(
            basketManager.collectedSwapFees(rootAsset),
            swapFeeAmount,
            "collectedSwapFees did not increase by swapFeeAmount"
        );
        assertEq(
            basketManager.collectedSwapFees(params.pairAsset),
            buyAmount - netBuyAmount,
            "collectedSwapFees did not increase by swapFeeAmount"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[0], rootAsset),
            basket0RootAssetBalanceOfBefore - internalTrades[0].sellAmount,
            "fromBasket balance of sellToken did not decrease by sellAmount"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[0], params.pairAsset),
            basket0PairAssetBalanceOfBefore + netBuyAmount,
            "fromBasket balance of buyToken did not increase by netBuyAmount (minus swap fee)"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[1], rootAsset),
            basket1RootAssetBalanceOfBefore + netSellAmount,
            "toBasket balance of sellToken did not increase by netSellAmount (minus swap fee)"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[1], params.pairAsset),
            basket1PairAssetBalanceOfBefore - buyAmount,
            "toBasket balance of buyToken did not decrease by buyAmount"
        );
    }

    function testFuzz_proposeTokenSwap_revertWhen_CallerIsNotTokenswapProposer(address caller) public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        address[][] memory basketAssets = new address[][](1);
        vm.assume(!basketManager.hasRole(TOKENSWAP_PROPOSER_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, TOKENSWAP_PROPOSER_ROLE));
        vm.prank(caller);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights, basketAssets);
    }

    function test_proposeTokenSwap_revertWhen_MustWaitForRebalance() public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        address[][] memory basketAssets = new address[][](1);
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights, basketAssets);
    }

    function test_proposeTokenSwap_revertWhen_BaketMisMatch() public {
        test_proposeRebalance_processesDeposits();
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        address[][] memory basketAssets = new address[][](1);
        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights, basketAssets);
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
        params.pairAsset = pairAsset;
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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalanceProposer);

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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ElementIndexNotFound.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
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
        params.pairAsset = pairAsset;

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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        /// Propose the rebalance
        vm.prank(rebalanceProposer);
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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        // Assume for the case where the amount bought is greater than the balance of the to basket, thus providing
        // invalid input to the function
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: basketManager.basketBalanceOf(baskets[0], rootAsset),
            minAmount: 0,
            maxAmount: type(uint256).max
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
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
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        vm.assume(mismatchAssetAddress != baskets[0]);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ElementIndexNotFound.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
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
        params.pairAsset = pairAsset;
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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalanceProposer);

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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.InternalTradeMinMaxAmountNotReached.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);

        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18 - 1
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.InternalTradeMinMaxAmountNotReached.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_InternalTradeMinMaxAmountNotReached_withSwapFee(
        uint256 sellWeight,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
    {
        // Setup fuzzing bounds
        vm.assume(swapFee > 0 && swapFee <= MAX_SWAP_FEE);
        vm.prank(timelock);
        basketManager.setSwapFee(swapFee);
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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalanceProposer);

        // Propose the rebalance
        basketManager.proposeRebalance(baskets);

        // Expect revert on maxAmount regardless of swap fee consideration
        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18 - 1
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.InternalTradeMinMaxAmountNotReached.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);

        // ensure minAmount check with swap fee reverts correctly
        uint256 swapFeeAmount = internalTrades[0].sellAmount.fullMulDiv(swapFee, 2e4);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18 - swapFeeAmount + 1,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.InternalTradeMinMaxAmountNotReached.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);

        // minAmount is reduced by swap fee so the following should not revert
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18 - swapFeeAmount,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18
        });
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(vm.getBlockTimestamp()));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
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
        params.pairAsset = pairAsset;

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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
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
        params.pairAsset = pairAsset;
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
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.AssetNotFoundInBasket.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
    }

    function test_proposeTokenSwap_revertWhen_Paused() public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        address[][] memory basketAssets = new address[][](1);
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights, basketAssets);
    }

    function test_proposeTokenSwap_revertWhen_CannotProposeEmptyTrades() public {
        // Setup basket and target weights
        address[] memory baskets = new address[](1);
        baskets[0] = _setupSingleBasketAndMocks();
        address[][] memory basketAssets = _getBasketAssets(baskets);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup empty trades
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);

        // Attempt to propose token swap with empty trades
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.CannotProposeEmptyTrades.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
    }

    function test_proposeTokenSwap_InternalSwapFeeAffectsTotalValue(uint16 swapFee) public {
        swapFee = uint16(bound(swapFee, 1, MAX_SWAP_FEE));

        address[][] memory basketAssets;
        address[] memory baskets;
        {
            basketAssets = new address[][](2);
            basketAssets[0] = new address[](2);
            basketAssets[0][0] = rootAsset;
            basketAssets[0][1] = pairAsset;
            basketAssets[1] = new address[](2);
            basketAssets[1][0] = rootAsset;
            basketAssets[1][1] = pairAsset;
            address[] memory baseAssets = new address[](2);
            baseAssets[0] = rootAsset;
            baseAssets[1] = pairAsset;
            uint256[] memory initialDepositAmounts = new uint256[](2);
            initialDepositAmounts[0] = 1000e18;
            initialDepositAmounts[1] = 1000e18;
            uint64[][] memory initialWeights = new uint64[][](2);
            initialWeights[0] = new uint64[](2);
            initialWeights[0][0] = uint64(5e17);
            initialWeights[0][1] = uint64(5e17);
            initialWeights[1] = new uint64[](2);
            initialWeights[1][0] = uint64(5e17);
            initialWeights[1][1] = uint64(5e17);
            uint256[] memory bitFlags = new uint256[](2);
            bitFlags[0] = 3;
            bitFlags[1] = 3;
            address[] memory strategies = new address[](2);
            strategies[0] = address(uint160(uint256(keccak256("Strategy")) + 0));
            strategies[1] = address(uint160(uint256(keccak256("Strategy")) + 1));
            // Setup baskets
            baskets = _setupBasketsAndMocks(
                basketAssets, baseAssets, initialWeights, initialDepositAmounts, bitFlags, strategies
            );
        }
        // Set allowed weight deviation to 0
        vm.prank(timelock);
        basketManager.setWeightDeviation(0);

        // Setup Internal trade between the two baskets
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: pairAsset,
            toBasket: baskets[1],
            sellAmount: 500e18,
            minAmount: 500e18 * 95 / 100,
            maxAmount: 500e18 * 105 / 100
        });
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);

        uint256 snapshot = vm.snapshotState();
        // Test 1: When swap fees are enabled, internal trades should fail to meet target weights
        // This is because the fee reduces the effective balance after each trade, causing weights to deviate
        // slightly
        {
            // Configure non-zero swap fee
            vm.prank(timelock);
            basketManager.setSwapFee(swapFee);

            // Propose the rebalance
            vm.prank(rebalanceProposer);
            basketManager.proposeRebalance(baskets);

            // Mock basket token supplies
            vm.mockCall(baskets[0], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(1000e18));
            vm.mockCall(baskets[1], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(1000e18));

            // Expect revert since fees will cause weights to deviate from targets
            vm.prank(tokenswapProposer);
            vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
            basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
        }

        // Reset state for next test
        vm.revertToState(snapshot);

        // Test 2: With zero fees, the same trades should successfully meet target weights
        // This test confirms that the swap fee is the factor causing weight deviations,
        // and ensures the basket manager utilities account for it correctly.
        {
            // Configure zero swap fee
            vm.prank(timelock);
            basketManager.setSwapFee(0);

            // Propose the rebalance
            vm.prank(rebalanceProposer);
            basketManager.proposeRebalance(baskets);

            // Mock basket token supplies
            vm.mockCall(baskets[0], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(1000e18));
            vm.mockCall(baskets[1], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(1000e18));

            // Should succeed since no fees means trades maintain target weights
            vm.prank(tokenswapProposer);
            basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
        }
    }

    function testFuzz_executeTokenSwap_revertWhen_CallerIsNotTokenswapExecutor(
        address caller,
        ExternalTrade[] calldata trades,
        bytes calldata data
    )
        public
    {
        _setTokenSwapAdapter();
        vm.assume(!basketManager.hasRole(TOKENSWAP_EXECUTOR_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, TOKENSWAP_EXECUTOR_ROLE));
        vm.prank(caller);
        basketManager.executeTokenSwap(trades, data);
    }

    function testFuzz_executeTokenSwap_revertWhen_Paused(ExternalTrade[] calldata trades, bytes calldata data) public {
        _setTokenSwapAdapter();
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(tokenswapExecutor);
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
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        /// Propose the rebalance
        vm.prank(rebalanceProposer);
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
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
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
        params.baseAssetWeight = 1e18 - params.sellWeight;
        deviation = bound(deviation, max_weight_deviation, params.baseAssetWeight);
        vm.assume(params.baseAssetWeight + deviation < 1e18);
        params.pairAsset = pairAsset;

        uint256 deviatedTradeAmount = params.depositAmount.fullMulDiv(1e18 - params.baseAssetWeight - deviation, 1e18);
        vm.assume(deviatedTradeAmount > 100);

        /// Setup basket and target weights
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint64[][] memory weightsPerBasket = new uint64[][](1);
        // Deviate from the target weights
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = uint64(params.baseAssetWeight);
        weightsPerBasket[0][1] = uint64(params.sellWeight);
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, weightsPerBasket, initialDepositAmounts);

        /// Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: deviatedTradeAmount,
            minAmount: deviatedTradeAmount.fullMulDiv(0.995e18, 1e18),
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights, basketAssets);
    }

    function testFuzz_completeRebalance_internalTrade(
        uint256 initialSplit,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
    {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        initialSplit = bound(initialSplit, 1, 1e18 - 1);
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, depositAmount, swapFee);
        address basket = targetBaskets[0];
        address[][] memory basketAssets = _getBasketAssets(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount));
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights, basketAssets);
    }

    function testFuzz_proRataRedeem(
        uint256 initialSplit,
        uint256 depositAmount,
        uint256 burnedShares,
        uint16 swapFee
    )
        public
    {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        burnedShares = bound(burnedShares, 1, depositAmount);
        initialSplit = bound(initialSplit, 1, 1e18 - 1);
        testFuzz_completeRebalance_internalTrade(initialSplit, depositAmount, swapFee);

        // Redeem some shares from 0th basket
        address basket = basketManager.basketTokens()[0];
        uint256 totalSupplyBefore = depositAmount; // Assume price of share == price of deposit token

        uint256 asset0balance = basketManager.basketBalanceOf(basket, rootAsset);
        uint256 asset1balance = basketManager.basketBalanceOf(basket, pairAsset);
        vm.prank(basket);
        basketManager.proRataRedeem(totalSupplyBefore, burnedShares, address(this));
        assertEq(IERC20(rootAsset).balanceOf(address(this)), asset0balance.fullMulDiv(burnedShares, totalSupplyBefore));
        assertEq(IERC20(pairAsset).balanceOf(address(this)), asset1balance.fullMulDiv(burnedShares, totalSupplyBefore));
    }

    function testFuzz_proRataRedeem_passWhen_otherBasketRebalancing(uint256 initialDepositAmount) public {
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        // Create two baskets
        address[][] memory assetsPerBasket = new address[][](2);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        assetsPerBasket[1] = new address[](2);
        assetsPerBasket[1][0] = address(1);
        assetsPerBasket[1][1] = address(2);
        uint64[][] memory weightsPerBasket = new uint64[][](2);
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = 1e18;
        weightsPerBasket[0][1] = 0;
        weightsPerBasket[1] = new uint64[](2);
        weightsPerBasket[1][0] = 1e18;
        weightsPerBasket[1][1] = 0;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = initialDepositAmount;
        initialDepositAmounts[1] = initialDepositAmount;
        // Below deposits into both baskets
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        address rebalancingBasket = baskets[0];
        address nonRebalancingBasket = baskets[1];
        // Rebalance with only one basket
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = rebalancingBasket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        // Redeem some half of the shares from non-rebalancing basket
        uint256 totalSupplyBefore = initialDepositAmount; // Assume price of share == price of deposit token
        uint256 burnedShares = initialDepositAmount / 2;
        uint256 asset0balance = basketManager.basketBalanceOf(nonRebalancingBasket, rootAsset);
        uint256 asset1balance = basketManager.basketBalanceOf(nonRebalancingBasket, pairAsset);
        vm.prank(nonRebalancingBasket);
        basketManager.proRataRedeem(totalSupplyBefore, burnedShares, address(this));
        assertEq(IERC20(rootAsset).balanceOf(address(this)), asset0balance.fullMulDiv(burnedShares, totalSupplyBefore));
        assertEq(IERC20(pairAsset).balanceOf(address(this)), asset1balance.fullMulDiv(burnedShares, totalSupplyBefore));
    }

    function test_proRataRedeem_revertWhen_CannotBurnMoreSharesThanTotalSupply(
        uint256 initialSplit,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
    {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        initialSplit = bound(initialSplit, 1, 1e18 - 1);
        testFuzz_completeRebalance_internalTrade(initialSplit, depositAmount, swapFee);

        // Redeem some shares
        address basket = basketManager.basketTokens()[0];
        vm.expectRevert(BasketManagerUtils.CannotBurnMoreSharesThanTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(depositAmount, depositAmount + 1, address(this));
    }

    function test_proRataRedeem_revertWhen_CallerIsNotBasketToken() public {
        vm.expectRevert(_formatAccessControlError(address(this), BASKET_TOKEN_ROLE));
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroTotalSupply() public {
        address basket = _setupSingleBasketAndMocks();
        vm.expectRevert(BasketManagerUtils.ZeroTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroBurnedShares() public {
        address basket = _setupSingleBasketAndMocks();
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(BasketManagerUtils.ZeroBurnedShares.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 0, address(this));
    }

    function test_proRataRedeem_revertWhen_ZeroAddress() public {
        address basket = _setupSingleBasketAndMocks();
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(BasketManager.ZeroAddress.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(0));
    }

    function test_proRataRedeem_revertWhen_MustWaitForRebalanceToComplete() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(this));
    }

    function test_proRataRedeem_revertWhen_Paused() public {
        address basket = _setupSingleBasketAndMocks();
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
        vm.expectRevert(BasketManager.ZeroAddress.selector);
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
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
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
        vm.prank(tokenswapExecutor);
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
        vm.assume(badTrades.length > 0);
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);
        vm.assume(keccak256(abi.encode(badTrades)) != keccak256(abi.encode(trades)));

        // Execute
        vm.expectRevert(BasketManager.ExternalTradesHashMismatch.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(badTrades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_EmptyExternalTrades(
        uint256 sellWeight,
        uint256 depositAmount,
        bytes memory data
    )
        public
    {
        _setTokenSwapAdapter();
        testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);
        // Now test empty trades execution
        vm.prank(tokenswapExecutor);
        vm.expectRevert(BasketManager.EmptyExternalTrades.selector);
        basketManager.executeTokenSwap(new ExternalTrade[](0), data);
    }

    function testFuzz_executeTokenSwap_revertWhen_TokenSwapNotProposed(ExternalTrade[] memory trades) public {
        _setTokenSwapAdapter();
        vm.expectRevert(BasketManager.TokenSwapNotProposed.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_ZeroAddress(uint256 sellWeight, uint256 depositAmount) public {
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Execute
        vm.expectRevert(BasketManager.ZeroAddress.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_setManagementFee(uint16 fee) public {
        vm.assume(fee <= MAX_MANAGEMENT_FEE);
        address basket = _setupSingleBasketAndMocks();
        vm.prank(timelock);
        basketManager.setManagementFee(basket, fee);
        assertEq(basketManager.managementFee(basket), fee);
    }

    function testFuzz_setManagementFee_passesWhen_otherBasketRebalancing(
        uint256 initialDepositAmount,
        uint16 fee
    )
        public
    {
        vm.assume(fee <= MAX_MANAGEMENT_FEE);
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        // Create two baskets
        address[][] memory assetsPerBasket = new address[][](2);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        assetsPerBasket[1] = new address[](2);
        assetsPerBasket[1][0] = address(1);
        assetsPerBasket[1][1] = address(2);
        uint64[][] memory weightsPerBasket = new uint64[][](2);
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = 1e18;
        weightsPerBasket[0][1] = 0;
        weightsPerBasket[1] = new uint64[](2);
        weightsPerBasket[1][0] = 1e18;
        weightsPerBasket[1][1] = 0;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = initialDepositAmount;
        initialDepositAmounts[1] = initialDepositAmount;
        // Below deposits into both baskets
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        address rebalancingBasket = baskets[0];
        address nonRebalancingBasket = baskets[1];
        // Rebalance with only one basket
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = rebalancingBasket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        vm.prank(timelock);
        basketManager.setManagementFee(nonRebalancingBasket, fee);
    }

    function testFuzz_setManagementFee_revertsWhen_calledByNonTimelock(address caller) public {
        vm.assume(caller != timelock);
        address basket = _setupSingleBasketAndMocks();
        vm.assume(basket != address(0));
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setManagementFee(basket, 10);
    }

    function testFuzz_setManagementFee_revertWhen_invalidManagementFee(address basket, uint16 fee) public {
        vm.assume(fee > MAX_MANAGEMENT_FEE);
        vm.assume(basket != address(0));
        vm.expectRevert(BasketManager.InvalidManagementFee.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(basket, fee);
    }

    function testFuzz_setManagementFee_revertWhen_MustWaitForRebalanceToComplete(uint16 fee) public {
        vm.assume(fee <= MAX_MANAGEMENT_FEE);
        address basket = test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(basket, fee);
    }

    function testFuzz_setManagementFee_revertWhen_basketTokenNotFound(address basket) public {
        vm.assume(basket != address(0));
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(basket, 0);
    }

    function testFuzz_setSwapFee(uint16 fee) public {
        vm.assume(fee <= MAX_SWAP_FEE);
        vm.prank(timelock);
        basketManager.setSwapFee(fee);
        assertEq(basketManager.swapFee(), fee, "swapFee() returned unexpected value");
    }

    function testFuzz_setSwapFee_revertsWhen_calledByNonTimelock(address caller, uint16 fee) public {
        vm.assume(caller != timelock);
        vm.assume(fee <= MAX_SWAP_FEE);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setSwapFee(fee);
    }

    function testFuzz_setSwapFee_revertWhen_invalidSwapFee(uint16 fee) public {
        vm.assume(fee > MAX_SWAP_FEE);
        vm.expectRevert(BasketManager.InvalidSwapFee.selector);
        vm.prank(timelock);
        basketManager.setSwapFee(fee);
    }

    function testFuzz_setSwapFee_revertWhen_MustWaitForRebalanceToComplete(uint16 fee) public {
        vm.assume(fee <= MAX_SWAP_FEE);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setSwapFee(fee);
    }

    function testFuzz_collectSwapFee_revertWhen_calledByNonManager(address caller, address asset) public {
        vm.assume(caller != manager);
        vm.expectRevert(_formatAccessControlError(caller, MANAGER_ROLE));
        vm.prank(caller);
        basketManager.collectSwapFee(asset);
    }

    function testFuzz_setStepDelay(uint40 stepDelay) public {
        vm.assume(stepDelay >= MIN_STEP_DELAY && stepDelay <= MAX_STEP_DELAY);
        vm.prank(timelock);
        basketManager.setStepDelay(stepDelay);
        assertEq(basketManager.stepDelay(), stepDelay);
    }

    function testFuzz_setStepDelay_revertWhen_InvalidStepDelay(uint40 stepDelay) public {
        vm.assume(stepDelay < MIN_STEP_DELAY || stepDelay > MAX_STEP_DELAY);
        vm.prank(timelock);
        vm.expectRevert(BasketManager.InvalidStepDelay.selector);
        basketManager.setStepDelay(stepDelay);
    }

    function testFuzz_setStepDelay_revertWhen_MustWaitForRebalanceToComplete(uint40 stepDelay) public {
        vm.assume(stepDelay >= MIN_STEP_DELAY && stepDelay <= MAX_STEP_DELAY);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setStepDelay(stepDelay);
    }

    function testFuzz_setStepDelay_revertWhen_CallerIsNotTimelock(address caller, uint40 stepDelay) public {
        vm.assume(caller != timelock);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setStepDelay(stepDelay);
    }

    function testFuzz_setRetryLimit(uint8 retryLimit) public {
        vm.assume(retryLimit <= MAX_RETRIES);
        vm.prank(timelock);
        basketManager.setRetryLimit(retryLimit);
        assertEq(basketManager.retryLimit(), retryLimit);
    }

    function testFuzz_setRetryLimit_revertWhen_InvalidRetryCount(uint8 retryLimit) public {
        vm.assume(retryLimit > MAX_RETRIES);
        vm.prank(timelock);
        vm.expectRevert(BasketManager.InvalidRetryCount.selector);
        basketManager.setRetryLimit(retryLimit);
    }

    function testFuzz_setRetryLimit_revertWhen_MustWaitForRebalanceToComplete(uint8 retryLimit) public {
        vm.assume(retryLimit <= MAX_RETRIES);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setRetryLimit(retryLimit);
    }

    function testFuzz_setRetryLimit_revertWhen_CallerIsNotTimelock(address caller, uint8 retryLimit) public {
        vm.assume(caller != timelock);
        vm.assume(retryLimit <= MAX_RETRIES);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setRetryLimit(retryLimit);
    }

    function testFuzz_setSlippageLimit(uint256 slippage) public {
        vm.assume(slippage < MAX_SLIPPAGE_LIMIT);
        vm.prank(timelock);
        basketManager.setSlippageLimit(slippage);
        assertEq(basketManager.slippageLimit(), slippage);
    }

    function testFuzz_setSlippageLimit_revertWhen_InvalidSlippageLimit(uint256 slippage) public {
        vm.assume(slippage > MAX_SLIPPAGE_LIMIT);
        vm.prank(timelock);
        vm.expectRevert(BasketManager.InvalidSlippageLimit.selector);
        basketManager.setSlippageLimit(slippage);
    }

    function testFuzz_setSlippageLimit_revertWhen_MustWaitForRebalanceToComplete(uint256 slippage) public {
        vm.assume(slippage < MAX_SLIPPAGE_LIMIT);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setSlippageLimit(slippage);
    }

    function testFuzz_setSlippageLimit_revertWhen_CallerIsNotTimelock(address caller, uint256 slippage) public {
        vm.assume(caller != timelock);
        vm.assume(slippage < MAX_SLIPPAGE_LIMIT);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setSlippageLimit(slippage);
    }

    function testFuzz_setWeightDeviation(uint256 deviation) public {
        vm.assume(deviation < MAX_WEIGHT_DEVIATION_LIMIT);
        vm.prank(timelock);
        basketManager.setWeightDeviation(deviation);
        assertEq(basketManager.weightDeviationLimit(), deviation);
    }

    function testFuzz_setWeightDeviation_revertWhen_InvalidWeightDeviationLimit(uint256 deviation) public {
        vm.assume(deviation > MAX_WEIGHT_DEVIATION_LIMIT);
        vm.prank(timelock);
        vm.expectRevert(BasketManager.InvalidWeightDeviationLimit.selector);
        basketManager.setWeightDeviation(deviation);
    }

    function testFuzz_setWeightDeviation_revertWhen_MustWaitForRebalanceToComplete(uint256 deviation) public {
        vm.assume(deviation < MAX_WEIGHT_DEVIATION_LIMIT);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setWeightDeviation(deviation);
    }

    function testFuzz_setWeightDeviation_revertWhen_CallerIsNotTimelock(address caller, uint256 deviation) public {
        vm.assume(caller != timelock);
        vm.assume(deviation < MAX_WEIGHT_DEVIATION_LIMIT);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setWeightDeviation(deviation);
    }

    function testFuzz_collectSwapFee_returnsZeroWhen_hasNotCollectedFee(address asset) public {
        vm.prank(manager);
        assertEq(basketManager.collectSwapFee(asset), 0, "collectSwapFee() returned non-zero value");
    }

    function testFuzz_collectSwapFee(uint256 initialSplit, uint256 depositAmount, uint16 fee) public {
        // below test includes a call basketManager.setSwapFee(fee)
        testFuzz_completeRebalance_internalTrade(initialSplit, depositAmount, fee);
        vm.startPrank(manager);
        uint256 rootAssetFee = basketManager.collectSwapFee(rootAsset);
        uint256 pairAssetFee = basketManager.collectSwapFee(pairAsset);
        vm.stopPrank();
        assertEq(rootAssetFee, IERC20(rootAsset).balanceOf(protocolTreasury));
        assertEq(pairAssetFee, IERC20(pairAsset).balanceOf(protocolTreasury));
    }

    function testFuzz_updateBitFlag(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume((currentBitFlag & newBitFlag) == currentBitFlag);
        vm.assume(currentBitFlag != newBitFlag);

        address strategy = BasketToken(basket).strategy();
        vm.mockCall(strategy, abi.encodeCall(WeightStrategy.supportsBitFlag, (newBitFlag)), abi.encode(true));

        // Assume that now the root asset will be at the last index
        address[] memory newAssets = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            newAssets[i] = address(uint160(uint160(rootAsset) + 4 - i));
        }

        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.getAssets, (newBitFlag)), abi.encode(newAssets)
        );
        vm.mockCall(basket, abi.encodeCall(BasketToken.setBitFlag, (newBitFlag)), "");

        bytes32 oldBasketId = keccak256(abi.encodePacked(currentBitFlag, strategy));
        bytes32 newBasketId = keccak256(abi.encodePacked(newBitFlag, strategy));

        // Check the storage before making changes
        assertEq(
            basketManager.basketIdToAddress(oldBasketId), address(basket), "Old basketIdToAddress() should be not empty"
        );
        assertEq(basketManager.basketIdToAddress(newBasketId), address(0), "New basket id should be empty");

        // Update the bit flag
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);

        // Check storage changes
        assertEq(basketManager.basketIdToAddress(oldBasketId), address(0), "Old basketIdToAddress() not reset");
        assertEq(basketManager.basketIdToAddress(newBasketId), basket, "New basketIdToAddress() not set correctly");

        address[] memory updatedAssets = basketManager.basketAssets(basket);
        assertEq(updatedAssets.length, 5);
        for (uint256 i = 0; i < updatedAssets.length; i++) {
            assertEq(
                updatedAssets[i], address(uint160(uint160(rootAsset) + 4 - i)), "basketAssets() not updated correctly"
            );
            assertEq(
                basketManager.getAssetIndexInBasket(basket, updatedAssets[i]),
                i,
                "rebalanceAssetToIndex not updated correctly"
            );
        }

        assertEq(
            basketManager.basketTokenToBaseAssetIndex(basket),
            4,
            "basketTokenToBaseAssetIndexPlusOne is not updated correctly"
        );
    }

    function testFuzz_basketTokenToBaseAssetIndex_revertWhen_basketTokenNotFound(address invalidBasket) public {
        address basket = _setupSingleBasketAndMocks();
        vm.assume(invalidBasket != basket);
        vm.expectRevert(BasketManager.BasketTokenNotFound.selector);
        basketManager.basketTokenToBaseAssetIndex(invalidBasket);
    }

    function testFuzz_updateBitFlag_revertWhen_BasketTokenNotFound(address invalidBasket, uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        vm.assume(invalidBasket != basket);
        vm.expectRevert(BasketManager.BasketTokenNotFound.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(invalidBasket, newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_BitFlagMustBeDifferent(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume(currentBitFlag == newBitFlag); // Ensure newBitFlag is the same as currentBitFlag
        vm.expectRevert(BasketManager.BitFlagMustBeDifferent.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_BitFlagMustIncludeCurrent(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume((currentBitFlag & newBitFlag) != currentBitFlag); // Ensure newBitFlag doesn't include currentBitFlag
        vm.expectRevert(BasketManager.BitFlagMustIncludeCurrent.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_BitFlagUnsupportedByStrategy(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume((currentBitFlag & newBitFlag) == currentBitFlag); // Ensure newBitFlag includes currentBitFlag
        vm.assume(currentBitFlag != newBitFlag);
        vm.mockCall(
            BasketToken(basket).strategy(),
            abi.encodeCall(WeightStrategy.supportsBitFlag, (newBitFlag)),
            abi.encode(false)
        );
        vm.expectRevert(BasketManager.BitFlagUnsupportedByStrategy.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function test_updateBitFlag_revertWhen_BasketIdAlreadyExists() public {
        // Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 1e18;
        depositAmounts[1] = 1e18;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = 0.5e18;
        initialWeights[0][1] = 0.5e18;
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = 0.5e18;
        initialWeights[1][1] = 0.5e18;
        // Use the same strategies with different bitFlags
        address[] memory strategies = new address[](2);
        address strategy = address(uint160(uint256(keccak256("Strategy"))));
        strategies[0] = strategy;
        strategies[1] = strategy;
        uint256[] memory bitFlags = new uint256[](2);
        bitFlags[0] = 1;
        bitFlags[1] = 3;

        address[] memory baskets =
            _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts, bitFlags, strategies);

        // Use a bitflag of a basket with the same strategy
        uint256 newBitFlag = BasketToken(baskets[1]).bitFlag();
        bytes32 newBasketId = keccak256(abi.encodePacked(newBitFlag, strategy));

        // Assert the new id is already taken
        assertTrue(basketManager.basketIdToAddress(newBasketId) != address(0));

        // Expect revert due to BasketIdAlreadyExists
        vm.expectRevert(BasketManager.BasketIdAlreadyExists.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(baskets[0], newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_CalledByNonTimelock(
        address caller,
        address basket,
        uint256 newBitFlag
    )
        public
    {
        vm.assume(!basketManager.hasRole(TIMELOCK_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function test_updateBitFlag_revertWhen_BasketIsRebalancing() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory baskets = new address[](1);
        baskets[0] = basket;

        // Set the basket to rebalancing state using proposeRebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Expect revert due to MustWaitForRebalanceToComplete
        vm.expectRevert(BasketManager.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(baskets[0], 2);
    }

    // Internal functions
    function _setTokenSwapAdapter() internal {
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(tokenSwapAdapter);
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts,
        uint256[] memory bitFlags,
        address[] memory strategies
    )
        internal
        returns (address[] memory baskets)
    {
        // Set baseAssets to the first asset of each basket
        address[] memory baseAssets = new address[](assetsPerBasket.length);
        for (uint256 i = 0; i < assetsPerBasket.length; i++) {
            baseAssets[i] = assetsPerBasket[i][0];
        }
        return _setupBasketsAndMocks(
            assetsPerBasket, baseAssets, weightsPerBasket, initialDepositAmounts, bitFlags, strategies
        );
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        address[] memory baseAssets,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts,
        uint256[] memory bitFlags,
        address[] memory strategies
    )
        internal
        returns (address[] memory baskets)
    {
        uint256 numBaskets = assetsPerBasket.length;
        baskets = new address[](numBaskets);

        assertEq(numBaskets, weightsPerBasket.length, "_setupBasketsAndMocks: Weights array length mismatch");
        assertEq(
            numBaskets,
            initialDepositAmounts.length,
            "_setupBasketsAndMocks: Initial deposit amounts array length mismatch"
        );
        assertEq(numBaskets, bitFlags.length, "_setupBasketsAndMocks: Bit flags array length mismatch");
        assertEq(numBaskets, strategies.length, "_setupBasketsAndMocks: Strategies array length mismatch");

        _targetWeights = weightsPerBasket;

        for (uint256 i = 0; i < numBaskets; i++) {
            address[] memory assets = assetsPerBasket[i];
            uint64[] memory weights = weightsPerBasket[i];
            address baseAsset = baseAssets[i];
            uint256 bitFlag = bitFlags[i];
            address strategy = strategies[i];
            vm.mockCall(
                basketTokenImplementation,
                abi.encodeCall(
                    BasketToken.initialize, (IERC20(baseAsset), "basket", "b", bitFlag, strategy, assetRegistry)
                ),
                new bytes(0)
            );
            vm.mockCall(
                strategyRegistry,
                abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)),
                abi.encode(true)
            );
            vm.mockCall(strategy, abi.encodeCall(WeightStrategy.supportsBitFlag, (bitFlag)), abi.encode(true));
            vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
            vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
            vm.prank(manager);
            baskets[i] = basketManager.createNewBasket("basket", "b", baseAsset, bitFlag, strategy);

            vm.mockCall(baskets[i], abi.encodeWithSelector(bytes4(keccak256("bitFlag()"))), abi.encode(bitFlag));
            vm.mockCall(
                baskets[i], abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(initialDepositAmounts[i])
            );
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
            vm.mockCall(
                baskets[i],
                abi.encodeWithSelector(BasketToken.prepareForRebalance.selector),
                abi.encode(initialDepositAmounts[i], 0)
            );
            vm.mockCall(baskets[i], abi.encodeWithSelector(bytes4(keccak256("strategy()"))), abi.encode(strategy));
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
            vm.mockCall(baskets[i], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.getTargetWeights.selector), abi.encode(weights));
        }
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts,
        address[] memory strategies
    )
        internal
        returns (address[] memory baskets)
    {
        uint256[] memory bitFlags = new uint256[](assetsPerBasket.length);
        for (uint256 i = 0; i < assetsPerBasket.length; i++) {
            bitFlags[i] = i + 1;
        }
        return _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts, bitFlags, strategies);
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts
    )
        internal
        returns (address[] memory baskets)
    {
        address[] memory strategies = new address[](assetsPerBasket.length);
        for (uint256 i = 0; i < assetsPerBasket.length; i++) {
            strategies[i] = address(uint160(uint256(keccak256("Strategy")) + i));
        }
        return _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts, strategies);
    }

    function _setupSingleBasketAndMocks(
        address[] memory assets,
        uint64[] memory targetWeights,
        uint256 initialDepositAmount
    )
        internal
        returns (address basket)
    {
        address[][] memory assetsPerBasket = new address[][](1);
        assetsPerBasket[0] = assets;
        uint64[][] memory weightsPerBasket = new uint64[][](1);
        weightsPerBasket[0] = targetWeights;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = initialDepositAmount;
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        return baskets[0];
    }

    function _setupSingleBasketAndMocks() internal returns (address basket) {
        uint256 initialDepositAmount = 10_000;
        return _setupSingleBasketAndMocks(initialDepositAmount);
    }

    function _setupSingleBasketAndMocks(uint256 depositAmount) internal returns (address basket) {
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = pairAsset;
        uint64[] memory targetWeights = new uint64[](2);
        targetWeights[0] = 0.05e18;
        targetWeights[1] = 0.05e18;
        return _setupSingleBasketAndMocks(assets, targetWeights, depositAmount);
    }

    function _changePrice(address asset, int256 alterPercentage) internal {
        uint256 currentPrice = mockPriceOracle.getQuote(1e18, asset, USD_ISO_4217_CODE);
        uint256 newPrice;
        if (alterPercentage > 0) {
            newPrice = currentPrice + (currentPrice * uint256(alterPercentage)) / 1e18;
        } else {
            newPrice = currentPrice - (currentPrice * uint256(-alterPercentage)) / 1e18;
        }
        mockPriceOracle.setPrice(asset, USD_ISO_4217_CODE, newPrice);
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, asset, 1e36 / newPrice);
    }

    function _setPrices(address asset) internal {
        mockPriceOracle.setPrice(asset, USD_ISO_4217_CODE, 1e18);
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, asset, 1e18);
        vm.startPrank(admin);
        eulerRouter.govSetConfig(asset, USD_ISO_4217_CODE, address(mockPriceOracle));
        eulerRouter.govSetConfig(rootAsset, asset, address(mockPriceOracle));
        vm.stopPrank();
    }

    // Helper function to execute external swaps and complete rebalance in tests
    // Assumptions and gotchas:
    // - Only swaps the first basket in the array, ignores any additional baskets
    // - Always swaps from rootAsset (base asset) to pairAsset
    // - Assumes 1:1 price between assets for minAmount calculation
    // - Sets 100% trade ownership to first basket
    // - Uses fixed 0.5% slippage tolerance
    // - Mocks zero pending deposits and redemptions
    // - Advances block.timestamp by 15 minutes to pass timelock
    // baskets: Array of basket addresses (only first is used)
    // basketsTargetWeights: Target weights for each basket's assets
    // swapAmount: Amount of rootAsset to swap
    // tradeSuccess: Percentage of trade that succeeds (1e18 = 100%)
    function _swapFirstBasketRootAssetToPairAsset(
        address[] memory baskets,
        uint64[][] memory basketsTargetWeights,
        uint256 swapAmount,
        uint256 tradeSuccess
    )
        internal
    {
        address basket = baskets[0];
        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: pairAsset,
            sellAmount: swapAmount,
            minAmount: swapAmount * 0.995e18 / 1e18, // TODO: Test additional cases where price is not 1:1
            basketTradeOwnership: tradeOwnerships
        });
        address[][] memory basketAssets = _getBasketAssets(baskets);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, basketsTargetWeights, basketAssets);

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
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(externalTrades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

        // Check the basket balances before the trade
        uint256 basketRootAssetBalanceBefore = basketManager.basketBalanceOf(basket, rootAsset);
        uint256 basketPairAssetBalanceBefore = basketManager.basketBalanceOf(basket, pairAsset);

        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // tradeSuccess => 1e18 for a 100% successful trade, 0 for 100% unsuccessful trade
        // 0 in the 1 index is the result of a 100% unsuccessful trade
        // 0 in the 0 index is the result of a 100% successful trade
        // Assumes price is 1:1
        // TODO: Test additional cases where price is not 1:1
        uint256 successfulSellAmount = swapAmount * tradeSuccess / 1e18;
        uint256 successfulBuyAmount = successfulSellAmount;
        claimedAmounts[0] = [swapAmount - successfulSellAmount, successfulBuyAmount];

        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        basketManager.completeRebalance(externalTrades, baskets, basketsTargetWeights, basketAssets);

        // Check that the basket balances have been updated correctly
        assertEq(
            basketManager.basketBalanceOf(basket, rootAsset),
            basketRootAssetBalanceBefore - swapAmount + claimedAmounts[0][0]
        );
        assertEq(basketManager.basketBalanceOf(basket, pairAsset), basketPairAssetBalanceBefore + claimedAmounts[0][1]);
    }

    function _getBasketAssets(address[] memory baskets) internal returns (address[][] memory basketAssets) {
        basketAssets = new address[][](baskets.length);
        for (uint256 i = 0; i < baskets.length; i++) {
            basketAssets[i] = basketManager.basketAssets(baskets[i]);
        }
    }
}

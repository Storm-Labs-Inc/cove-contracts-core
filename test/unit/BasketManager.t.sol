// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { AllocationResolver } from "src/AllocationResolver.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

contract BasketManagerTest is BaseTest {
    BasketManager public basketManager;
    address public alice;
    address public admin;
    address public manager;
    address public rebalancer;
    address public pauser;
    address public rootAsset;
    address public basketTokenImplementation;
    address public oracleRegistry;
    address public allocationResolver;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        admin = createUser("admin");
        manager = createUser("manager");
        rebalancer = createUser("rebalancer");
        rootAsset = address(new ERC20Mock());
        basketTokenImplementation = createUser("basketTokenImplementation");
        oracleRegistry = createUser("oracleRegistry");
        allocationResolver = createUser("allocationResolver");
        basketManager = new BasketManager(basketTokenImplementation, oracleRegistry, allocationResolver, admin);
        vm.startPrank(admin);
        basketManager.grantRole(MANAGER_ROLE, manager);
        basketManager.grantRole(REBALANCER_ROLE, rebalancer);
        basketManager.grantRole(basketManager.PAUSER_ROLE(), pauser);

        vm.label(address(basketManager), "basketManager");
        vm.stopPrank();
    }

    function testFuzz_constructor(
        address basketTokenImplementation_,
        address oracleRegistry_,
        address allocationResolver_,
        address admin_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(oracleRegistry_ != address(0));
        vm.assume(allocationResolver_ != address(0));
        vm.assume(admin_ != address(0));

        BasketManager bm = new BasketManager(basketTokenImplementation_, oracleRegistry_, allocationResolver_, admin_);
        assertEq(bm.basketTokenImplementation(), basketTokenImplementation_);
        assertEq(bm.oracleRegistry(), oracleRegistry_);
        assertEq(address(bm.allocationResolver()), allocationResolver_);
        assertEq(bm.hasRole(bm.DEFAULT_ADMIN_ROLE(), admin_), true);
        assertEq(bm.getRoleMemberCount(bm.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(bm.MANAGER_ROLE(), MANAGER_ROLE);
        assertEq(bm.REBALANCER_ROLE(), REBALANCER_ROLE);
        assertEq(bm.PAUSER_ROLE(), PAUSER_ROLE);
    }

    function testFuzz_constructor_revertWhen_ZeroAddress(
        address basketTokenImplementation_,
        address oracleRegistry_,
        address allocationResolver_,
        address admin_,
        uint256 flag
    )
        public
    {
        // Use flag to determine which address to set to zero
        flag = bound(flag, 0, 14);
        if (flag & 1 == 0) {
            basketTokenImplementation_ = address(0);
        }
        if (flag & 2 == 0) {
            oracleRegistry_ = address(0);
        }
        if (flag & 4 == 0) {
            allocationResolver_ = address(0);
        }
        if (flag & 8 == 0) {
            admin_ = address(0);
        }

        vm.expectRevert(BasketManager.ZeroAddress.selector);
        new BasketManager(basketTokenImplementation_, oracleRegistry_, allocationResolver_, admin_);
    }

    function testFuzz_createNewBasket(uint256 bitFlag, uint256 strategyId) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, address(rootAsset), bitFlag, strategyId);
        assertEq(basketManager.numOfBasketTokens(), 1);
        assertEq(basketManager.basketTokens(0), basket);
        assertEq(basketManager.basketIdToAddress(keccak256(abi.encodePacked(bitFlag, strategyId))), basket);
        assertEq(basketManager.basketTokenToIndex(basket), 0);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenMaxExceeded(uint256 bitFlag, uint256 strategyId) public {
        string memory name = "basket";
        string memory symbol = "b";
        bitFlag = bound(bitFlag, 0, type(uint256).max - 257);
        strategyId = bound(strategyId, 0, type(uint256).max - 257);
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.supportsStrategy.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            bitFlag += 1;
            strategyId += 1;
            basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
            assertEq(basketManager.numOfBasketTokens(), i + 1);
        }
        vm.expectRevert(BasketManager.BasketTokenMaxExceeded.selector);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenAlreadyExists(uint256 bitFlag, uint256 strategyId) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        vm.startPrank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
        vm.expectRevert(BasketManager.BasketTokenAlreadyExists.selector);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
    }

    function testFuzz_createNewBasket_revertWhen_AllocationResolverDoesNotSupportStrategy(
        uint256 bitFlag,
        uint256 strategyId
    )
        public
    {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(false)
        );
        vm.expectRevert(BasketManager.AllocationResolverDoesNotSupportStrategy.selector);
        vm.startPrank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
    }

    function testFuzz_createNewBasket_revertWhen_CallerIsNotManager(address caller) public {
        vm.assume(!basketManager.hasRole(MANAGER_ROLE, caller));
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        vm.prank(caller);
        vm.expectRevert(_formatAccessControlError(caller, MANAGER_ROLE));
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
    }

    function test_createNewBasket_revertWhen_AssetListEmpty() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](0);
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManager.AssetListEmpty.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
    }

    function test_createNewBasket_revertWhen_BaseAssetMismatch() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address wrongAsset = address(new ERC20Mock());
        address[] memory assets = new address[](1);
        assets[0] = wrongAsset;

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManager.BaseAssetMismatch.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
    }

    function test_createNewBasket_revertWhen_BaseAssetIsZeroAddress() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](1);
        assets[0] = address(0);

        vm.expectRevert(BasketManager.ZeroAddress.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, address(0), bitFlag, strategyId);
    }

    function test_basketTokenToIndex() public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.supportsStrategy.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, i);
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i);
        }

        for (uint256 i = 0; i < 256; i++) {
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i);
        }
    }

    function test_basketTokenToIndex_revertWhen_BasketTokenNotFound() public {
        vm.expectRevert(BasketManager.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(address(0));
    }

    function testFuzz_basketTokenToIndex_revertWhen_BasketTokenNotFound(address basket) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.supportsStrategy.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, i);
            vm.assume(baskets[i] != basket);
        }

        vm.expectRevert(BasketManager.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(basket);
    }

    function test_proposeRebalance_processesDeposits() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(BasketManager.Status.REBALANCE_PROPOSED));
    }

    function test_proposeRebalance_revertWhen_depositTooLittle_RebalanceNotRequired() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(100));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;

        vm.expectRevert(BasketManager.RebalanceNotRequired.selector);
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_noDeposits_RebalanceNotRequired() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;

        vm.expectRevert(BasketManager.RebalanceNotRequired.selector);
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_MustWaitForRebalanceToComplete() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.startPrank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManager.MustWaitForRebalanceToComplete.selector);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_BasketTokenNotFound(address fakeBasket) public {
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = fakeBasket;
        vm.expectRevert(BasketManager.BasketTokenNotFound.selector);
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

    function test_completeRebalance() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        // vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeems.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.prank(rebalancer);
        basketManager.completeRebalance(targetBaskets);

        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(BasketManager.Status.NOT_STARTED));
        assertEq(basketManager.rebalanceStatus().basketHash, bytes32(0));
    }

    function test_completeRebalance_passWhen_redeemingShares() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalancer);
        basketManager.completeRebalance(targetBaskets);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalancer);
        basketManager.completeRebalance(targetBaskets);
    }

    function test_completeRebalance_revertWhen_NoRebalanceInProgress() public {
        vm.expectRevert(BasketManager.NoRebalanceInProgress.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(new address[](0));
    }

    function test_completeRebalance_revertWhen_BasketsMismatch() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManager.BasketsMismatch.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(new address[](0));
    }

    function test_completeRebalance_revertWhen_TooEarlyToCompleteRebalance() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManager.TooEarlyToCompleteRebalance.selector);
        vm.prank(rebalancer);
        basketManager.completeRebalance(targetBaskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_CallerIsNotRebalancer(address caller) public {
        BasketManager.InternalTrade[] memory internalTrades = new BasketManager.InternalTrade[](1);
        BasketManager.ExternalTrade[] memory externalTrades = new BasketManager.ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        vm.assume(!basketManager.hasRole(REBALANCER_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, REBALANCER_ROLE));
        vm.prank(caller);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
    }

    function testFuzz_proposeTokenSwap_externalTrade(uint256 sellWeight, uint256 depositAmount) public {
        sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshhold for a rebalance to be valid
        vm.assume(depositAmount * sellWeight / 1e18 > 500);
        uint256 baseAssetWeight = 1e18 - sellWeight;
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address pairAsset = address(new ERC20Mock());
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = pairAsset;

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(depositAmount));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = baseAssetWeight;
        newTargetWeights[1] = sellWeight;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
        BasketManager.ExternalTrade[] memory externalTrades = new BasketManager.ExternalTrade[](1);
        BasketManager.InternalTrade[] memory internalTrades = new BasketManager.InternalTrade[](0);
        BasketManager.BasketTradeOwnership[] memory tradeOwnerships = new BasketManager.BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketManager.BasketTradeOwnership({ basket: basket, tradeOwnership: uint96(1e18) });
        externalTrades[0] = BasketManager.ExternalTrade({
            sellToken: rootAsset,
            buyToken: pairAsset,
            sellAmount: depositAmount * sellWeight / 1e18,
            minAmount: (depositAmount * sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });

        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(block.timestamp));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(BasketManager.Status.TOKEN_SWAP_PROPOSED));
    }

    function testFuzz_proposeTokenSwap_internalTrade(uint256 sellWeight, uint256 depositAmount) public {
        sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshhold for a rebalance to be valid
        vm.assume(depositAmount * sellWeight / 1e18 > 500);
        uint256 baseAssetWeight = 1e18 - sellWeight;
        string memory name = "basket";
        string memory name2 = "basket2";
        string memory symbol = "b";
        string memory symbol2 = "c";
        uint256 bitFlag = 1;
        uint256 bitFlag2 = 2;
        uint256 strategyId = 1;
        uint256 strategyId2 = 2;
        address pairAsset = address(new ERC20Mock());
        vm.label(pairAsset, "pairAsset");
        address[] memory basket1Assets = new address[](2);
        basket1Assets[0] = rootAsset;
        basket1Assets[1] = pairAsset;
        address[] memory basket2Assets = new address[](2);
        basket2Assets[0] = pairAsset;
        basket2Assets[1] = rootAsset;

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(
            allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(basket1Assets)
        );
        vm.startPrank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);
        vm.label(basket, "basket");
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(pairAsset), name2, symbol2, bitFlag2, strategyId2, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag2, strategyId2)),
            abi.encode(true)
        );
        vm.mockCall(
            allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag2)), abi.encode(basket2Assets)
        );
        address basket2 = basketManager.createNewBasket(name2, symbol2, pairAsset, bitFlag2, strategyId2);
        vm.label(basket2, "basket2");
        vm.stopPrank();

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(depositAmount));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        vm.mockCall(basket2, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(depositAmount));
        vm.mockCall(basket2, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket2, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket2, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory intialTargetWeights = new uint256[](2);
        intialTargetWeights[0] = baseAssetWeight;
        intialTargetWeights[1] = 1e18 - baseAssetWeight;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(intialTargetWeights)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket2)),
            abi.encode(intialTargetWeights)
        );
        address[] memory targetBaskets = new address[](2);
        targetBaskets[0] = basket;
        targetBaskets[1] = basket2;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        BasketManager.ExternalTrade[] memory externalTrades = new BasketManager.ExternalTrade[](0);
        BasketManager.InternalTrade[] memory internalTrades = new BasketManager.InternalTrade[](1);
        internalTrades[0] = BasketManager.InternalTrade({
            fromBasket: basket,
            sellToken: rootAsset,
            buyToken: pairAsset,
            toBasket: basket2,
            sellAmount: depositAmount * (1e18 - baseAssetWeight) / 1e18,
            minAmount: (depositAmount * (1e18 - baseAssetWeight) / 1e18) * 0.995e18 / 1e18
        });

        vm.prank(rebalancer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets);
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(block.timestamp));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(BasketManager.Status.TOKEN_SWAP_PROPOSED));
    }

    function testFuzz_executeTokenSwap_revertWhen_CallerIsNotRebalancer(address caller) public {
        vm.assume(!basketManager.hasRole(REBALANCER_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, REBALANCER_ROLE));
        vm.prank(caller);
        basketManager.executeTokenSwap();
    }

    function testFuzz_proRataRedeem(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, 500e18, type(uint256).max);
        redeemAmount = bound(redeemAmount, 1, depositAmount);
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        // Deposit some assets
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(depositAmount));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
        // Mimic the fulfillDeposit call and transfer the depositing assets to the basket
        ERC20Mock(rootAsset).mint(address(basketManager), depositAmount);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount));
        vm.prank(rebalancer);
        basketManager.completeRebalance(targetBaskets);

        // Redeem some shares
        vm.prank(basket);
        basketManager.proRataRedeem(depositAmount, redeemAmount, address(this));

        assertEq(ERC20Mock(rootAsset).balanceOf(address(this)), redeemAmount);
    }

    function test_proRataRedeem_revertWhen_CannotBurnMoreSharesThanTotalSupply(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 500e18, type(uint256).max - 1);
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.supportsStrategy.selector), abi.encode(true)
        );
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        // Deposit some assets
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(depositAmount));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);
        // Mimic the fulfillDeposit call and transfer the depositing assets to the basket
        ERC20Mock(rootAsset).mint(address(basketManager), depositAmount);

        // Simulate the passage of time
        vm.warp(block.timestamp + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount));
        vm.prank(rebalancer);
        basketManager.completeRebalance(targetBaskets);

        // Redeem some shares
        vm.expectRevert(BasketManager.CannotBurnMoreSharesThanTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(depositAmount, depositAmount + 1, address(this));
    }

    function test_proRataRedeem_revertWhen_CallerIsNotBasketToken() public {
        vm.expectRevert(_formatAccessControlError(address(this), BASKET_TOKEN_ROLE));
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroTotalSupply() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.expectRevert(BasketManager.ZeroTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroBurnedShares() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(BasketManager.ZeroBurnedShares.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 0, address(this));
    }

    function test_proRataRedeem_revertWhen_ZeroAddress() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId, admin)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(BasketManager.ZeroAddress.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(0));
    }

    function test_proRataRedeem_revertWhen_MustWaitForRebalanceToComplete() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.supportsStrategy.selector), abi.encode(true)
        );
        vm.mockCall(
            allocationResolver, abi.encodeWithSelector(AllocationResolver.getAssets.selector), abi.encode(assets)
        );
        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.preFulfillRedeem, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 0.5e18;
        newTargetWeights[1] = 0.5e18;
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.getTargetWeight, (basket)),
            abi.encode(newTargetWeights)
        );
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalancer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManager.MustWaitForRebalanceToComplete.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(this));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { BaseTest } from "../utils/BaseTest.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AllocationResolver } from "src/AllocationResolver.sol";
import { BasketManager } from "src/BasketManager.sol";

import { BasketToken } from "src/BasketToken.sol";

contract BasketManagerTest is BaseTest {
    BasketManager public basketManager;
    address public alice;
    address public owner;
    address public rootAsset;
    address public basketTokenImplementation;
    address public oracleRegistry;
    address public allocationResolver;

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        owner = createUser("owner");
        rootAsset = address(new ERC20Mock());
        basketTokenImplementation = createUser("basketTokenImplementation");
        oracleRegistry = createUser("oracleRegistry");
        allocationResolver = createUser("allocationResolver");
        vm.prank(owner);
        basketManager = new BasketManager(rootAsset, basketTokenImplementation, oracleRegistry, allocationResolver);
        vm.label(address(basketManager), "basketManager");
    }

    function testFuzz_constructor(
        address rootAsset_,
        address basketTokenImplementation_,
        address oracleRegistry_,
        address allocationResolver_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(oracleRegistry_ != address(0));
        vm.assume(allocationResolver_ != address(0));
        vm.assume(rootAsset_ != address(0));

        BasketManager bm =
            new BasketManager(rootAsset_, basketTokenImplementation_, oracleRegistry_, allocationResolver_);
        assertEq(bm.ROOT_ASSET(), rootAsset_);
        assertEq(bm.basketTokenImplementation(), basketTokenImplementation_);
        assertEq(bm.oracleRegistry(), oracleRegistry_);
        assertEq(address(bm.allocationResolver()), allocationResolver_);
    }

    function testFuzz_constructor_revertWhen_ZeroAddress(
        address rootAsset_,
        address basketTokenImplementation_,
        address oracleRegistry_,
        address allocationResolver_,
        uint256 flag
    )
        public
    {
        flag = bound(flag, 0, 14);
        if (flag & 1 == 0) {
            rootAsset_ = address(0);
        }
        if (flag & 2 == 0) {
            basketTokenImplementation_ = address(0);
        }
        if (flag & 4 == 0) {
            oracleRegistry_ = address(0);
        }
        if (flag & 8 == 0) {
            allocationResolver_ = address(0);
        }

        vm.expectRevert(BasketManager.ZeroAddress.selector);
        new BasketManager(rootAsset_, basketTokenImplementation_, oracleRegistry_, allocationResolver_);
    }

    function testFuzz_createNewBasket(uint256 bitFlag, uint256 strategyId) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(
            allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(new address[](0))
        );
        address basket = basketManager.createNewBasket(name, symbol, bitFlag, strategyId);
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
        vm.mockCall(
            allocationResolver,
            abi.encodeWithSelector(AllocationResolver.getAssets.selector),
            abi.encode(new address[](0))
        );
        for (uint256 i = 0; i < 256; i++) {
            bitFlag += 1;
            strategyId += 1;
            basketManager.createNewBasket(name, symbol, bitFlag, strategyId);
            assertEq(basketManager.numOfBasketTokens(), i + 1);
        }
        vm.expectRevert(BasketManager.BasketTokenMaxExceeded.selector);
        basketManager.createNewBasket(name, symbol, bitFlag, strategyId);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenAlreadyExists(uint256 bitFlag, uint256 strategyId) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(
            allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(new address[](0))
        );
        basketManager.createNewBasket(name, symbol, bitFlag, strategyId);
        vm.expectRevert(BasketManager.BasketTokenAlreadyExists.selector);
        basketManager.createNewBasket(name, symbol, bitFlag, strategyId);
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
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(false)
        );
        vm.expectRevert(BasketManager.AllocationResolverDoesNotSupportStrategy.selector);
        basketManager.createNewBasket(name, symbol, bitFlag, strategyId);
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
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        address basket = basketManager.createNewBasket(name, symbol, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingRedeems, ()), abi.encode(0));
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
        basketManager.proposeRebalance(targetBaskets);

        assertEq(basketManager.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(BasketManager.Status.REBALANCE_PROPOSED));
    }

    function test_proposeRebalance_revertWhen_depositTooLittle() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        uint256 strategyId = 1;
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = address(new ERC20Mock());

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategyId)),
            new bytes(0)
        );
        vm.mockCall(
            allocationResolver,
            abi.encodeCall(AllocationResolver.supportsStrategy, (bitFlag, strategyId)),
            abi.encode(true)
        );
        vm.mockCall(allocationResolver, abi.encodeCall(AllocationResolver.getAssets, (bitFlag)), abi.encode(assets));
        address basket = basketManager.createNewBasket(name, symbol, bitFlag, strategyId);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(100));
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingRedeems, ()), abi.encode(0));
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

        vm.expectRevert(BasketManager.RebalanceNotNeeded.selector);
        basketManager.proposeRebalance(targetBaskets);
    }
}

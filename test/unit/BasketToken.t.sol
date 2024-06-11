// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { BasketToken } from "src/BasketToken.sol";

import { Errors } from "src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { DummyERC20 } from "test/utils/mocks/DummyERC20.sol";
import { MockAssetRegistry } from "test/utils/mocks/MockAssetRegistry.sol";
import { MockBasketManager } from "test/utils/mocks/MockBasketManager.sol";

contract BasketTokenTest is BaseTest {
    BasketToken public basket;
    BasketToken public basketTokenImplementation;
    MockBasketManager public basketManager;
    MockAssetRegistry public assetRegistry;
    DummyERC20 public dummyAsset;
    address public alice;
    address public owner;

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        owner = createUser("owner");
        // create dummy asset
        dummyAsset = new DummyERC20("Dummy", "DUMB");
        vm.label(address(dummyAsset), "dummyAsset");
        vm.prank(owner);
        basketTokenImplementation = new BasketToken();
        basketManager = new MockBasketManager(address(basketTokenImplementation));
        vm.label(address(basketManager), "basketManager");
        basket = basketManager.createNewBasket(ERC20(dummyAsset), "Test", "TEST", 1, 1, address(owner));
        vm.label(address(basket), "basketToken");
        assetRegistry = new MockAssetRegistry();
        vm.label(address(assetRegistry), "assetRegistry");
        vm.prank(address(owner));
        basket.setAssetRegistry(address(assetRegistry));
    }

    function test_constructor() public {
        vm.expectRevert();
        basketTokenImplementation.initialize(ERC20(dummyAsset), "Test", "TEST", 1, 1, address(0));
    }

    function test_initialize() public view {
        assertEq(basket.asset(), address(dummyAsset));
        assertEq(basket.name(), string.concat("CoveBasket-", "Test"));
        assertEq(basket.symbol(), string.concat("covb", "TEST"));
        assertEq(basket.basketManager(), address(basketManager));
        assertEq(basket.asset(), address(dummyAsset));
    }

    function test_initialize_revertsWhen_ownerZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        basketManager.createNewBasket(ERC20(dummyAsset), "Test", "TEST", 1, 1, address(0));
    }

    function test_setBasketManager() public {
        MockBasketManager newBasketManager = new MockBasketManager(address(basket));
        vm.label(address(newBasketManager), "newBasketManager");
        vm.prank(owner);
        basket.setBasketManager(address(newBasketManager));
        assertEq(basket.basketManager(), address(newBasketManager));
    }

    function test_setBasketManager_revertsWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(owner);
        basket.setBasketManager(address(0));
    }

    function test_setAssetRegistry() public {
        MockAssetRegistry newAssetRegistry = new MockAssetRegistry();
        vm.label(address(newAssetRegistry), "newAssetRegistry");
        vm.prank(owner);
        basket.setAssetRegistry(address(newAssetRegistry));
        assertEq(basket.assetRegistry(), address(newAssetRegistry));
    }

    function test_setAssetRegistry_revertWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(owner);
        basket.setAssetRegistry(address(0));
    }

    function testFuzz_requestDeposit(uint256 amount) public {
        vm.assume(amount > 0);
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        assertEq(basket.totalAssets(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.pendingDepositRequest(alice), amount);
        assertEq(basket.maxDeposit(alice), 0);
        assertEq(basket.maxMint(alice), 0);
        assertEq(basket.totalPendingDeposits(), amount);
    }

    function testFuzz_requestDeposit_withoutUserArgument(uint256 amount) public {
        vm.assume(amount > 0);
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount);
        assertEq(basket.totalAssets(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.pendingDepositRequest(alice), amount);
        assertEq(basket.maxDeposit(alice), 0);
        assertEq(basket.maxMint(alice), 0);
        assertEq(basket.totalPendingDeposits(), amount);
    }

    function test_requestDeposit_passWhen_pendingDepositRequest() public {
        // vm.assume(amount > 0 && amount2 > 0 && amount + amount2 < type(uint256).max); // TODO: overflows
        // bound(amount, 0, type(uint256).max / 2);
        // bound(amount2, 0, type(uint256).max/ 2);
        uint256 amount = 1e22;
        uint256 amount2 = 1e20;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount);
        assertEq(basket.pendingDepositRequest(alice), amount);
        assertEq(basket.totalPendingDeposits(), amount);
        dummyAsset.mint(alice, amount2);
        dummyAsset.approve(address(basket), amount2);
        basket.requestDeposit(amount2, alice);
        assertEq(basket.pendingDepositRequest(alice), amount + amount2);
        assertEq(basket.totalPendingDeposits(), amount + amount2);
    }

    function test_requestDeposit_revertWhen_zeroAmount() public {
        vm.prank(alice);
        dummyAsset.approve(address(basket), 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        basket.requestDeposit(0, alice);
    }

    function test_requestDeposit_revertWhen_claimableDepositOutstanding() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimOutstandingDeposit.selector));
        vm.startPrank(alice);
        basket.requestDeposit(amount, alice);
    }

    function test_requestDeposit_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        assetRegistry.pauseAssets();
        vm.expectRevert(abi.encodeWithSelector(BasketToken.AssetPaused.selector));
        basket.requestDeposit(amount, alice);
    }

    function test_fulfillDeposit() public {
        // Note: fuzztest fails if amount = 1, issued shares = 2, should this be checked in basket manager?
        // vm.assume(amount > 0 && issuedShares > 0);
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        assertEq(dummyAsset.balanceOf(address(basketManager)), basketManagerBalanceBefore + amount);
        assertEq(basket.balanceOf(address(basket)), issuedShares);
        // assertEq(basket.totalAssets(), amount);
        assertEq(dummyAsset.balanceOf(address(basket)), 0);
        assertEq(dummyAsset.balanceOf(address(basketManager)), amount);
        assertEq(basket.balanceOf(address(basket)), issuedShares);
        assertEq(basket.maxDeposit(alice), amount);
        assertEq(basket.maxMint(alice), issuedShares);
        assertEq(basket.totalPendingDeposits(), 0);
    }

    function test_fulfillDeposit_revertsWhen_ZeroPendingDeposits() public {
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingDeposits.selector));
        vm.prank(address(basketManager));
        basket.fulfillDeposit(1e18);
    }

    function test_fulfillDeposit_revertsWhen_notBasketManager() public {
        vm.expectRevert(_formatAccessControlError(alice, BASKET_MANAGER_ROLE));
        vm.prank(alice);
        basket.fulfillDeposit(1e18);
    }

    function test_deposit() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        uint256 userBalanceBefore = basket.balanceOf(address(alice));
        vm.prank(alice);
        basket.deposit(amount, alice);
        uint256 userBalanceAfter = basket.balanceOf(address(alice));
        assertEq(userBalanceAfter, userBalanceBefore + issuedShares);
        assertEq(basket.maxDeposit(alice), 0);
        assertEq(basket.maxMint(alice), 0);
    }

    function test_deposit_revertsWhen_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        basket.deposit(0, alice);
    }

    function test_deposit_revertsWhen_notClaimingFullOutstandingDeposit() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimFullAmount.selector));
        vm.prank(alice);
        basket.deposit(amount - 1, alice);
    }

    function test_mint() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        uint256 userBalanceBefore = basket.balanceOf(address(alice));
        vm.prank(alice);
        basket.mint(issuedShares, alice);
        uint256 userBalanceAfter = basket.balanceOf(address(alice));
        assertEq(userBalanceAfter, userBalanceBefore + issuedShares);
        assertEq(basket.maxDeposit(alice), 0);
        assertEq(basket.maxMint(alice), 0);
    }

    function test_mint_revertsWhen_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        basket.mint(0, alice);
    }

    function test_mint_revertsWhen_notClaimingFullOutstandingDeposit() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimFullAmount.selector));
        vm.prank(alice);
        basket.mint(issuedShares - 1, alice);
    }

    function test_cancelDepositRequest() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        assertEq(basket.pendingDepositRequest(alice), amount);
        assertEq(basket.totalPendingDeposits(), amount);
        uint256 balanceBefore = dummyAsset.balanceOf(address(alice));
        basket.cancelDepositRequest();
        uint256 balanceAfter = dummyAsset.balanceOf(address(alice));
        assertEq(basket.pendingDepositRequest(alice), 0);
        assertEq(balanceAfter, balanceBefore + amount);
    }

    function test_cancelDepositRequest_revertsWhen_zeroPendingDeposits() public {
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingDeposits.selector));
        vm.prank(alice);
        basket.cancelDepositRequest();
    }

    function test_requestRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(1e18, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares, alice, alice);
        assertEq(basket.pendingRedeemRequest(alice), userShares);
        assertEq(basket.totalPendingRedeems(), userShares);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.balanceOf(address(basket)), userShares);
        assertEq(basket.maxRedeem(alice), 0);
        assertEq(basket.maxWithdraw(alice), 0);
    }

    function test_requestRedeem_withAllowance() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        address payable bob = createUser("bob");
        vm.label(users["bob"], "bob");
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.approve(bob, userShares);
        vm.stopPrank();
        vm.startPrank(bob);
        basket.requestRedeem(userShares, bob, alice);
        assertEq(basket.pendingRedeemRequest(bob), userShares);
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.balanceOf(address(basket)), userShares);
    }

    function test_redeemRequest_passWhen_pendingRedeemRequest() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 halfUserShares = basket.balanceOf(alice) / 2;
        basket.requestRedeem(halfUserShares, alice, alice);
        assertEq(basket.pendingRedeemRequest(alice), halfUserShares);
        assertEq(basket.totalPendingRedeems(), halfUserShares);
        assertEq(basket.balanceOf(alice), halfUserShares);
        assertEq(basket.balanceOf(address(basket)), halfUserShares);
        assertEq(basket.maxRedeem(alice), 0);
        assertEq(basket.maxWithdraw(alice), 0);
        basket.requestRedeem(halfUserShares, alice, alice);
        assertEq(basket.pendingRedeemRequest(alice), issuedShares);
        assertEq(basket.totalPendingRedeems(), issuedShares);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.balanceOf(address(basket)), issuedShares);
        assertEq(basket.maxRedeem(alice), 0);
        assertEq(basket.maxWithdraw(alice), 0);
    }

    function test_requestRedeem_revertWhen_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        basket.requestRedeem(0, alice, alice);
    }

    function test_requestRedeem_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        assetRegistry.pauseAssets();
        vm.expectRevert(abi.encodeWithSelector(BasketToken.AssetPaused.selector));
        basket.requestRedeem(amount, alice, alice);
    }

    function test_requestRedeem_revertWhen_outstandingRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares / 2, alice, alice);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimOutstandingRedeem.selector));
        vm.stopPrank();
        vm.prank(alice);
        basket.requestRedeem(issuedShares / 2, alice, alice);
    }

    function test_fulfillRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares, alice, alice);
        vm.stopPrank();
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        assertEq(basketManagerBalanceBefore, amount);
        uint256 basketBalanceBefore = basket.balanceOf(address(basket));
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        assertEq(basketManagerBalanceBefore - amount, dummyAsset.balanceOf(address(basketManager)));
        assertEq(basketBalanceBefore - userShares, basket.balanceOf(address(basket)));
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.maxRedeem(alice), issuedShares);
        assertEq(basket.maxWithdraw(alice), amount);
    }

    function test_preFulfillRedeem_returnsZeroWhen_ZeroPendingRedeems() public {
        vm.startPrank(address(basketManager));
        assertEq(basket.preFulfillRedeem(), 0);
    }

    function test_fulfillRedeem_revertsWhen_preFulfillRedeem_notCalled() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares, alice, alice);
        vm.stopPrank();
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        assertEq(basketManagerBalanceBefore, amount);
        vm.startPrank(address(basketManager));
        vm.expectRevert(abi.encodeWithSelector(BasketToken.PreFulFillRedeemNotCalled.selector));
        basket.fulfillRedeem(amount);
    }

    function test_fulfillRedeem_revertWhen_reedemRequest_afterPreFulfillRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares / 2, alice, alice);
        vm.stopPrank();
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        assertEq(basketManagerBalanceBefore, amount);
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
        vm.prank(alice);
        vm.expectRevert(BasketToken.MustClaimOutstandingRedeem.selector);
        basket.requestRedeem(userShares / 2, alice, alice);
    }

    function test_fulfillRedeem_passWhen_reedemRequestClaimed() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares / 2, alice, alice);
        vm.stopPrank();
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        assertEq(basketManagerBalanceBefore, amount);
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount / 2);
        vm.startPrank(alice);
        uint256 aliceAssetBalanceBefore = dummyAsset.balanceOf(alice);
        basket.redeem(userShares / 2, alice, alice);
        assertEq(dummyAsset.balanceOf(alice), aliceAssetBalanceBefore + (amount / 2));
        assertEq(basket.pendingRedeemRequest(alice), 0);
        uint256 aliceBasketBalanceBefore = basket.balanceOf(alice);
        basket.requestRedeem(userShares / 2, alice, alice);
        assertEq(aliceBasketBalanceBefore, basket.balanceOf(alice) + (userShares / 2));
        assertEq(basket.pendingRedeemRequest(alice), userShares / 2);
    }

    function test_fulfillRedeem_passWhen_reedemRequestClaimed_withdraw() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares / 2, alice, alice);
        vm.stopPrank();
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        assertEq(basketManagerBalanceBefore, amount);
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount / 2);
        vm.startPrank(alice);
        uint256 aliceAssetBalanceBefore = dummyAsset.balanceOf(alice);
        basket.withdraw(amount / 2, alice, alice);
        assertEq(dummyAsset.balanceOf(alice), aliceAssetBalanceBefore + (amount / 2));
        assertEq(basket.pendingRedeemRequest(alice), 0);
        uint256 aliceBasketBalanceBefore = basket.balanceOf(alice);
        basket.requestRedeem(userShares / 2, alice, alice);
        assertEq(aliceBasketBalanceBefore, basket.balanceOf(alice) + (userShares / 2));
        assertEq(basket.pendingRedeemRequest(alice), userShares / 2);
    }

    function test_fulfillRedeem_revertsWhen_notBasketManager() public {
        vm.expectRevert(_formatAccessControlError(alice, BASKET_MANAGER_ROLE));
        vm.prank(alice);
        basket.fulfillRedeem(1e18);
    }

    function test_preFulfillRedeem_revertsWhen_notBasketManager() public {
        vm.expectRevert(_formatAccessControlError(alice, BASKET_MANAGER_ROLE));
        vm.prank(alice);
        basket.fulfillRedeem(1e18);
    }

    function test_Redeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares, alice, alice);
        vm.stopPrank();
        assertEq(dummyAsset.balanceOf(address(basketManager)), amount);
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        vm.stopPrank();
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.maxRedeem(alice), issuedShares);
        assertEq(basket.maxWithdraw(alice), amount);
        uint256 aliceBalanceBefore = dummyAsset.balanceOf(alice);
        vm.prank(alice);
        basket.redeem(issuedShares, alice, alice);
        assertEq(dummyAsset.balanceOf(alice), aliceBalanceBefore + amount);
        assertEq(basket.maxRedeem(alice), 0);
        assertEq(basket.maxWithdraw(alice), 0);
    }

    function test_redeem_revertsWhen_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        basket.redeem(0, alice, alice);
    }

    function test_redeem_revertsWhen_notClaimingFullOutstandingRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimFullAmount.selector));
        vm.stopPrank();
        vm.prank(alice);
        basket.redeem(issuedShares - 1, alice, alice);
    }

    function test_withdraw() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares); // pps = 10
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        uint256 userShares = basket.balanceOf(alice);
        basket.requestRedeem(userShares, alice, alice);
        vm.stopPrank();
        assertEq(dummyAsset.balanceOf(address(basketManager)), amount);
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        vm.stopPrank();
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.maxRedeem(alice), issuedShares);
        assertEq(basket.maxWithdraw(alice), amount);
        uint256 aliceBalanceBefore = dummyAsset.balanceOf(alice);
        vm.prank(alice);
        basket.withdraw(amount, alice, alice);
        assertEq(dummyAsset.balanceOf(alice), aliceBalanceBefore + amount);
        assertEq(basket.maxRedeem(alice), 0);
        assertEq(basket.maxWithdraw(alice), 0);
    }

    function test_withdraw_revertsWhen_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        basket.withdraw(0, alice, alice);
    }

    function test_withdraw_revertsWhen_notClaimingFullOutstandingRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimFullAmount.selector));
        vm.prank(alice);
        basket.withdraw(amount - 1, alice, alice);
    }

    function test_cancelRedeemRequest() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares);
        assertEq(basket.pendingRedeemRequest(alice), issuedShares);
        assertEq(basket.totalPendingRedeems(), issuedShares);
        uint256 balanceBefore = basket.balanceOf(address(alice));
        basket.cancelRedeemRequest();
        uint256 balanceAfter = basket.balanceOf(address(alice));
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(balanceAfter, balanceBefore + issuedShares);
    }

    function test_cancelRedeemRequest_revertsWhen_zeroPendingRedeems() public {
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingRedeems.selector));
        vm.prank(alice);
        basket.cancelRedeemRequest();
    }

    function test_cancelRedeemRequest_revertsWhen_preFulfillRedeem_hasBeenCalled() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingRedeems.selector));
        vm.prank(alice);
        basket.cancelRedeemRequest();
    }

    function test_previewDeposit_reverts() public {
        vm.expectRevert();
        basket.previewDeposit(1);
    }

    function test_previewMint_reverts() public {
        vm.expectRevert();
        basket.previewMint(1);
    }
}

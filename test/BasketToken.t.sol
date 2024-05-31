// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { BasketToken } from "src/BasketToken.sol";
import { MockBasketManager } from "test/mock/MockBasketManager.sol";
import { MockAssetRegistry } from "test/mock/MockAssetRegistry.sol";
// import { Errors } from "src/libraries/Errors.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DummyERC20 } from "./utils/mocks/DummyERC20.sol";
import { Errors } from "src/libraries/Errors.sol";

contract BasketToken_Test is BaseTest {
    BasketToken public basket;
    MockBasketManager public basketManager;
    MockAssetRegistry public assetRegistry;
    DummyERC20 public dummyAsset;
    address public alice;
    address public owner;

    function setUp() public override {
        super.setUp();
        alice = users["alice"];
        owner = users["owner"];
        // create dummy asset
        dummyAsset = new DummyERC20("Dummy", "DUMB");
        vm.label(address(dummyAsset), "dummyAsset");
        vm.prank(owner);
        BasketToken basketTokenImplementation = new BasketToken();
        basketManager = new MockBasketManager(address(basketTokenImplementation));
        vm.label(address(basketManager), "basketManager");
        basket = basketManager.createNewBasket(ERC20(dummyAsset), "Test", "TEST", 1, 1);
        vm.label(address(basket), "basketToken");
        assetRegistry = new MockAssetRegistry();
        vm.label(address(assetRegistry), "assetRegistry");
        vm.prank(address(basketManager));
        basket.setAssetRegistry(address(assetRegistry));
    }

    function test_initialize() public view {
        assertEq(basket.asset(), address(dummyAsset));
        assertEq(basket.name(), string.concat("CoveBasket-", "Test"));
        assertEq(basket.symbol(), string.concat("cb", "TEST"));
        assertEq(basket.basketManager(), address(basketManager));
        assertEq(basket.asset(), address(dummyAsset));
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

    function test_requestDeposit_passWhen_pendingDepositRequest() public {
        // vm.assume(amount > 0 && amount2 > 0 && amount + amount2 < type(uint256).max); // TODO: overflows
        // bound(amount, 0, type(uint256).max / 2);
        // bound(amount2, 0, type(uint256).max/ 2);
        uint256 amount = 1e22;
        uint256 amount2 = 1e20;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
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
        vm.expectRevert(abi.encodeWithSelector(Errors.MustClaimOutstandingDeposit.selector));
        vm.startPrank(alice);
        basket.requestDeposit(amount, alice);
    }

    function test_requestDeposit_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        assetRegistry.pauseAssets();
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetPaused.selector));
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
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroPendingDeposits.selector));
        vm.prank(address(basketManager));
        basket.fulfillDeposit(1e18);
    }

    function test_fulfillDeposit_revertsWhen_notBasketManager() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotBasketManager.selector));
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
        vm.expectRevert(abi.encodeWithSelector(Errors.MustClaimFullAmount.selector));
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
        vm.expectRevert(abi.encodeWithSelector(Errors.MustClaimFullAmount.selector));
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
        basket.cancelDepositRequest(alice);
        uint256 balanceAfter = dummyAsset.balanceOf(address(alice));
        assertEq(basket.pendingDepositRequest(alice), 0);
        assertEq(balanceAfter, balanceBefore + amount);
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
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetPaused.selector));
        basket.requestRedeem(amount, alice, alice);
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
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount);
        assertEq(basketManagerBalanceBefore - amount, dummyAsset.balanceOf(address(basketManager)));
        assertEq(basketBalanceBefore - userShares, basket.balanceOf(address(basket)));
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.maxRedeem(alice), issuedShares);
        assertEq(basket.maxWithdraw(alice), amount);
    }

    function test_fulfillRedeem_revertsWhen_ZeroPendingRedeems() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroPendingRedeems.selector));
        vm.prank(address(basketManager));
        basket.fulfillRedeem(1e18);
    }

    function test_fulfillRedeem_revertsWhen_notBasketManager() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotBasketManager.selector));
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
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount);
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
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount);
        vm.expectRevert(abi.encodeWithSelector(Errors.MustClaimFullAmount.selector));
        vm.prank(alice);
        basket.redeem(issuedShares - 1, alice, alice);
    }
}

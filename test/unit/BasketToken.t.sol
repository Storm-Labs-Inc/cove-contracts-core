// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { BasketManager } from "./../../src/BasketManager.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { BasketToken } from "src/BasketToken.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Errors } from "src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MockAssetRegistry } from "test/utils/mocks/MockAssetRegistry.sol";
import { MockBasketManager } from "test/utils/mocks/MockBasketManager.sol";

contract BasketTokenTest is BaseTest {
    using FixedPointMathLib for uint256;

    BasketToken public basket;
    BasketToken public basketTokenImplementation;
    MockBasketManager public basketManager;
    MockAssetRegistry public assetRegistry;
    ERC20Mock public dummyAsset;
    address public alice;
    address public owner;

    address[] public froms;
    uint256[] public depositAmounts;
    uint256[] public redeemAmounts;

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        owner = createUser("owner");
        // create dummy asset
        dummyAsset = new ERC20Mock();
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

    function testFuzz_constructor_disablesInitializers(
        address asset,
        uint256 bitFlag,
        uint256 strategyId,
        address owner_
    )
        public
    {
        BasketToken tokenImpl = new BasketToken();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tokenImpl.initialize(ERC20(asset), "Test", "TEST", bitFlag, strategyId, owner_);
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

    function testFuzz_requestDeposit(uint256 amount, address from) public {
        vm.assume(from != address(basket) && from != address(basketManager) && from != address(0));
        amount = bound(amount, 1, type(uint256).max);
        dummyAsset.mint(from, amount);

        uint256 totalAssetsBefore = basket.totalAssets();
        uint256 balanceBefore = basket.balanceOf(from);
        uint256 dummyAssetBalanceBefore = dummyAsset.balanceOf(from);
        uint256 pendingDepositRequestBefore = basket.pendingDepositRequest(from);
        uint256 totalPendingDepositBefore = basket.totalPendingDeposits();
        uint256 maxDepositBefore = basket.maxDeposit(from);
        uint256 maxMintBefore = basket.maxMint(from);

        // Approve and request deposit
        vm.startPrank(from);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, from);
        vm.stopPrank();

        // Check state
        assertEq(dummyAsset.balanceOf(from), dummyAssetBalanceBefore - amount);
        assertEq(basket.totalAssets(), totalAssetsBefore);
        assertEq(basket.balanceOf(from), balanceBefore);
        assertEq(basket.maxDeposit(from), maxDepositBefore);
        assertEq(basket.maxMint(from), maxMintBefore);
        assertEq(basket.pendingDepositRequest(from), pendingDepositRequestBefore + amount);
        assertEq(basket.totalPendingDeposits(), totalPendingDepositBefore + amount);
    }

    function test_requestDeposit_passWhen_pendingDepositRequest() public {
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
        vm.expectRevert(Errors.ZeroAmount.selector);
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
        vm.expectRevert(BasketToken.MustClaimOutstandingDeposit.selector);
        vm.startPrank(alice);
        basket.requestDeposit(amount, alice);
    }

    function test_requestDeposit_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        assetRegistry.pauseAssets();
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestDeposit(amount, alice);
    }

    function testFuzz_fulfillDeposit(uint256 totalAmount, uint256 issuedShares) public {
        // First, requestDeposit from 100 users
        totalAmount = bound(totalAmount, 1, type(uint256).max);
        froms = new address[](100);
        depositAmounts = new uint256[](100);
        uint256 remainingAmount = totalAmount;
        for (uint256 i = 0; i < 100; ++i) {
            froms[i] = createUser(string.concat("user", vm.toString(i)));
            if (remainingAmount == 0) {
                break;
            }
            if (i == 99) {
                depositAmounts[i] = remainingAmount;
            } else {
                depositAmounts[i] = bound(uint256(keccak256(abi.encodePacked(block.timestamp, i))), 1, remainingAmount);
            }
            remainingAmount -= depositAmounts[i];
            if (depositAmounts[i] == 0) {
                continue;
            }
            testFuzz_requestDeposit(depositAmounts[i], froms[i]);
        }
        assertEq(basket.totalPendingDeposits(), totalAmount);

        // Shares minted must be within the range [amount / 1e10, amount * 1e10]
        {
            uint256 minSharesMinted = Math.max(totalAmount / 1e10 + 1, 1);
            uint256 maxSharesMinted = totalAmount > type(uint256).max / 1e10 ? type(uint256).max : totalAmount * 1e10;
            issuedShares = bound(issuedShares, minSharesMinted, maxSharesMinted);
        }

        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        uint256 depositEpochBefore = basket.currentDepositEpoch();
        uint256 basketBalanceOfBefore = basket.balanceOf(address(basket));

        // Call fulfillDeposit
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);

        // Check state
        assertEq(basket.currentDepositEpoch(), depositEpochBefore + 1);
        assertEq(dummyAsset.balanceOf(address(basketManager)), basketManagerBalanceBefore + totalAmount);
        assertEq(basket.balanceOf(address(basket)), basketBalanceOfBefore + issuedShares);

        assertEq(dummyAsset.balanceOf(address(basket)), 0);
        assertEq(dummyAsset.balanceOf(address(basketManager)), totalAmount);
        for (uint256 i = 0; i < 100; ++i) {
            assertEq(basket.pendingDepositRequest(froms[i]), 0);
            assertEq(basket.maxDeposit(froms[i]), depositAmounts[i]);
            assertEq(basket.maxMint(froms[i]), depositAmounts[i].fullMulDiv(issuedShares, totalAmount));
        }
        assertEq(basket.totalPendingDeposits(), 0);
    }

    function testFuzz_fulfillDeposit_revertsWhen_CannotFulfillWithZeroShares(
        uint256 totalAmount,
        address from
    )
        public
    {
        testFuzz_requestDeposit(totalAmount, from);
        vm.expectRevert(BasketToken.CannotFulfillWithZeroShares.selector);
        vm.prank(address(basketManager));
        basket.fulfillDeposit(0);
    }

    function test_fulfillDeposit_revertsWhen_ZeroPendingDeposits() public {
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        vm.prank(address(basketManager));
        basket.fulfillDeposit(1e18);
    }

    function test_fulfillDeposit_revertsWhen_notBasketManager() public {
        vm.expectRevert(_formatAccessControlError(alice, BASKET_MANAGER_ROLE));
        vm.prank(alice);
        basket.fulfillDeposit(1e18);
    }

    function test_pendingDepositRequest_returnsZeroWhenFulfilled() public {
        uint256 amount = 1e18;
        uint256 shares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice);
        vm.stopPrank();
        assertEq(basket.pendingDepositRequest(alice), amount);
        vm.prank(address(basketManager));
        basket.fulfillDeposit(shares);
        assertEq(basket.pendingDepositRequest(alice), 0);
    }

    function testFuzz_deposit(uint256 amount, uint256 issuedShares) public {
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for 100 users
        testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < 100; ++i) {
            if (depositAmounts[i] == 0) {
                continue;
            }
            uint256 userBalanceBefore = basket.balanceOf(froms[i]);
            uint256 maxDeposit = basket.maxDeposit(froms[i]);
            uint256 maxMint = basket.maxMint(froms[i]);

            // Call deposit
            vm.prank(froms[i]);
            basket.deposit(maxDeposit, froms[i]);

            // Check state
            assertEq(basket.balanceOf(froms[i]), userBalanceBefore + maxMint);
            assertEq(basket.maxDeposit(froms[i]), 0);
            assertEq(basket.maxMint(froms[i]), 0);
        }

        // Check state
        uint256 lostShares = basket.balanceOf(address(basket));
        // TODO: establish max loss of shares in edge cases
        assertLe(
            lostShares.fullMulDiv(1e18, issuedShares), 1e18, "Lost shares should be less than 100% of the issued shares"
        );
    }

    function test_deposit_revertsWhen_zeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
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
        vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
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
        vm.expectRevert(Errors.ZeroAmount.selector);
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
        vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
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
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        vm.prank(alice);
        basket.cancelDepositRequest();
    }

    function testFuzz_requestRedeem(uint256 amount, uint256 issuedShares) public {
        testFuzz_deposit(amount, issuedShares);
        redeemAmounts = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            address from = froms[i];
            uint256 userSharesBefore = basket.balanceOf(from);
            if (userSharesBefore == 0) {
                continue;
            }
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 pendingRedeemRequestBefore = basket.pendingRedeemRequest(from);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();

            vm.prank(from);
            basket.requestRedeem(userSharesBefore, from, from);

            assertEq(basket.pendingRedeemRequest(from), pendingRedeemRequestBefore + userSharesBefore);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeemsBefore + userSharesBefore);
            assertEq(basket.balanceOf(from), 0);
            assertEq(basket.balanceOf(address(basket)), basketBalanceOfSelfBefore + userSharesBefore);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);

            redeemAmounts[i] = userSharesBefore;
        }
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

    function test_requestRedeem_passWhen_pendingRedeemRequest() public {
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
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.requestRedeem(0, alice, alice);
    }

    function test_requestRedeem_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        assetRegistry.pauseAssets();
        vm.expectRevert(BasketToken.AssetPaused.selector);
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
        vm.expectRevert(BasketToken.MustClaimOutstandingRedeem.selector);
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
        uint256 currentRedeemEpoch = basket.currentRedeemEpoch();
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        assertEq(
            uint8(basket.redemptionStatus(currentRedeemEpoch)), uint8(BasketToken.RedemptionStatus.REDEEM_PREFULFILLED)
        );
        basket.fulfillRedeem(amount);
        assertEq(
            uint8(basket.redemptionStatus(currentRedeemEpoch)), uint8(BasketToken.RedemptionStatus.REDEEM_FULFILLED)
        );
        assertEq(basketManagerBalanceBefore - amount, dummyAsset.balanceOf(address(basketManager)));
        assertEq(basketBalanceBefore - userShares, basket.balanceOf(address(basket)));
        assertEq(basket.pendingRedeemRequest(alice), 0);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.balanceOf(alice), 0);
        assertEq(basket.maxRedeem(alice), issuedShares);
        assertEq(basket.maxWithdraw(alice), amount);
    }

    function test_pendingRedeemRequest_returnsZeroWhenFulfilled() public {
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
        basket.preFulfillRedeem();
        basket.fulfillRedeem(amount);
        assertEq(basket.pendingRedeemRequest(alice), 0);
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
        vm.expectRevert(BasketToken.PreFulFillRedeemNotCalled.selector);
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
        vm.expectRevert(BasketToken.CurrentlyFulfillingRedeem.selector);
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

    function test_redeem() public {
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
        vm.expectRevert(Errors.ZeroAmount.selector);
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
        vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
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
        vm.expectRevert(Errors.ZeroAmount.selector);
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
        vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
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
        vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
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
        vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
        vm.prank(alice);
        basket.cancelRedeemRequest();
    }

    function test_fallbackCancelRedeemRequest() public {
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
        assertEq(basket.totalPendingRedeems(), issuedShares);
        assertEq(basket.pendingRedeemRequest(alice), issuedShares);
        uint256 currentRedeemEpoch = basket.currentRedeemEpoch();
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        assertEq(basket.totalPendingRedeems(), 0);
        basket.fallbackRedeemTrigger();
        assertEq(
            uint8(basket.redemptionStatus(currentRedeemEpoch)), uint8(BasketToken.RedemptionStatus.FALLBACK_TRIGGERED)
        );
        vm.stopPrank();
        uint256 aliceBalanceBefore = basket.balanceOf(alice);
        assertEq(basket.pendingRedeemRequest(alice), 0);
        vm.prank(alice);
        basket.fallbackCancelRedeemRequest();
        assertEq(basket.balanceOf(alice), aliceBalanceBefore + issuedShares);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.pendingRedeemRequest(alice), 0);
    }

    function test_fallbackCancelRedeemRequest_revertsWhen_fallbackNotTriggered() public {
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
        vm.expectRevert(abi.encodeWithSelector(BasketToken.EpochFallbackNotTriggered.selector));
        basket.fallbackCancelRedeemRequest();
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
        vm.expectRevert(abi.encodeWithSelector(BasketToken.EpochFallbackNotTriggered.selector));
        vm.prank(alice);
        basket.fallbackCancelRedeemRequest();
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.EpochFallbackNotTriggered.selector));
        vm.prank(alice);
        basket.fallbackCancelRedeemRequest();
    }

    function test_cancelRedeemRequest_revertsWhen_fallbackTriggered() public {
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
        assertEq(basket.totalPendingRedeems(), issuedShares);
        assertEq(basket.pendingRedeemRequest(alice), issuedShares);
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        assertEq(basket.totalPendingRedeems(), 0);
        basket.fallbackRedeemTrigger();
        vm.stopPrank();
        assertEq(basket.pendingRedeemRequest(alice), 0);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingRedeems.selector));
        vm.prank(alice);
        basket.cancelRedeemRequest();
    }

    function test_fallbackRedeemTrigger_revertWhen_PreFulFillRedeemNotCalled() public {
        vm.expectRevert(abi.encodeWithSelector(BasketToken.PreFulFillRedeemNotCalled.selector));
        vm.prank(address(basketManager));
        basket.fallbackRedeemTrigger();
    }

    function test_redeem_revertsWhen_fallbackTriggered() public {
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
        assertEq(basket.totalPendingRedeems(), issuedShares);
        assertEq(basket.pendingRedeemRequest(alice), issuedShares);
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        assertEq(basket.totalPendingRedeems(), 0);
        basket.fallbackRedeemTrigger();
        vm.stopPrank();
        assertEq(basket.pendingRedeemRequest(alice), 0);
        uint256 aliceMaxRedeem = basket.maxRedeem(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        basket.redeem(aliceMaxRedeem, alice, alice);
    }

    function test_previewDeposit_reverts() public {
        vm.expectRevert();
        basket.previewDeposit(1);
    }

    function test_previewMint_reverts() public {
        vm.expectRevert();
        basket.previewMint(1);
    }

    function testFuzz_proRataRedeem(
        uint256 depositAmount,
        address to,
        address from,
        uint256 sharesMinted,
        uint256 sharesToRedeem
    )
        public
    {
        vm.assume(to != address(0));
        vm.assume(from != address(0));
        // 1 <= depositAmount <= type(uint256).max
        // 1 <= sharesMinted <= type(uint256).max
        // depositAmount / 1e18 <= sharesMinted <= depositAmount * 1e18
        depositAmount = bound(depositAmount, 1, type(uint256).max);
        uint256 minSharesMinted = Math.max(depositAmount / 1e18, 1);
        uint256 maxSharesMinted = depositAmount > type(uint256).max / 1e18 ? type(uint256).max : depositAmount * 1e18;
        sharesMinted = bound(sharesMinted, minSharesMinted, maxSharesMinted);

        // Approve and requestDeposit
        dummyAsset.mint(from, depositAmount);
        vm.startPrank(from);
        dummyAsset.approve(address(basket), depositAmount);
        basket.requestDeposit(depositAmount, from);
        vm.stopPrank();

        // FulfillDeposit from BasketManager
        vm.prank(address(basketManager));
        basket.fulfillDeposit(sharesMinted);

        // Deposit
        vm.prank(from);
        basket.deposit(depositAmount, from);
        uint256 acutalMinted = basket.balanceOf(from);
        // Check minted shares
        assertGt(acutalMinted, 0);
        assertLe(acutalMinted, sharesMinted);
        // 1 <= sharesToRedeem <= realSharesMinted <= sharesMinted
        sharesToRedeem = bound(sharesToRedeem, 1, acutalMinted);

        // proRataRedeem
        uint256 totalSupply = basket.totalSupply();
        vm.mockCall(
            address(basketManager),
            abi.encodeCall(BasketManager.proRataRedeem, (totalSupply, sharesToRedeem, to)),
            new bytes(0)
        );
        vm.prank(from);
        basket.proRataRedeem(sharesToRedeem, to, from);
    }

    function testFuzz_proRataRedeem_revertWhen_ERC20InsufficientAllowance(
        uint256 depositAmount,
        address to,
        address from,
        address spender,
        uint256 approveAmount,
        uint256 sharesMinted,
        uint256 sharesToRedeem
    )
        public
    {
        vm.assume(to != address(0));
        vm.assume(from != address(0));
        vm.assume(spender != address(0) && spender != from);
        // 1 <= depositAmount <= type(uint256).max
        // 1 <= sharesMinted <= type(uint256).max
        // depositAmount / 1e18 <= sharesMinted <= depositAmount * 1e18
        depositAmount = bound(depositAmount, 1, type(uint256).max);
        uint256 minSharesMinted = Math.max(depositAmount / 1e18, 1);
        uint256 maxSharesMinted = depositAmount > type(uint256).max / 1e18 ? type(uint256).max : depositAmount * 1e18;
        sharesMinted = bound(sharesMinted, minSharesMinted, maxSharesMinted);

        // Approve and requestDeposit
        dummyAsset.mint(from, depositAmount);
        vm.startPrank(from);
        dummyAsset.approve(address(basket), depositAmount);
        basket.requestDeposit(depositAmount, from);
        vm.stopPrank();

        // FulfillDeposit from BasketManager
        vm.prank(address(basketManager));
        basket.fulfillDeposit(sharesMinted);

        // Deposit
        vm.prank(from);
        basket.deposit(depositAmount, from);
        uint256 acutalMinted = basket.balanceOf(from);
        // Check minted shares
        assertGt(acutalMinted, 0);
        assertLe(acutalMinted, sharesMinted);
        // 1 <= sharesToRedeem <= realSharesMinted <= sharesMinted
        sharesToRedeem = bound(sharesToRedeem, 1, acutalMinted);
        // 0 <= approveAmount <= sharesToRedeem - 1
        approveAmount = bound(approveAmount, 0, sharesToRedeem - 1);
        vm.prank(from);
        basket.approve(spender, approveAmount);

        // proRataRedeem from another user trying to use from's shares
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approveAmount, sharesToRedeem
            )
        );
        basket.proRataRedeem(sharesToRedeem, to, from);
    }
}

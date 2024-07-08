// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { BasketManager } from "./../../src/BasketManager.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
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

    address[] public fuzzedUsers;
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

    function testFuzz_initialize_revertWhen_InvalidInitialization(
        address asset,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId,
        address owner_
    )
        public
    {
        BasketToken tokenImpl = new BasketToken();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tokenImpl.initialize(ERC20(asset), name, symbol, bitFlag, strategyId, owner_);
    }

    function testFuzz_initialize_revertWhen_alreadyInitialized(
        address asset,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId,
        address owner_
    )
        public
    {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        basket.initialize(ERC20(asset), name, symbol, bitFlag, strategyId, owner_);
    }

    function testFuzz_initialize(
        address from,
        address asset,
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId,
        address tokenOwner
    )
        public
    {
        vm.assume(tokenOwner != address(0));
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        vm.mockCall(asset, abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(assetDecimals));

        // Call initialize
        vm.prank(from);
        token.initialize(ERC20(asset), name, symbol, bitFlag, strategyId, tokenOwner);

        // Check state
        assertEq(token.asset(), asset);
        assertEq(token.name(), string.concat("CoveBasket-", name));
        assertEq(token.symbol(), string.concat("covb", symbol));
        assertEq(token.decimals(), assetDecimals);
        assertEq(token.bitFlag(), bitFlag);
        assertEq(token.strategyId(), strategyId);
        assertEq(token.owner(), tokenOwner);
        assertEq(token.basketManager(), from);
    }

    function testFuzz_initialize_revertsWhen_ownerZero(
        address from,
        address asset,
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId
    )
        public
    {
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        vm.mockCall(asset, abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(assetDecimals));

        // Call initialize
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAddress.selector);
        token.initialize(ERC20(asset), name, symbol, bitFlag, strategyId, address(0));
    }

    function testFuzz_setBasketManager(address newBasketManager) public {
        vm.assume(newBasketManager != address(0));
        vm.prank(owner);
        basket.setBasketManager(newBasketManager);
        assertEq(basket.basketManager(), newBasketManager);
    }

    function testFuzz_setBasketManager_revertsWhen_notOwner(address from, address newBasketManager) public {
        vm.assume(newBasketManager != address(0));
        vm.prank(from);
        vm.expectRevert(_formatAccessControlError(from, DEFAULT_ADMIN_ROLE));
        basket.setBasketManager(newBasketManager);
    }

    function test_setBasketManager_revertsWhen_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        basket.setBasketManager(address(0));
    }

    function testFuzz_setAssetRegistry(address newAssetRegistry) public {
        vm.assume(newAssetRegistry != address(0));
        vm.prank(owner);
        basket.setAssetRegistry(newAssetRegistry);
        assertEq(basket.assetRegistry(), newAssetRegistry);
    }

    function testFuzz_setAssetRegistry_revertsWhen_notOwner(address from, address newAssetRegistry) public {
        vm.assume(newAssetRegistry != address(0));
        vm.prank(from);
        vm.expectRevert(_formatAccessControlError(from, DEFAULT_ADMIN_ROLE));
        basket.setAssetRegistry(newAssetRegistry);
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

        // Call requestDeposit twice
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

        // Call requestDeposit while there is an outstanding deposit
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
        totalAmount = bound(totalAmount, 1, type(uint256).max);
        issuedShares = bound(issuedShares, 1, type(uint256).max);
        fuzzedUsers = new address[](100);
        depositAmounts = new uint256[](100);
        uint256 remainingAmount = totalAmount;

        // Call requestDeposit from 100 users with random amounts
        for (uint256 i = 0; i < 100; ++i) {
            fuzzedUsers[i] = createUser(string.concat("user", vm.toString(i)));
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
            testFuzz_requestDeposit(depositAmounts[i], fuzzedUsers[i]);
        }
        assertEq(basket.totalPendingDeposits(), totalAmount);

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
            assertEq(basket.pendingDepositRequest(fuzzedUsers[i]), 0);
            assertEq(basket.maxDeposit(fuzzedUsers[i]), depositAmounts[i]);
            assertEq(basket.maxMint(fuzzedUsers[i]), depositAmounts[i].fullMulDiv(issuedShares, totalAmount));
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

    function testFuzz_fulfillDeposit_revertsWhen_ZeroPendingDeposits(uint256 issuedShares) public {
        assertEq(basket.totalPendingDeposits(), 0);
        vm.prank(address(basketManager));
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        basket.fulfillDeposit(issuedShares);
    }

    function testFuzz_fulfillDeposit_revertsWhen_notBasketManager(address from, uint256 issuedShares) public {
        vm.assume(!basket.hasRole(BASKET_MANAGER_ROLE, from));
        vm.prank(from);
        vm.expectRevert(_formatAccessControlError(from, BASKET_MANAGER_ROLE));
        basket.fulfillDeposit(issuedShares);
    }

    function testFuzz_deposit(uint256 amount, uint256 issuedShares) public {
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for 100 users
        testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < 100; ++i) {
            if (depositAmounts[i] == 0) {
                continue;
            }
            uint256 userBalanceBefore = basket.balanceOf(fuzzedUsers[i]);
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            uint256 maxMint = basket.maxMint(fuzzedUsers[i]);

            // Call deposit
            vm.prank(fuzzedUsers[i]);
            uint256 shares = basket.deposit(maxDeposit, fuzzedUsers[i]);

            // Check state
            assertEq(shares, maxMint);
            assertEq(basket.balanceOf(fuzzedUsers[i]), userBalanceBefore + maxMint);
            assertEq(basket.maxDeposit(fuzzedUsers[i]), 0);
            assertEq(basket.maxMint(fuzzedUsers[i]), 0);
        }

        // Check state
        uint256 lostShares = basket.balanceOf(address(basket));
        // TODO: establish max loss of shares in edge cases
        assertLe(
            lostShares.fullMulDiv(1e18, issuedShares), 1e18, "Lost shares should be less than 100% of the issued shares"
        );
    }

    function testFuzz_deposit_revertsWhen_zeroAmount(address from) public {
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.deposit(0, from);
    }

    function testFuzz_deposit_revertsWhen_notClaimingFullOutstandingDeposit(
        address from,
        uint256 amount,
        uint256 issuedShares,
        uint256 claimingAmount
    )
        public
    {
        vm.assume(from != address(0));
        amount = bound(amount, 2, type(uint256).max);
        issuedShares = bound(issuedShares, 1, type(uint256).max);
        claimingAmount = bound(claimingAmount, 1, amount - 1);
        dummyAsset.mint(from, amount);
        vm.startPrank(from);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, from);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);

        // Call deposit with partial amount
        vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
        vm.prank(from);
        basket.deposit(claimingAmount, from);
    }

    function testFuzz_mint(uint256 amount, uint256 issuedShares) public {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < 100; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(from);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 maxMint = basket.maxMint(from);
            if (maxMint == 0) {
                continue;
            }

            // Call mint
            vm.prank(from);
            basket.mint(maxMint, from);

            // Check state
            assertEq(basket.balanceOf(from), userBalanceBefore + maxMint);
            assertEq(basket.balanceOf(address(basket)), basketBalanceBefore - maxMint);
            assertEq(basket.maxDeposit(from), 0);
            assertEq(basket.maxMint(from), 0);
        }
    }

    function testFuzz_mint_revertsWhen_zeroAmount(address from) public {
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.mint(0, from);
    }

    function testFuzz_mint_revertsWhen_notClaimingFullOutstandingDeposit(
        address from,
        uint256 amount,
        uint256 issuedShares,
        uint256 claimingShares
    )
        public
    {
        vm.assume(from != address(0));
        amount = bound(amount, 1, type(uint256).max);
        issuedShares = bound(issuedShares, 2, type(uint256).max);
        claimingShares = bound(claimingShares, 1, issuedShares - 1);

        dummyAsset.mint(from, amount);
        vm.startPrank(from);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, from);
        vm.stopPrank();

        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);

        vm.prank(from);
        vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
        basket.mint(claimingShares, from);
    }

    function testFuzz_cancelDepositRequest(address user, uint256 amount) public {
        vm.assume(user != address(0));
        amount = bound(amount, 1, type(uint256).max);

        dummyAsset.mint(user, amount);
        vm.startPrank(user);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, user);
        assertEq(basket.pendingDepositRequest(user), amount);
        assertEq(basket.totalPendingDeposits(), amount);
        uint256 balanceBefore = dummyAsset.balanceOf(user);
        basket.cancelDepositRequest();
        uint256 balanceAfter = dummyAsset.balanceOf(user);
        assertEq(basket.pendingDepositRequest(user), 0);
        assertEq(balanceAfter, balanceBefore + amount);
        vm.stopPrank();
    }

    function testFuzz_cancelDepositRequest_revertsWhen_zeroPendingDeposits(address user) public {
        vm.assume(user != address(0));
        vm.prank(user);
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        basket.cancelDepositRequest();
    }

    function testFuzz_requestRedeem(
        uint256 amount,
        uint256 issuedShares,
        address[100] memory callers,
        address[100] memory dests
    )
        public
    {
        testFuzz_deposit(amount, issuedShares);
        for (uint256 i = 0; i < 100; ++i) {
            address from = fuzzedUsers[i];
            address caller = callers[i];
            vm.assume(caller != address(0));
            address to = dests[i];
            vm.assume(to != address(0));

            uint256 userSharesBefore = basket.balanceOf(from);
            if (userSharesBefore == 0) {
                continue;
            }
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 pendingRedeemRequestBefore = basket.pendingRedeemRequest(to);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();
            uint256 sharesToRedeem = bound(userSharesBefore, 1, userSharesBefore);

            vm.prank(from);
            basket.approve(caller, sharesToRedeem);

            vm.prank(caller);
            basket.requestRedeem(sharesToRedeem, to, from);

            assertEq(basket.pendingRedeemRequest(to), pendingRedeemRequestBefore + sharesToRedeem);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeemsBefore + sharesToRedeem);
            assertEq(basket.balanceOf(from), userSharesBefore - sharesToRedeem);
            assertEq(basket.balanceOf(address(basket)), basketBalanceOfSelfBefore + sharesToRedeem);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_requestRedeem(uint256 amount, uint256 issuedShares) public {
        testFuzz_deposit(amount, issuedShares);
        redeemAmounts = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            address from = fuzzedUsers[i];
            uint256 userSharesBefore = basket.balanceOf(from);
            if (userSharesBefore == 0) {
                continue;
            }
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 pendingRedeemRequestBefore = basket.pendingRedeemRequest(from);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();
            uint256 sharesToRedeem = bound(userSharesBefore, 1, userSharesBefore);

            vm.prank(from);
            basket.requestRedeem(sharesToRedeem, from, from);

            assertEq(basket.pendingRedeemRequest(from), pendingRedeemRequestBefore + sharesToRedeem);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeemsBefore + sharesToRedeem);
            assertEq(basket.balanceOf(from), userSharesBefore - sharesToRedeem);
            assertEq(basket.balanceOf(address(basket)), basketBalanceOfSelfBefore + sharesToRedeem);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);

            redeemAmounts[i] = sharesToRedeem;
        }
    }

    function testFuzz_requestRedeem_revertWhen_afterPreFulfillRedeem(uint256 amount, uint256 issuedShares) public {
        testFuzz_preFulfillRedeem(amount, issuedShares);
        for (uint256 i = 0; i < 100; ++i) {
            address from = fuzzedUsers[i];
            uint256 userSharesBefore = basket.balanceOf(from);
            if (userSharesBefore == 0) {
                continue;
            }
            vm.prank(from);
            vm.expectRevert(BasketToken.CurrentlyFulfillingRedeem.selector);
            basket.requestRedeem(userSharesBefore, from, from);
        }
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

    function testFuzz_fulfillRedeem(uint256 amount, uint256 issuedShares, uint256 fulfillAmount) public {
        testFuzz_requestRedeem(amount, issuedShares);

        uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();
        vm.assume(totalPendingRedeemsBefore != 0);
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        fulfillAmount = bound(fulfillAmount, 1, basketManagerBalanceBefore);
        uint256 basketBalanceBefore = basket.balanceOf(address(basket));
        uint256 currentRedeemEpoch = basket.currentRedeemEpoch();
        assertEq(uint8(basket.redemptionStatus(currentRedeemEpoch)), uint8(BasketToken.RedemptionStatus.OPEN));

        // Call preFulfillRedeem and fulfillRedeem
        vm.startPrank(address(basketManager));
        basket.preFulfillRedeem();
        assertEq(
            uint8(basket.redemptionStatus(currentRedeemEpoch)), uint8(BasketToken.RedemptionStatus.REDEEM_PREFULFILLED)
        );
        basket.fulfillRedeem(fulfillAmount);
        assertEq(
            uint8(basket.redemptionStatus(currentRedeemEpoch)), uint8(BasketToken.RedemptionStatus.REDEEM_FULFILLED)
        );
        vm.stopPrank();

        // Check state
        assertEq(dummyAsset.balanceOf(address(basketManager)), basketManagerBalanceBefore - fulfillAmount);
        assertEq(basket.balanceOf(address(basket)), basketBalanceBefore - totalPendingRedeemsBefore);
        assertEq(basket.totalPendingRedeems(), 0);
        for (uint256 i = 0; i < 100; ++i) {
            assertEq(basket.pendingRedeemRequest(fuzzedUsers[i]), 0);
            assertEq(basket.maxRedeem(fuzzedUsers[i]), redeemAmounts[i]);
            assertEq(
                basket.maxWithdraw(fuzzedUsers[i]),
                redeemAmounts[i].fullMulDiv(fulfillAmount, totalPendingRedeemsBefore)
            );
        }
    }

    function testFuzz_preFulfillRedeem(uint256 totalAmount, uint256 issuedShares) public {
        testFuzz_requestRedeem(totalAmount, issuedShares);

        uint256 pendingSharesBefore = basket.totalPendingRedeems();
        vm.assume(pendingSharesBefore != 0);

        uint256 redeemEpochBefore = basket.currentRedeemEpoch();
        vm.prank(address(basketManager));

        // Call preFulfillRedeem
        uint256 preFulfilledShares = basket.preFulfillRedeem();

        // Check state
        assertEq(preFulfilledShares, pendingSharesBefore);
        assertEq(basket.totalPendingRedeems(), 0);
        assertEq(basket.currentRedeemEpoch(), redeemEpochBefore + 1);
        assertEq(
            uint8(basket.redemptionStatus(redeemEpochBefore)), uint8(BasketToken.RedemptionStatus.REDEEM_PREFULFILLED)
        );
    }

    function test_preFulfillRedeem_returnsZeroWhen_ZeroPendingRedeems() public {
        assertEq(basket.totalPendingRedeems(), 0);
        vm.prank(address(basketManager));
        assertEq(basket.preFulfillRedeem(), 0);
    }

    function testFuzz_fulfillRedeem_revertsWhen_preFulfillRedeem_notCalled(
        uint256 amount,
        uint256 issuedShares,
        uint256 fulfillAmount
    )
        public
    {
        testFuzz_requestRedeem(amount, issuedShares);
        vm.startPrank(address(basketManager));
        vm.expectRevert(BasketToken.PreFulFillRedeemNotCalled.selector);
        basket.fulfillRedeem(fulfillAmount);
        vm.stopPrank();
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

    function testFuzz_redeem(uint256 totalDepositAmount, uint256 issuedShares, uint256 redeemAmount) public {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < 100; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            if (maxRedeem == 0) {
                continue;
            }

            // Call redeem
            vm.prank(from);
            uint256 assets = basket.redeem(maxRedeem, from, from);

            // Check state
            assertEq(assets, maxWithdraw);
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
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

    function testFuzz_withdraw(uint256 totalDepositAmount, uint256 issuedShares, uint256 redeemAmount) public {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < 100; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            if (maxWithdraw == 0) {
                continue;
            }

            // Call redeem
            vm.prank(from);
            basket.withdraw(maxWithdraw, from, from);

            // Check state
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
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

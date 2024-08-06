// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { BasketManager } from "./../../src/BasketManager.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { Errors } from "src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { ERC20DecimalsMockImpl } from "test/utils/mocks/ERC20DecimalsMockImpl.sol";
import { MockBasketManager } from "test/utils/mocks/MockBasketManager.sol";

contract BasketTokenTest is BaseTest {
    using FixedPointMathLib for uint256;

    uint256 private constant MAX_USERS = 20;

    BasketToken public basket;
    BasketToken public basketTokenImplementation;
    MockBasketManager public basketManager;
    ERC20Mock public dummyAsset;
    address public assetRegistry;
    address public alice;
    address public owner;

    address[] public fuzzedUsers;
    uint256[] public depositAmounts;

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
        assetRegistry = createUser("assetRegistry");
        vm.label(address(assetRegistry), "assetRegistry");
        vm.prank(address(owner));
        basket.setAssetRegistry(address(assetRegistry));

        // mock call to return ENABLED for the dummyAsset
        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(uint8(AssetRegistry.AssetStatus.ENABLED))
        );
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
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId,
        address tokenAdmin
    )
        public
    {
        vm.assume(tokenAdmin != address(0));
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        // Added mock due to foundry test issue
        ERC20DecimalsMockImpl mockERC20 = new ERC20DecimalsMockImpl(assetDecimals, "test", "TST");
        // Call initialize
        vm.prank(from);
        token.initialize(ERC20(mockERC20), name, symbol, bitFlag, strategyId, tokenAdmin);

        // Check state
        assertEq(token.asset(), address(mockERC20));
        assertEq(token.name(), string.concat("CoveBasket-", name));
        assertEq(token.symbol(), string.concat("covb", symbol));
        assertEq(token.decimals(), assetDecimals);
        assertEq(token.bitFlag(), bitFlag);
        assertEq(token.strategyId(), strategyId);
        assertEq(token.admin(), tokenAdmin);
        assertEq(token.basketManager(), from);
        assertEq(token.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(token.supportsInterface(OPERATOR7540_INTERFACE), true);
        assertEq(token.supportsInterface(ASYNCHRONOUS_DEPOSIT_INTERFACE), true);
        assertEq(token.supportsInterface(ASYNCHRONOUS_REDEMPTION_INTERFACE), true);
    }

    function testFuzz_initialize_revertsWhen_ownerZero(
        address from,
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId
    )
        public
    {
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        // Added mock due to foundry test issue
        ERC20DecimalsMockImpl mockERC20 = new ERC20DecimalsMockImpl(assetDecimals, "test", "TST");

        // Call initialize
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAddress.selector);
        token.initialize(ERC20(mockERC20), name, symbol, bitFlag, strategyId, address(0));
    }

    function testFuzz_setBasketManager(address newBasketManager) public {
        vm.assume(newBasketManager != address(0));
        vm.prank(owner);
        basket.setBasketManager(newBasketManager);
        assertEq(basket.basketManager(), newBasketManager);
    }

    function testFuzz_setBasketManager_revertsWhen_notOwner(address from, address newBasketManager) public {
        vm.assume(newBasketManager != address(0) && from != address(owner));
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
        basket.requestDeposit(amount, from, from);
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

    function testFuzz_requestDeposit_withController(uint256 amount, address from, address controller) public {
        vm.assume(
            from != address(basket) && from != address(basketManager) && from != address(0) && controller != address(0)
                && from != controller
        );
        amount = bound(amount, 1, type(uint256).max);
        dummyAsset.mint(from, amount);

        uint256 totalAssetsBefore = basket.totalAssets();
        uint256 balanceBefore = basket.balanceOf(from);
        uint256 dummyAssetBalanceBefore = dummyAsset.balanceOf(from);
        uint256 pendingDepositRequestBefore = basket.pendingDepositRequest(from);
        uint256 totalPendingDepositBefore = basket.totalPendingDeposits();
        uint256 maxDepositBefore = basket.maxDeposit(controller);
        uint256 maxMintBefore = basket.maxMint(controller);

        // Approve and request deposit
        vm.startPrank(from);
        basket.setOperator(controller, true);
        dummyAsset.approve(address(basket), amount);
        vm.stopPrank();
        vm.prank(controller);
        basket.requestDeposit(amount, controller, from);

        // Check state
        assertEq(dummyAsset.balanceOf(from), dummyAssetBalanceBefore - amount);
        assertEq(basket.totalAssets(), totalAssetsBefore);
        assertEq(basket.balanceOf(controller), balanceBefore);
        assertEq(basket.maxDeposit(controller), maxDepositBefore);
        assertEq(basket.maxMint(controller), maxMintBefore);
        assertEq(basket.pendingDepositRequest(controller), pendingDepositRequestBefore + amount);
        assertEq(basket.totalPendingDeposits(), totalPendingDepositBefore + amount);
    }

    function test_requestDeposit_passWhen_pendingDepositRequest() public {
        uint256 amount = 1e22;
        uint256 amount2 = 1e20;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);

        // Call requestDeposit twice
        basket.requestDeposit(amount, alice, alice);
        assertEq(basket.pendingDepositRequest(alice), amount);
        assertEq(basket.totalPendingDeposits(), amount);
        dummyAsset.mint(alice, amount2);
        dummyAsset.approve(address(basket), amount2);
        basket.requestDeposit(amount2, alice, alice);
        assertEq(basket.pendingDepositRequest(alice), amount + amount2);
        assertEq(basket.totalPendingDeposits(), amount + amount2);
    }

    function test_requestDeposit_revertWhen_zeroAmount() public {
        vm.prank(alice);
        dummyAsset.approve(address(basket), 0);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(alice);
        basket.requestDeposit(0, alice, alice);
    }

    function test_requestDeposit_revertWhen_claimableDepositOutstanding() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);

        // Call requestDeposit while there is an outstanding deposit
        vm.expectRevert(BasketToken.MustClaimOutstandingDeposit.selector);
        vm.startPrank(alice);
        basket.requestDeposit(amount, alice, alice);
    }

    function test_requestDeposit_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(uint8(AssetRegistry.AssetStatus.PAUSED))
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestDeposit(amount, alice, alice);
    }

    function test_requestDeposit_revertWhen_assetDisabled() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(uint8(AssetRegistry.AssetStatus.DISABLED))
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestDeposit(amount, alice, alice);
    }

    function testFuzz_requestDeposit_revertWhen_invalidAssetStatus(uint8 status) public {
        vm.assume(status > 2);
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(status)
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert();
        basket.requestDeposit(amount, alice, alice);
    }

    function testFuzz_fulfillDeposit(uint256 totalAmount, uint256 issuedShares) public {
        totalAmount = bound(totalAmount, 1, type(uint256).max);
        issuedShares = bound(issuedShares, 1, type(uint256).max);
        fuzzedUsers = new address[](MAX_USERS);
        depositAmounts = new uint256[](MAX_USERS);
        uint256 remainingAmount = totalAmount;

        // Call requestDeposit from users with random amounts
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            fuzzedUsers[i] = createUser(string.concat("user", vm.toString(i)));
            // Ignore the cases where a user ends up with zero deposit amount
            vm.assume(remainingAmount > 1);
            if (i == MAX_USERS - 1) {
                depositAmounts[i] = remainingAmount;
            } else {
                depositAmounts[i] =
                    bound(uint256(keccak256(abi.encodePacked(block.timestamp, i))), 1, remainingAmount - 1);
            }
            remainingAmount -= depositAmounts[i];
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
        for (uint256 i = 0; i < MAX_USERS; ++i) {
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
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for users
        testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Skip users with zero deposit amount. This is to avoid ZeroAmount error
            // Zero deposit amount happens due to splitting the total deposit amount among users
            uint256 userBalanceBefore = basket.balanceOf(fuzzedUsers[i]);
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            uint256 maxMint = basket.maxMint(fuzzedUsers[i]);
            assertGt(depositAmounts[i], 0, "users should have non-zero deposit amount before testing");
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0 if user has pending deposit");
            assertGt(basket.claimableDepositRequest(0, fuzzedUsers[i]), 0, "User should have claimable deposit request");

            // Call deposit
            vm.prank(fuzzedUsers[i]);
            uint256 shares = basket.deposit(maxDeposit, fuzzedUsers[i], fuzzedUsers[i]);

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

    function testFuzz_deposit_operator(uint256 amount, uint256 issuedShares, address operator) public {
        vm.assume(operator != address(0));
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for users
        testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Skip users with zero deposit amount. This is to avoid ZeroAmount error
            // Zero deposit amount happens due to splitting the total deposit amount among users
            uint256 userBalanceBefore = basket.balanceOf(fuzzedUsers[i]);
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            uint256 maxMint = basket.maxMint(fuzzedUsers[i]);
            assertGt(depositAmounts[i], 0, "users should have non-zero deposit amount before testing");
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0 if user has pending deposit");
            assertGt(basket.claimableDepositRequest(0, fuzzedUsers[i]), 0, "User should have claimable deposit request");

            // setOperator
            vm.prank(fuzzedUsers[i]);
            basket.setOperator(operator, true);
            // Call deposit from operator
            vm.prank(operator);
            uint256 shares = basket.deposit(maxDeposit, fuzzedUsers[i], fuzzedUsers[i]);

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

    function testFuzz_deposit_revertWhen_operatorNotSet(
        uint256 amount,
        uint256 issuedShares,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for users
        testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Skip users with zero deposit amount. This is to avoid ZeroAmount error
            // Zero deposit amount happens due to splitting the total deposit amount among users
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            assertGt(depositAmounts[i], 0, "users should have non-zero deposit amount before testing");
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0 if user has pending deposit");
            assertGt(basket.claimableDepositRequest(0, fuzzedUsers[i]), 0, "User should have claimable deposit request");

            assert(!basket.isOperator(fuzzedUsers[i], operator));
            // Call deposit from operator
            vm.expectRevert();
            vm.prank(operator);
            basket.deposit(maxDeposit, fuzzedUsers[i], fuzzedUsers[i]);
        }
    }

    function testFuzz_deposit_revertsWhen_zeroAmount(address from) public {
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.deposit(0, from, from);
    }

    function testFuzz_deposit_revertsWhen_notClaimingFullOutstandingDeposit(
        uint256 amount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxDeposit = basket.maxDeposit(from);
            vm.assume(maxDeposit > 1);
            uint256 claimingAmount = bound(uint256(keccak256(abi.encode(maxDeposit))), 1, maxDeposit - 1);

            // Call deposit with partial amount
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            vm.prank(from);
            basket.deposit(claimingAmount, from, from);
        }
    }

    function testFuzz_mint(uint256 amount, uint256 issuedShares) public {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(from);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 maxDeposit = basket.maxDeposit(from);
            uint256 maxMint = basket.maxMint(from);
            // TODO: Allow 0 as shares value when `mint` is called
            // In case of "bad" assets to shares ratio, maxMint can be zero despite non zero assets deposited.
            // This will block future deposits from this user since their pending deposits cannot be ressetted to 0.
            // Therefore we need a way to allow 0 as shares value when `mint` is called.
            vm.assume(maxMint > 0);

            // Call mint
            vm.prank(from);
            assertEq(basket.mint(maxMint, from, from), maxDeposit);

            // Check state
            assertEq(basket.balanceOf(from), userBalanceBefore + maxMint);
            assertEq(basket.balanceOf(address(basket)), basketBalanceBefore - maxMint);
            assertEq(basket.maxDeposit(from), 0);
            assertEq(basket.maxMint(from), 0);
        }
    }

    function testFuzz_mint_operator(uint256 amount, uint256 issuedShares, address operator) public {
        vm.assume(operator != address(0));
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(from);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 maxDeposit = basket.maxDeposit(from);
            uint256 maxMint = basket.maxMint(from);
            // TODO: Allow 0 as shares value when `mint` is called
            // In case of "bad" assets to shares ratio, maxMint can be zero despite non zero assets deposited.
            // This will block future deposits from this user since their pending deposits cannot be ressetted to 0.
            // Therefore we need a way to allow 0 as shares value when `mint` is called.
            vm.assume(maxMint > 0);

            // Set Operator
            vm.prank(from);
            basket.setOperator(operator, true);

            // Call mint
            vm.prank(operator);
            assertEq(basket.mint(maxMint, from, from), maxDeposit);

            // Check state
            assertEq(basket.balanceOf(from), userBalanceBefore + maxMint);
            assertEq(basket.balanceOf(address(basket)), basketBalanceBefore - maxMint);
            assertEq(basket.maxDeposit(from), 0);
            assertEq(basket.maxMint(from), 0);
        }
    }

    function testFuzz_mint_revertWhen_operatorNotSet(uint256 amount, uint256 issuedShares, address operator) public {
        vm.assume(operator != address(0));
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxMint = basket.maxMint(from);
            // TODO: Allow 0 as shares value when `mint` is called
            // In case of "bad" assets to shares ratio, maxMint can be zero despite non zero assets deposited.
            // This will block future deposits from this user since their pending deposits cannot be ressetted to 0.
            // Therefore we need a way to allow 0 as shares value when `mint` is called.
            vm.assume(maxMint > 0);

            // Set Operator
            assert(!basket.isOperator(from, operator));

            // Call mint
            vm.expectRevert();
            vm.prank(operator);
            basket.mint(maxMint, from, from);
        }
    }

    function testFuzz_mint_revertsWhen_zeroAmount(address from) public {
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.mint(0, from, from);
    }

    function testFuzz_mint_revertsWhen_notClaimingFullOutstandingDeposit(
        uint256 amount,
        uint256 issuedShares,
        uint256 claimingShares
    )
        public
    {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxMint = basket.maxMint(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(maxMint > 1);
            claimingShares = bound(claimingShares, 1, maxMint - 1);

            vm.prank(from);
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            basket.mint(claimingShares, from, from);
        }
    }

    function testFuzz_cancelDepositRequest(uint256 amount, address from) public {
        vm.assume(from != address(basket) && from != address(basketManager) && from != address(0));
        testFuzz_requestDeposit(amount, from);
        uint256 requestAmount = basket.pendingDepositRequest(from);
        uint256 balanceBefore = dummyAsset.balanceOf(from);

        // Call cancelDepositRequest
        vm.prank(from);
        basket.cancelDepositRequest();

        // Check state
        assertEq(basket.pendingDepositRequest(from), 0);
        assertEq(dummyAsset.balanceOf(from), balanceBefore + requestAmount);
    }

    function testFuzz_cancelDepositRequest_revertsWhen_zeroPendingDeposits(address user) public {
        vm.assume(user != address(0));
        vm.prank(user);
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        basket.cancelDepositRequest();
    }

    function _testFuzz_requestRedeem(address[MAX_USERS] memory callers, address[MAX_USERS] memory dests) internal {
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            address caller = callers[i];
            address to = dests[i];
            vm.assume(caller != address(0) && to != address(0));

            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignores the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 pendingRedeemRequestBefore = basket.pendingRedeemRequest(to);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userSharesBefore))), 1, userSharesBefore);

            // Approve tokens to be used by the caller
            vm.prank(from);
            basket.approve(caller, sharesToRedeem);

            // Call requestRedeem
            vm.prank(caller);
            basket.requestRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(to), pendingRedeemRequestBefore + sharesToRedeem);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeemsBefore + sharesToRedeem);
            assertEq(basket.balanceOf(from), userSharesBefore - sharesToRedeem);
            assertEq(basket.balanceOf(address(basket)), basketBalanceOfSelfBefore + sharesToRedeem);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function _testFuzz_requestRedeem_setOperator(
        address[MAX_USERS] memory callers,
        address[MAX_USERS] memory dests
    )
        internal
    {
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            address caller = callers[i];
            address to = dests[i];
            vm.assume(caller != address(0) && to != address(0));

            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignores the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 pendingRedeemRequestBefore = basket.pendingRedeemRequest(to);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userSharesBefore))), 1, userSharesBefore);

            // Approve set caller as the operator
            vm.prank(from);
            basket.setOperator(caller, true);

            // Call requestRedeem
            vm.prank(caller);
            basket.requestRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(to), pendingRedeemRequestBefore + sharesToRedeem);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeemsBefore + sharesToRedeem);
            assertEq(basket.balanceOf(from), userSharesBefore - sharesToRedeem);
            assertEq(basket.balanceOf(address(basket)), basketBalanceOfSelfBefore + sharesToRedeem);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_requestRedeem(
        uint256 amount,
        uint256 issuedShares,
        address[MAX_USERS] memory callers,
        address[MAX_USERS] memory dests
    )
        public
    {
        testFuzz_deposit(amount, issuedShares);
        _testFuzz_requestRedeem(callers, dests);
    }

    function testFuzz_requestRedeem(uint256 amount, uint256 issuedShares) public {
        testFuzz_deposit(amount, issuedShares);
        address[MAX_USERS] memory users_;
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            users_[i] = fuzzedUsers[i];
        }
        _testFuzz_requestRedeem(users_, users_);
    }

    function testFuzz_requestRedeem_revertWhen_afterPreFulfillRedeem(uint256 amount, uint256 issuedShares) public {
        testFuzz_preFulfillRedeem(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            vm.prank(from);
            vm.expectRevert(BasketToken.CurrentlyFulfillingRedeem.selector);
            basket.requestRedeem(userSharesBefore, from, from);
        }
    }

    function testFuzz_requestRedeem_passWhen_pendingRedeemRequest(uint256 amount, uint256 issuedShares) public {
        testFuzz_requestRedeem(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            uint256 userPendingRequest = basket.pendingRedeemRequest(from);
            uint256 totalPendingRedeems = basket.totalPendingRedeems();
            uint256 sharesToRequest = bound(uint256(keccak256(abi.encode(userSharesBefore))), 1, userSharesBefore);

            // Call requestRedeem
            vm.prank(from);
            basket.requestRedeem(sharesToRequest, from, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(from), userPendingRequest + sharesToRequest);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeems + sharesToRequest);
        }
    }

    function test_requestRedeem_revertWhen_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.requestRedeem(0, alice, alice);
    }

    function test_requestRedeem_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(uint8(AssetRegistry.AssetStatus.PAUSED))
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestRedeem(amount, alice, alice);
    }

    function test_requestRedeem_revertWhen_assetDisabled() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(uint8(AssetRegistry.AssetStatus.DISABLED))
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestRedeem(amount, alice, alice);
    }

    function testFuzz_requestRedeem_revertWhen_invalidAssetStatus(uint8 status) public {
        vm.assume(status > 2);
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry),
            abi.encodeCall(AssetRegistry.getAssetStatus, (address(dummyAsset))),
            abi.encode(status)
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert();
        basket.requestRedeem(amount, alice, alice);
    }

    function test_requestRedeem_revertWhen_outstandingRedeem() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice, alice);
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

        uint256[] memory redeemShares = new uint256[](MAX_USERS);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            redeemShares[i] = basket.pendingRedeemRequest(fuzzedUsers[i]);
        }

        uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();
        assertGt(totalPendingRedeemsBefore, 0, "Total pending redeems should be greater than 0 for this test");
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
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            assertEq(basket.pendingRedeemRequest(fuzzedUsers[i]), 0);
            assertEq(basket.claimableRedeemRequest(0, fuzzedUsers[i]), redeemShares[i]);
            assertEq(basket.maxRedeem(fuzzedUsers[i]), redeemShares[i]);
            assertEq(
                basket.maxWithdraw(fuzzedUsers[i]), redeemShares[i].fullMulDiv(fulfillAmount, totalPendingRedeemsBefore)
            );
        }
    }

    function testFuzz_preFulfillRedeem(uint256 totalAmount, uint256 issuedShares) public {
        testFuzz_requestRedeem(totalAmount, issuedShares);

        uint256 pendingSharesBefore = basket.totalPendingRedeems();
        assertGt(pendingSharesBefore, 0, "Total pending redeems should be greater than 0 for this test");

        uint256 redeemEpochBefore = basket.currentRedeemEpoch();

        uint256[] memory pendingShares = new uint256[](MAX_USERS);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            pendingShares[i] = basket.pendingRedeemRequest(from);
            assertGt(pendingShares[i], 0, "Pending redeem request should be greater than 0");
        }

        // Call preFulfillRedeem
        vm.prank(address(basketManager));
        uint256 preFulfilledShares = basket.preFulfillRedeem();

        // Check state
        assertEq(
            preFulfilledShares, pendingSharesBefore, "PreFulfilled shares should be equal to total pending redeems"
        );
        assertEq(basket.totalPendingRedeems(), 0, "Total pending redeems should be 0 after preFulfillRedeem");
        assertEq(basket.currentRedeemEpoch(), redeemEpochBefore + 1, "Current redeem epoch should be incremented");
        assertEq(
            uint8(basket.redemptionStatus(redeemEpochBefore)),
            uint8(BasketToken.RedemptionStatus.REDEEM_PREFULFILLED),
            "Redemption status should be REDEEM_PREFULFILLED after preFulfillRedeem"
        );
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            assertEq(
                basket.pendingRedeemRequest(fuzzedUsers[i]),
                0,
                "Pending redeem requests should be 0 after preFulfillRedeem"
            );
        }
    }

    function testFuzz_preFulfillRedeem_revertsWhen_MustWaitForPreviousRedeemEpoch(
        uint256 totalAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_preFulfillRedeem(totalAmount, issuedShares);
        vm.expectRevert(BasketToken.MustWaitForPreviousRedeemEpoch.selector);
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
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

    function testFuzz_requestRedeem_passWhen_afterRedeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_redeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userPendingRequest = basket.pendingRedeemRequest(from);
            uint256 totalPendingRedeems = basket.totalPendingRedeems();
            uint256 userBalanceBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userBalanceBefore > 0);

            uint256 sharesToRequest = bound(uint256(keccak256(abi.encode(userBalanceBefore))), 1, userBalanceBefore);

            // Call requestRedeem
            vm.prank(from);
            basket.requestRedeem(sharesToRequest, from, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(from), userPendingRequest + sharesToRequest);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeems + sharesToRequest);
        }
    }

    function testFuzz_requestRedeem_passWhen_afterWithdraw(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_withdraw(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userPendingRequest = basket.pendingRedeemRequest(from);
            uint256 totalPendingRedeems = basket.totalPendingRedeems();
            uint256 userBalanceBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userBalanceBefore > 0);

            uint256 sharesToRequest = bound(uint256(keccak256(abi.encode(userBalanceBefore))), 1, userBalanceBefore);

            // Call requestRedeem
            vm.prank(from);
            basket.requestRedeem(sharesToRequest, from, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(from), userPendingRequest + sharesToRequest);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeems + sharesToRequest);
        }
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
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Previous tests ensures that the user has non zero shares to redeem
            assertGt(maxRedeem, 0, "Max redeem should be greater than 0 for this test");

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

    function testFuzz_redeem_operator(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Previous tests ensures that the user has non zero shares to redeem
            assertGt(maxRedeem, 0, "Max redeem should be greater than 0 for this test");

            // Set operator
            vm.prank(from);
            basket.setOperator(operator, true);

            // Call redeem
            vm.prank(operator);
            uint256 assets = basket.redeem(maxRedeem, from, from);

            // Check state
            assertEq(assets, maxWithdraw);
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_redeem_revertWhen_operatorNotSet(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxRedeem = basket.maxRedeem(from);
            // Previous tests ensures that the user has non zero shares to redeem
            assertGt(maxRedeem, 0, "Max redeem should be greater than 0 for this test");

            // Set operator
            assert(!basket.isOperator(from, operator));

            // Call redeem
            vm.expectRevert();
            vm.prank(operator);
            basket.redeem(maxRedeem, from, from);
        }
    }

    function test_redeem_revertsWhen_zeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(alice);
        basket.redeem(0, alice, alice);
    }

    function testFuzz_redeem_revertsWhen_notClaimingFullOutstandingRedeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxRedeem = basket.maxRedeem(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            vm.assume(maxRedeem > 1);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(maxRedeem))), 1, maxRedeem - 1);

            // Call redeem
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            vm.prank(from);
            basket.redeem(sharesToRedeem, from, from);
        }
    }

    function testFuzz_withdraw(uint256 totalDepositAmount, uint256 issuedShares, uint256 redeemAmount) public {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            // TODO: Allow 0 as assets value when `withdraw` is called
            // In case of "bad" assets to shares ratio, maxWithdraw can be zero despite non zero shares redeemed.
            // This will block future redeems from this user since their pending redeems cannot be ressetted to 0.
            // Therefore we need a way to allow 0 as assets value when `withdraw` is called to ensure that the user's
            // pending redeems can be reset to 0.
            vm.assume(maxWithdraw > 0);

            // Call redeem
            vm.prank(from);
            assertEq(basket.withdraw(maxWithdraw, from, from), maxRedeem);

            // Check state
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_withdraw_operator(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            // TODO: Allow 0 as assets value when `withdraw` is called
            // In case of "bad" assets to shares ratio, maxWithdraw can be zero despite non zero shares redeemed.
            // This will block future redeems from this user since their pending redeems cannot be ressetted to 0.
            // Therefore we need a way to allow 0 as assets value when `withdraw` is called to ensure that the user's
            // pending redeems can be reset to 0.
            vm.assume(maxWithdraw > 0);

            // Set operator
            vm.prank(from);
            basket.setOperator(operator, true);

            // Call redeem
            vm.prank(operator);
            assertEq(basket.withdraw(maxWithdraw, from, from), maxRedeem);

            // Check state
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_withdraw_revertWhen_operatorNotSet(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            // TODO: Allow 0 as assets value when `withdraw` is called
            // In case of "bad" assets to shares ratio, maxWithdraw can be zero despite non zero shares redeemed.
            // This will block future redeems from this user since their pending redeems cannot be ressetted to 0.
            // Therefore we need a way to allow 0 as assets value when `withdraw` is called to ensure that the user's
            // pending redeems can be reset to 0.
            vm.assume(maxWithdraw > 0);

            assert(!basket.isOperator(fuzzedUsers[i], operator));

            // Call redeem
            vm.expectRevert();
            vm.prank(operator);
            basket.withdraw(maxWithdraw, from, from);
        }
    }

    function testFuzz_withdraw_revertsWhen_zeroAmount(address caller, address user, address receiver) public {
        vm.assume(caller != address(0) && user != address(0) && receiver != address(0));
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(caller);
        basket.withdraw(0, user, receiver);
    }

    function testFuzz_withdraw_revertsWhen_notClaimingFullOutstandingRedeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            vm.assume(maxWithdraw > 1);
            uint256 sharesToWithdraw = bound(uint256(keccak256(abi.encode(maxWithdraw))), 1, maxWithdraw - 1);

            // Call withdraw with partial amount
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            vm.prank(from);
            basket.withdraw(sharesToWithdraw, from, from);
        }
    }

    function testFuzz_cancelRedeemRequest(uint256 totalDepositAmount, uint256 issuedShares) public {
        testFuzz_requestRedeem(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            uint256 pendingRedeem = basket.pendingRedeemRequest(user);
            uint256 balanceBefore = basket.balanceOf(user);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedeems();

            // Call cancelRedeemRequest
            vm.prank(user);
            basket.cancelRedeemRequest();

            // Check state
            assertEq(basket.pendingRedeemRequest(user), 0);
            assertEq(basket.balanceOf(user), balanceBefore + pendingRedeem);
            assertEq(basket.totalPendingRedeems(), totalPendingRedeemsBefore - pendingRedeem);
        }
    }

    function test_cancelRedeemRequest_revertsWhen_zeroPendingRedeems() public {
        vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
        vm.prank(alice);
        basket.cancelRedeemRequest();
    }

    function testFuzz_cancelRedeemRequest_revertsWhen_preFulfillRedeem_hasBeenCalled(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_preFulfillRedeem(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
            vm.prank(fuzzedUsers[i]);
            basket.cancelRedeemRequest();
        }
    }

    function testFuzz_fallbackRedeemTrigger(uint256 totalDepositAmount, uint256 issuedShares) public {
        testFuzz_preFulfillRedeem(totalDepositAmount, issuedShares);
        uint256 epoch = basket.currentRedeemEpoch();

        // Call fallbackRedeemTrigger
        vm.prank(address(basketManager));
        basket.fallbackRedeemTrigger();
        assertEq(
            uint8(basket.redemptionStatus(epoch - 1)),
            uint8(BasketToken.RedemptionStatus.FALLBACK_TRIGGERED),
            "Redemption status of epoch - 1 should be changed to FALLBACK_TRIGGERED"
        );
        assertEq(basket.currentRedeemEpoch(), epoch, "Epoch should not change");
    }

    function testFuzz_claimFallbackShares(uint256 totalDepositAmount, uint256 issuedShares) public {
        testFuzz_fallbackRedeemTrigger(totalDepositAmount, issuedShares);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(user);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 userClaimable = basket.claimableFallbackShares(user);
            assertEq(basket.pendingRedeemRequest(user), 0, "Pending redeem request after preFulFill should be 0");
            assertGt(userClaimable, 0, "Claimable shares should be greater than 0");

            // Claim fallback shares
            vm.prank(user);
            assertEq(basket.claimFallbackShares(), userClaimable, "Claimed shares should be equal to claimable shares");

            // Check state
            assertEq(
                basket.balanceOf(user),
                userBalanceBefore + userClaimable,
                "User balance should increase by claimable shares"
            );
            assertEq(
                basket.balanceOf(address(basket)),
                basketBalanceBefore - userClaimable,
                "Basket balance should decrease by claimable shares"
            );
            assertEq(basket.claimableFallbackShares(user), 0, "Claimable shares should be 0 after claim");
            assertEq(basket.pendingRedeemRequest(user), 0, "Pending redeem request should remain 0 after claim");
        }
    }

    function testFuzz_claimFallbackShares_revertsWhen_fallbackNotTriggered(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_preFulfillRedeem(totalDepositAmount, issuedShares);
        // fallbackRedeemTrigger not called
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];

            // Try calling claim fallback shares
            vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
            vm.prank(user);
            basket.claimFallbackShares();
        }
    }

    function test_claimFallbackShares_revertsWhen_fallbackNotTriggered() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice, alice);
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.fulfillDeposit(issuedShares);
        vm.startPrank(alice);
        basket.deposit(amount, alice, alice);
        basket.requestRedeem(issuedShares, alice, alice);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
        basket.claimFallbackShares();
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.preFulfillRedeem();
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
        vm.prank(alice);
        basket.claimFallbackShares();
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
        vm.prank(alice);
        basket.claimFallbackShares();
    }

    function testFuzz_cancelRedeemRequest_revertsWhen_fallbackTriggered(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_fallbackRedeemTrigger(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingRedeems.selector));
            vm.prank(user);
            basket.cancelRedeemRequest();
        }
    }

    function test_fallbackRedeemTrigger_revertWhen_PreFulFillRedeemNotCalled() public {
        vm.expectRevert(abi.encodeWithSelector(BasketToken.PreFulFillRedeemNotCalled.selector));
        vm.prank(address(basketManager));
        basket.fallbackRedeemTrigger();
    }

    function testFuzz_redeem_revertsWhen_fallbackTriggered(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 sharesToRedeem
    )
        public
    {
        vm.assume(sharesToRedeem != 0);
        testFuzz_fallbackRedeemTrigger(totalDepositAmount, issuedShares);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            // Call redeem
            vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimFullAmount.selector));
            vm.prank(user);
            basket.redeem(sharesToRedeem, user, user);
        }
    }

    function testFuzz_previewDeposit_reverts(uint256 n) public {
        vm.expectRevert();
        basket.previewDeposit(n);
    }

    function testFuzz_previewMint_reverts(uint256 n) public {
        vm.expectRevert();
        basket.previewMint(n);
    }

    function testFuzz_proRataRedeem(uint256 totalDepositAmount, uint256 issuedShares, address to) public {
        vm.assume(to != address(0));
        testFuzz_deposit(totalDepositAmount, issuedShares);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userShares = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userShares > 0);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userShares))), 1, userShares);

            // Mock proRataRedeem
            uint256 totalSupply = basket.totalSupply();
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to),
                abi.encode(0)
            );

            // Call proRataRedeem
            vm.prank(from);
            vm.expectCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to)
            );
            basket.proRataRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(basket.balanceOf(from), userShares - sharesToRedeem);
            assertEq(basket.totalSupply(), totalSupply - sharesToRedeem);
        }
    }

    function testFuzz_proRataRedeem_passWhen_withApproval(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        address caller,
        address to
    )
        public
    {
        vm.assume(caller != address(0) && to != address(0));
        testFuzz_deposit(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userShares = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userShares > 0);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userShares))), 1, userShares);

            // Approve token spend
            vm.prank(from);
            basket.approve(caller, sharesToRedeem);

            // Mock proRataRedeem
            uint256 totalSupply = basket.totalSupply();
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to),
                abi.encode(0)
            );

            // Call proRataRedeem
            vm.prank(caller);
            vm.expectCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to)
            );
            basket.proRataRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(basket.balanceOf(from), userShares - sharesToRedeem);
            assertEq(basket.totalSupply(), totalSupply - sharesToRedeem);
        }
    }

    function testFuzz_proRataRedeem_revertWhen_ERC20InsufficientAllowance(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        address caller,
        address to
    )
        public
    {
        vm.assume(caller != address(0) && to != address(0));
        testFuzz_deposit(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userShares = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userShares > 0);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userShares))), 1, userShares);
            uint256 approveAmount = bound(uint256(keccak256(abi.encode(sharesToRedeem))), 0, sharesToRedeem - 1);

            // Approve token spend
            vm.prank(from);
            basket.approve(caller, approveAmount);

            // Call proRataRedeem
            vm.prank(caller);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, caller, approveAmount, sharesToRedeem
                )
            );
            basket.proRataRedeem(sharesToRedeem, to, from);
        }
    }

    function test_supportsInterface() public {
        assert(basket.supportsInterface(type(IERC165).interfaceId));
        assert(basket.supportsInterface(OPERATOR7540_INTERFACE)); // 0xe3bc4e65
        assert(basket.supportsInterface(ASYNCHRONOUS_DEPOSIT_INTERFACE)); // 0xce3bbe50
        assert(basket.supportsInterface(ASYNCHRONOUS_REDEMPTION_INTERFACE)); // 0x620ee8e4
    }

    function test_share() public {
        assert(basket.share() == address(basket));
    }

    function testFuzz_setOperator(address operator, address controller) public {
        vm.assume(operator != address(0));
        vm.assume(controller != address(0));
        vm.assume(operator != controller);
        vm.startPrank(controller);
        basket.setOperator(operator, true);
        assertEq(basket.isOperator(controller, operator), true);
        basket.setOperator(operator, false);
        assertEq(basket.isOperator(controller, operator), false);
    }
}

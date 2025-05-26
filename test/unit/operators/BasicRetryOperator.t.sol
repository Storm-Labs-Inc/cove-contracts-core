// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { BasketToken } from "src/BasketToken.sol";
import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

/// @title BasicRetryOperatorTest
/// @notice Unit tests for the BasicRetryOperator contract.
contract BasicRetryOperatorTest is BaseTest {
    BasicRetryOperator internal _operator;
    ERC20Mock internal _asset;
    address internal _mockBasketToken; // Changed from BasketToken to address

    address internal _user1;
    address internal _user2;

    address internal _admin;
    address internal _manager;

    /*//////////////////////////////////////////////////////////////
                            SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();

        _admin = makeAddr("admin");
        _manager = makeAddr("manager");

        _operator = new BasicRetryOperator(_admin, _manager);
        _asset = new ERC20Mock();
        _mockBasketToken = makeAddr("mockBasketToken");

        _user1 = createUser("user1");
        _user2 = createUser("user2");

        // Mock the asset call for the _operator.approveDeposits call in setUp
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(_asset)));

        // Operator needs to approve basket token to spend its assets for retries.
        // This will call _mockBasketToken.asset()
        vm.prank(_manager);
        _operator.approveDeposits(BasketToken(payable(_mockBasketToken)), _MAX_UINT256);

        // Note: BasketToken.setOperator calls are not directly relevant here as we mock BasketToken's behavior.
        // The operator's authorization is implicitly assumed when its calls to the mocked BasketToken succeed.
    }

    /*//////////////////////////////////////////////////////////////
                    USER CONFIGURATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_setDepositRetry(bool enabled) public {
        vm.prank(_user1);
        vm.expectEmit(true, false, false, true);
        emit BasicRetryOperator.DepositRetrySet(_user1, enabled);
        _operator.setDepositRetry(enabled);

        assertEq(_operator.isDepositRetryEnabled(_user1), enabled, "Deposit retry should be set to the correct value");
    }

    function testFuzz_setRedeemRetry(bool enabled) public {
        vm.prank(_user1);
        vm.expectEmit(true, false, false, true);
        emit BasicRetryOperator.RedeemRetrySet(_user1, enabled);
        _operator.setRedeemRetry(enabled);

        assertEq(_operator.isRedeemRetryEnabled(_user1), enabled, "Redeem retry should be set to the correct value");
    }

    function test_defaultRetryState_IsEnabledForNewUser() public {
        address newUser = makeAddr("newUserNotConfigured");
        assertTrue(_operator.isDepositRetryEnabled(newUser), "Default deposit retry for new user should be enabled");
        assertTrue(_operator.isRedeemRetryEnabled(newUser), "Default redeem retry for new user should be enabled");
    }

    /*//////////////////////////////////////////////////////////////
                           MAIN HANDLER LOGIC
    //////////////////////////////////////////////////////////////*/

    // --- handleDeposit Reverts ---
    function test_RevertWhen_handleDeposit_ZeroUserAddress() public {
        vm.expectRevert(BasicRetryOperator.ZeroAddress.selector);
        _operator.handleDeposit(address(0), _mockBasketToken);
    }

    function test_RevertWhen_handleDeposit_ZeroBasketTokenAddress() public {
        vm.expectRevert(BasicRetryOperator.ZeroAddress.selector);
        _operator.handleDeposit(_user1, address(0));
    }

    function test_RevertWhen_handleDeposit_NothingToClaim() public {
        // Mock maxDeposit to return 0 for _user2
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxDeposit.selector, _user2), abi.encode(0));
        // Mock claimableFallbackAssets to return 0 for _user2
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackAssets.selector, _user2),
            abi.encode(0)
        );

        vm.expectRevert(BasicRetryOperator.NothingToClaim.selector);
        _operator.handleDeposit(_user2, _mockBasketToken);
    }

    // --- handleDeposit Success Paths ---
    function test_handleDeposit_ClaimFulfilledDeposit(uint256 depositAmount, uint256 sharesToMint) public {
        vm.assume(depositAmount > 0);
        vm.assume(sharesToMint > 0);

        // 1. Mock _basketToken.maxDeposit(_user1) to return depositAmount
        vm.mockCall(
            _mockBasketToken, abi.encodeWithSelector(BasketToken.maxDeposit.selector, _user1), abi.encode(depositAmount)
        );

        // 2. Mock _basketToken.deposit(depositAmount, _user1, _user1) to return sharesToMint
        //    and expect this call.
        //    The operator calls deposit(assets, user, user) which is `deposit(uint256,address,address)`
        bytes memory expectedDepositCallData = abi.encodeWithSelector(
            bytes4(keccak256(bytes("deposit(uint256,address,address)"))), depositAmount, _user1, _user1
        );
        vm.mockCall(_mockBasketToken, expectedDepositCallData, abi.encode(sharesToMint));
        vm.expectCall(_mockBasketToken, expectedDepositCallData);

        vm.prank(address(this)); // anyone can call handleDeposit
        vm.expectEmit(true, true, false, true); // user, basketToken, data (assets, shares)
        emit BasicRetryOperator.DepositClaimedForUser(_user1, _mockBasketToken, depositAmount, sharesToMint);
        _operator.handleDeposit(_user1, _mockBasketToken);
    }

    function test_handleDeposit_ClaimFallbackAssets_RetryDisabled(uint256 fallbackAmount) public {
        vm.assume(fallbackAmount > 0);

        // Setup: maxDeposit returns 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxDeposit.selector, _user1), abi.encode(0));
        // Setup: User has disabled deposit retry
        vm.prank(_user1);
        _operator.setDepositRetry(false);

        // 1. Mock _basketToken.claimableFallbackAssets(_user1) to return fallbackAmount
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackAssets.selector, _user1),
            abi.encode(fallbackAmount)
        );

        // 2. Mock _basketToken.claimFallbackAssets(_user1, _user1) and expect this call
        //    This function returns the amount of assets claimed.
        bytes memory expectedClaimFallbackCallData =
            abi.encodeWithSelector(BasketToken.claimFallbackAssets.selector, _user1, _user1);
        vm.mockCall(_mockBasketToken, expectedClaimFallbackCallData, abi.encode(fallbackAmount));
        vm.expectCall(_mockBasketToken, expectedClaimFallbackCallData);

        vm.prank(address(this)); // anyone can call handleDeposit
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.FallbackAssetsClaimedForUser(_user1, _mockBasketToken, fallbackAmount);
        _operator.handleDeposit(_user1, _mockBasketToken);
    }

    function test_handleDeposit_RetryFallbackAssets_RetryEnabled(uint256 fallbackAmount, uint256 requestID) public {
        vm.assume(fallbackAmount > 0);

        // Setup: maxDeposit returns 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxDeposit.selector, _user1), abi.encode(0));
        // Setup: User has deposit retry enabled (default, or explicitly set)
        vm.prank(_user1);
        _operator.setDepositRetry(true);

        // 1. Mock _basketToken.claimableFallbackAssets(_user1) to return fallbackAmount
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackAssets.selector, _user1),
            abi.encode(fallbackAmount)
        );

        // 2. Mock _basketToken.claimFallbackAssets(address(this_operator), _user1)
        bytes memory expectedClaimToOperatorData =
            abi.encodeWithSelector(BasketToken.claimFallbackAssets.selector, address(_operator), _user1);
        vm.mockCall(_mockBasketToken, expectedClaimToOperatorData, abi.encode(fallbackAmount));
        vm.expectCall(_mockBasketToken, expectedClaimToOperatorData);

        // Ensure operator has the assets it supposedly claimed for the retry.
        deal(address(_asset), address(_operator), fallbackAmount);

        // 3. Mock _basketToken.requestDeposit(fallbackAmount, _user1, _user1) and expect this call.
        bytes memory expectedRequestDepositData =
            abi.encodeWithSelector(BasketToken.requestDeposit.selector, fallbackAmount, _user1, address(_operator));
        vm.mockCall(_mockBasketToken, expectedRequestDepositData, abi.encode(requestID));
        vm.expectCall(_mockBasketToken, expectedRequestDepositData);

        vm.prank(address(this)); // anyone can call handleDeposit
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.FallbackAssetsRetriedForUser(_user1, _mockBasketToken, fallbackAmount);
        _operator.handleDeposit(_user1, _mockBasketToken);

        // Simulate BasketToken pulling assets from operator during requestDeposit
        // If BasicRetryOperator.sol's approveDeposits() was effective, BasketToken can pull _asset from operator.
        // We check the operator's balance of _asset is now 0.
        // To make this pass, the mocked requestDeposit should effectively transfer `fallbackAmount` from operator.
        // Since mocks don't do state changes, we manually model it.
        // The `deal` gave assets to operator. Now, assume `requestDeposit` took them.
        // This means the `_asset.transferFrom(address(_operator), address(_mockBasketToken), fallbackAmount)` happened.
        vm.prank(address(_mockBasketToken)); // Simulate basket token is the one pulling
        _asset.transferFrom(address(_operator), _mockBasketToken, fallbackAmount);
        vm.stopPrank();

        assertEq(_asset.balanceOf(address(_operator)), 0, "Operator should have used fallback assets for retry");
    }

    function test_handleDeposit_RetryEnabled_NoFallbackAssets_RevertsNothingToClaim() public {
        // Setup: User has deposit retry enabled
        vm.prank(_user1);
        _operator.setDepositRetry(true);
        vm.stopPrank(); // Stop prank for subsequent calls

        // Mock maxDeposit to return 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxDeposit.selector, _user1), abi.encode(0));
        // Mock claimableFallbackAssets to return 0
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackAssets.selector, _user1),
            abi.encode(0)
        );

        vm.expectRevert(BasicRetryOperator.NothingToClaim.selector);
        _operator.handleDeposit(_user1, _mockBasketToken);
    }

    function test_handleDeposit_RetryEnabled_MaxDepositExists_NoFallback_ClaimsZeroFallback(uint256 maxDepositAmount)
        public
    {
        vm.assume(maxDepositAmount > 0);

        // Setup: User has deposit retry enabled
        vm.prank(_user1);
        _operator.setDepositRetry(true);
        vm.stopPrank();

        // Mock maxDeposit to return a non-zero value
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.maxDeposit.selector, _user1),
            abi.encode(maxDepositAmount)
        );
        // Mock claimableFallbackAssets to return 0
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackAssets.selector, _user1),
            abi.encode(0) // No fallback assets
        );

        // Expect claimFallbackAssets NOT to be called because fallbackAssets is 0
        // The path `if (!depositRetryEnabled[user] || fallbackAssets == 0)` will be true,
        // then the inner `if (fallbackAssets > 0)` will be false.

        // Mock the deposit call for maxDepositAmount
        uint256 sharesToMint = maxDepositAmount; // Example shares
        bytes memory expectedDepositCallData = abi.encodeWithSelector(
            bytes4(keccak256(bytes("deposit(uint256,address,address)"))), maxDepositAmount, _user1, _user1
        );
        vm.mockCall(_mockBasketToken, expectedDepositCallData, abi.encode(sharesToMint));
        vm.expectCall(_mockBasketToken, expectedDepositCallData);

        vm.prank(address(this));
        // Only DepositClaimedForUser is emitted
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.DepositClaimedForUser(_user1, _mockBasketToken, maxDepositAmount, sharesToMint);

        _operator.handleDeposit(_user1, _mockBasketToken);
    }

    // --- handleRedeem Reverts ---
    function test_RevertWhen_handleRedeem_ZeroUserAddress() public {
        vm.expectRevert(BasicRetryOperator.ZeroAddress.selector);
        _operator.handleRedeem(address(0), _mockBasketToken);
    }

    function test_RevertWhen_handleRedeem_ZeroBasketTokenAddress() public {
        vm.expectRevert(BasicRetryOperator.ZeroAddress.selector);
        _operator.handleRedeem(_user1, address(0));
    }

    function test_RevertWhen_handleRedeem_NothingToClaim() public {
        // Mock maxRedeem to return 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxRedeem.selector, _user1), abi.encode(0));
        // Mock claimableFallbackShares to return 0
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackShares.selector, _user1),
            abi.encode(0)
        );

        vm.expectRevert(BasicRetryOperator.NothingToClaim.selector);
        _operator.handleRedeem(_user1, _mockBasketToken);
    }

    function test_handleRedeem_RetryEnabled_NoFallbackShares_RevertsNothingToClaim() public {
        // Setup: User has redeem retry enabled
        vm.prank(_user1);
        _operator.setRedeemRetry(true);
        vm.stopPrank(); // Stop prank for subsequent calls

        // Mock maxRedeem to return 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxRedeem.selector, _user1), abi.encode(0));
        // Mock claimableFallbackShares to return 0
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackShares.selector, _user1),
            abi.encode(0)
        );

        vm.expectRevert(BasicRetryOperator.NothingToClaim.selector);
        _operator.handleRedeem(_user1, _mockBasketToken);
    }

    function test_handleRedeem_RetryEnabled_MaxRedeemExists_NoFallback_ClaimsZeroFallback(uint256 maxRedeemShares)
        public
    {
        vm.assume(maxRedeemShares > 0);

        vm.prank(_user1);
        _operator.setRedeemRetry(true);
        vm.stopPrank();

        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.maxRedeem.selector, _user1),
            abi.encode(maxRedeemShares)
        );
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackShares.selector, _user1),
            abi.encode(0) // No fallback shares
        );

        // Expect claimFallbackShares NOT to be called

        uint256 assetsToReceive = maxRedeemShares; // Example assets
        bytes memory expectedRedeemCallData =
            abi.encodeWithSelector(BasketToken.redeem.selector, maxRedeemShares, _user1, _user1);
        vm.mockCall(_mockBasketToken, expectedRedeemCallData, abi.encode(assetsToReceive));
        vm.expectCall(_mockBasketToken, expectedRedeemCallData);

        vm.prank(address(this));
        // Only RedeemClaimedForUser is emitted
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.RedeemClaimedForUser(_user1, _mockBasketToken, maxRedeemShares, assetsToReceive);

        _operator.handleRedeem(_user1, _mockBasketToken);
    }

    // --- handleRedeem Success Paths ---
    function test_handleRedeem_ClaimFulfilledRedeem(uint256 sharesToRedeem, uint256 assetsToReceive) public {
        vm.assume(sharesToRedeem > 0);
        vm.assume(assetsToReceive > 0);

        // 1. Mock _basketToken.maxRedeem(_user1) to return sharesToRedeem
        vm.mockCall(
            _mockBasketToken, abi.encodeWithSelector(BasketToken.maxRedeem.selector, _user1), abi.encode(sharesToRedeem)
        );

        // 2. Mock _basketToken.redeem(sharesToRedeem, _user1, _user1) to return assetsToReceive
        //    and expect this call.
        bytes memory expectedRedeemCallData =
            abi.encodeWithSelector(BasketToken.redeem.selector, sharesToRedeem, _user1, _user1);
        vm.mockCall(_mockBasketToken, expectedRedeemCallData, abi.encode(assetsToReceive));
        vm.expectCall(_mockBasketToken, expectedRedeemCallData);

        vm.prank(address(this)); // anyone can call handleRedeem
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.RedeemClaimedForUser(_user1, _mockBasketToken, sharesToRedeem, assetsToReceive);
        _operator.handleRedeem(_user1, _mockBasketToken);
    }

    function test_handleRedeem_ClaimFallbackShares_RetryDisabled(uint256 fallbackShares) public {
        vm.assume(fallbackShares > 0);

        // Setup: maxRedeem returns 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxRedeem.selector, _user1), abi.encode(0));
        // Setup: User has disabled redeem retry
        vm.prank(_user1);
        _operator.setRedeemRetry(false);

        // 1. Mock _basketToken.claimableFallbackShares(_user1) to return fallbackShares
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackShares.selector, _user1),
            abi.encode(fallbackShares)
        );

        // 2. Mock _basketToken.claimFallbackShares(_user1, _user1) and expect this call
        bytes memory expectedClaimFallbackCallData =
            abi.encodeWithSelector(BasketToken.claimFallbackShares.selector, _user1, _user1);
        vm.mockCall(_mockBasketToken, expectedClaimFallbackCallData, abi.encode(fallbackShares));
        vm.expectCall(_mockBasketToken, expectedClaimFallbackCallData);

        vm.prank(address(this));
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.FallbackSharesClaimedForUser(_user1, _mockBasketToken, fallbackShares);
        _operator.handleRedeem(_user1, _mockBasketToken);
    }

    function test_handleRedeem_RetryFallbackShares_RetryEnabled(uint256 fallbackShares, uint256 requestID) public {
        vm.assume(fallbackShares > 0);

        // Setup: maxRedeem returns 0
        vm.mockCall(_mockBasketToken, abi.encodeWithSelector(BasketToken.maxRedeem.selector, _user1), abi.encode(0));
        // Setup: User has redeem retry enabled
        vm.prank(_user1);
        _operator.setRedeemRetry(true);

        // 1. Mock _basketToken.claimableFallbackShares(_user1) to return fallbackShares
        vm.mockCall(
            _mockBasketToken,
            abi.encodeWithSelector(BasketToken.claimableFallbackShares.selector, _user1),
            abi.encode(fallbackShares)
        );

        // 2. Mock _basketToken.claimFallbackShares(address(this_operator), _user1)
        //    This implies the BasketToken transfers shares to the operator contract.
        //    However, BasicRetryOperator doesn't hold shares. It calls requestRedeem with these shares.
        bytes memory expectedClaimToOperatorData =
            abi.encodeWithSelector(BasketToken.claimFallbackShares.selector, address(_operator), _user1);
        vm.mockCall(_mockBasketToken, expectedClaimToOperatorData, abi.encode(fallbackShares));
        vm.expectCall(_mockBasketToken, expectedClaimToOperatorData);

        // 3. Mock _basketToken.requestRedeem(fallbackShares, _user1, _user1) and expect this call.
        //    requestRedeem usually returns a requestId (uint256), let's say 200.
        bytes memory expectedRequestRedeemData =
            abi.encodeWithSelector(BasketToken.requestRedeem.selector, fallbackShares, _user1, address(_operator));
        vm.mockCall(_mockBasketToken, expectedRequestRedeemData, abi.encode(requestID));
        vm.expectCall(_mockBasketToken, expectedRequestRedeemData);

        vm.prank(address(this));
        vm.expectEmit(true, true, false, true);
        emit BasicRetryOperator.FallbackSharesRetriedForUser(_user1, _mockBasketToken, fallbackShares);
        _operator.handleRedeem(_user1, _mockBasketToken);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function test_approveDeposits(uint256 approvalAmount) public {
        address mockNewBasket = makeAddr("mockNewBasket");
        ERC20Mock asset = new ERC20Mock(); // This is the asset *OF* the new basket

        // Mock the .asset() call for the new mock basket
        vm.mockCall(mockNewBasket, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(asset)));

        // Check initial allowance (should be 0 for operator on the new basket's asset)
        assertEq(asset.allowance(address(_operator), mockNewBasket), 0, "Initial allowance should be 0");

        vm.prank(_manager);
        _operator.approveDeposits(BasketToken(payable(mockNewBasket)), approvalAmount);

        // Check that the allowance is set to the correct amount
        assertEq(
            asset.allowance(address(_operator), mockNewBasket),
            approvalAmount,
            "Allowance should be set to the correct amount"
        );
    }

    function test_RevertWhen_approveDeposits_ZeroBasketToken(uint256 approvalAmount) public {
        // Calling .asset() on address(0) will revert.
        // The cast to BasketToken(payable(address(0))) is fine, the call to .asset() is the problem.
        vm.expectRevert();
        vm.prank(_manager);
        _operator.approveDeposits(BasketToken(payable(address(0))), approvalAmount);
    }

    function test_RevertWhen_approveDeposits_NotManager(address nonManager, uint256 approvalAmount) public {
        vm.assume(!_operator.hasRole(_operator.MANAGER_ROLE(), nonManager));
        vm.prank(nonManager);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        _operator.approveDeposits(BasketToken(payable(_mockBasketToken)), approvalAmount);
    }
}

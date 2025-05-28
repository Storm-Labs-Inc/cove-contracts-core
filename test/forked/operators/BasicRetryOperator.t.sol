// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BasicRetryOperatorForkedTest is BaseTest {
    BasketManager public basketManager;
    BasketToken public basketToken;
    BasicRetryOperator public basicRetryOperator;
    address public caller = COVE_DEPLOYER_ADDRESS;

    // Mainnet block numbers
    uint256 public callerHasClaimableRedeem = 22_550_666;
    uint256 public callerHasClaimableFallbackShares = 22_550_174;
    uint256 public callerHasClaimableDeposit = 22_527_584;

    function setUp() public override {
        super.setUp();

        basketManager = BasketManager(0xbeccf8486856476E9Cd8AD6FaD80Fb7c17a15Da1);
        basketToken = BasketToken(0x9f53dA1E245207e163E71DFC45dAFaB2d01770d0);
    }

    function test_handleDeposit_callerHasClaimableDeposit() public {
        forkNetworkAt("mainnet", callerHasClaimableDeposit);
        basicRetryOperator = new BasicRetryOperator(caller, caller);
        vm.prank(caller);
        basicRetryOperator.approveDeposits(basketToken, type(uint256).max);
        vm.prank(caller);
        basketToken.setOperator(address(basicRetryOperator), true);

        // Caller (COVE_DEPLOYER_ADDRESS) has a claimable deposit at this block.
        // The operator will claim this deposit on behalf of the caller.

        // Get initial state for assertions
        uint256 initialCallerShares = basketToken.balanceOf(caller);
        uint256 initialOperatorAssetBalance = IERC20(basketToken.asset()).balanceOf(address(basicRetryOperator));
        uint256 assetsToClaim = basketToken.maxDeposit(caller);
        assertTrue(assetsToClaim > 0, "Pre-condition: assetsToClaim should be greater than 0");
        uint256 lastDepositRequestIdBefore = basketToken.lastDepositRequestId(caller);
        // Using DepositRequestView as DepositRequestStruct has mapping and cannot be in memory
        BasketToken.DepositRequestView memory depositRequestViewBefore =
            basketToken.getDepositRequest(lastDepositRequestIdBefore);
        assertTrue(
            depositRequestViewBefore.fulfilledShares > 0,
            "Pre-condition: Deposit request should be fulfilled before claim"
        );

        // Expect the DepositClaimedForUser event
        // We need to predict the shares minted.
        // shares = (fulfilledShares * depositAssetsForUser) / totalDepositAssetsInRequest
        uint256 expectedShares =
            (depositRequestViewBefore.fulfilledShares * assetsToClaim) / depositRequestViewBefore.totalDepositAssets;

        vm.expectEmit(true, true, false, true); // user, basketToken, assets, shares
        emit BasicRetryOperator.DepositClaimedForUser(caller, address(basketToken), assetsToClaim, expectedShares);

        // Call the function to be tested
        basicRetryOperator.handleDeposit(caller, address(basketToken));

        // Assertions
        // 1. Caller should have received shares.
        uint256 finalCallerShares = basketToken.balanceOf(caller);
        assertEq(
            finalCallerShares, initialCallerShares + expectedShares, "Caller should have received the expected shares"
        );

        // 2. The specific deposit request for the caller should be cleared.
        //    maxDeposit for the caller should now be 0 for this request.
        //    We can't directly check the 'depositAssets[caller]' in the struct after claim
        //    because the 'assets' parameter to 'deposit' in BasketToken is the amount to claim,
        //    and after a successful claim, `maxDeposit` for that user and request ID will be 0.
        assertEq(basketToken.maxDeposit(caller), 0, "Caller's maxDeposit should be zero after claim");

        // 3. Operator's balance of the underlying asset should remain unchanged or be 0 if it handled assets.
        //    For a direct claim, operator doesn't hold assets.
        uint256 finalOperatorAssetBalance = IERC20(basketToken.asset()).balanceOf(address(basicRetryOperator));
        assertEq(
            finalOperatorAssetBalance,
            initialOperatorAssetBalance,
            "Operator asset balance should be unchanged for direct claim"
        );
    }

    function test_handleRedeem_callerHasClaimableRedeem() public {
        forkNetworkAt("mainnet", callerHasClaimableRedeem);
        basicRetryOperator = new BasicRetryOperator(caller, caller);
        vm.prank(caller);
        basketToken.setOperator(address(basicRetryOperator), true);

        // Caller (COVE_DEPLOYER_ADDRESS) has a claimable redeem at this block.

        // Get initial state for assertions
        uint256 initialCallerAssetBalance = IERC20(basketToken.asset()).balanceOf(caller);
        uint256 sharesToClaim = basketToken.maxRedeem(caller);
        assertTrue(sharesToClaim > 0, "Pre-condition: sharesToClaim should be greater than 0");
        uint256 lastRedeemRequestIdBefore = basketToken.lastRedeemRequestId(caller);
        BasketToken.RedeemRequestView memory redeemRequestViewBefore =
            basketToken.getRedeemRequest(lastRedeemRequestIdBefore);
        assertTrue(
            redeemRequestViewBefore.fulfilledAssets > 0,
            "Pre-condition: Redeem request should be fulfilled before claim"
        );

        // Predict expected assets to receive
        // assets = (fulfilledAssets * redeemSharesForUser) / totalRedeemSharesInRequest
        uint256 expectedAssets =
            (redeemRequestViewBefore.fulfilledAssets * sharesToClaim) / redeemRequestViewBefore.totalRedeemShares;

        // Expect the RedeemClaimedForUser event
        vm.expectEmit(true, true, false, true); // user, basketToken, shares, assets
        emit BasicRetryOperator.RedeemClaimedForUser(caller, address(basketToken), sharesToClaim, expectedAssets);

        // Call the function to be tested
        basicRetryOperator.handleRedeem(caller, address(basketToken));

        // Assertions
        // 1. Caller should have received assets.
        uint256 finalCallerAssetBalance = IERC20(basketToken.asset()).balanceOf(caller);
        assertEq(
            finalCallerAssetBalance,
            initialCallerAssetBalance + expectedAssets,
            "Caller should have received the expected assets"
        );

        // 2. The specific redeem request for the caller should be cleared.
        //    maxRedeem for the caller should now be 0 for this request.
        assertEq(basketToken.maxRedeem(caller), 0, "Caller's maxRedeem should be zero after claim");
    }

    function test_handleFallbackShares_callerHasClaimableFallbackShares_NoRetry() public {
        forkNetworkAt("mainnet", callerHasClaimableFallbackShares);
        basicRetryOperator = new BasicRetryOperator(caller, caller);
        vm.prank(caller);
        basketToken.setOperator(address(basicRetryOperator), true);

        // Caller (COVE_DEPLOYER_ADDRESS) has claimable fallback shares at this block.
        // Retry is disabled for the caller.

        // Setup: Disable redeem retry for the caller
        vm.prank(caller);
        basicRetryOperator.setRedeemRetry(false);
        vm.stopPrank();

        // Get initial state for assertions
        uint256 initialCallerSharesBalance = basketToken.balanceOf(caller);
        uint256 fallbackSharesToClaim = basketToken.claimableFallbackShares(caller);
        assertTrue(fallbackSharesToClaim > 0, "Pre-condition: fallbackSharesToClaim should be greater than 0");
        // Ensure maxRedeem is 0 for this path to be taken
        assertEq(
            basketToken.maxRedeem(caller), 0, "Pre-condition: maxRedeem for caller should be 0 to test fallback path"
        );

        // Expect the FallbackSharesClaimedForUser event
        vm.expectEmit(true, true, false, true); // user, basketToken, shares
        emit BasicRetryOperator.FallbackSharesClaimedForUser(caller, address(basketToken), fallbackSharesToClaim);

        // Call the function to be tested
        basicRetryOperator.handleRedeem(caller, address(basketToken));

        // Assertions
        // 1. Caller should have received the fallback shares.
        uint256 finalCallerSharesBalance = basketToken.balanceOf(caller);
        assertEq(
            finalCallerSharesBalance,
            initialCallerSharesBalance + fallbackSharesToClaim,
            "Caller should have received the fallback shares"
        );

        // 2. Claimable fallback shares for the caller should be zero after the claim.
        assertEq(
            basketToken.claimableFallbackShares(caller),
            0,
            "Caller's claimable fallback shares should be zero after claim"
        );
    }

    function test_handleFallbackShares_callerHasClaimableFallbackShares_Retry() public {
        forkNetworkAt("mainnet", callerHasClaimableFallbackShares);
        basicRetryOperator = new BasicRetryOperator(caller, caller);
        vm.prank(caller);
        basketToken.setOperator(address(basicRetryOperator), true);

        // Caller (COVE_DEPLOYER_ADDRESS) has claimable fallback shares at this block.
        // Retry is enabled for the caller (default state).

        // Get initial state for assertions
        uint256 initialCallerSharesBalance = basketToken.balanceOf(caller); // Shares should not change directly
        uint256 fallbackSharesToClaimAndRetry = basketToken.claimableFallbackShares(caller);
        assertTrue(fallbackSharesToClaimAndRetry > 0, "Pre-condition: fallbackSharesToClaimAndRetry should be > 0");
        // Ensure maxRedeem is 0 for this path to be taken
        assertEq(
            basketToken.maxRedeem(caller), 0, "Pre-condition: maxRedeem for caller should be 0 to test fallback path"
        );
        uint256 initialNextRedeemRequestId = basketToken.nextRedeemRequestId();

        // Expect the FallbackSharesRetriedForUser event
        vm.expectEmit(true, true, false, true); // user, basketToken, shares
        emit BasicRetryOperator.FallbackSharesRetriedForUser(
            caller, address(basketToken), fallbackSharesToClaimAndRetry
        );

        // Call the function to be tested
        basicRetryOperator.handleRedeem(caller, address(basketToken));

        // Assertions
        // 1. Caller's share balance should NOT have changed directly because shares were retried (sent to new request).
        uint256 finalCallerSharesBalance = basketToken.balanceOf(caller);
        assertEq(
            finalCallerSharesBalance,
            initialCallerSharesBalance,
            "Caller shares should be unchanged as fallback was retried"
        );

        // 2. Claimable fallback shares for the caller should be zero after the retry process initiated.
        assertEq(
            basketToken.claimableFallbackShares(caller),
            0,
            "Caller's claimable fallback shares should be zero after retry initiated"
        );

        // 3. A new redeem request should have been made by the operator on behalf of the caller.
        //    The operator becomes the "owner" of these shares in the new request context temporarily.
        //    The lastRedeemRequestId for the caller should point to the new request made by the operator.
        uint256 newLastRedeemRequestId = basketToken.lastRedeemRequestId(caller);
        assertTrue(
            newLastRedeemRequestId >= initialNextRedeemRequestId, "A new redeem request ID should be set for the caller"
        );

        // Check the details of the new request made by the operator for the user
        // The request should be for fallbackSharesToClaimAndRetry
        // The `controller` of this new request is `caller`
        // The `owner` of the shares *within* this request becomes the operator temporarily (who called requestRedeem)
        // However, BasketToken.requestRedeem takes `owner` as the one whose shares are taken initially.
        // In BasicRetryOperator `bt.requestRedeem(fallbackShares, user, user);` -> owner is user.
        // Let's verify the pendingRedeemRequest for the `caller` (as controller) on this `newLastRedeemRequestId`
        uint256 pendingSharesInNewRequest = basketToken.pendingRedeemRequest(newLastRedeemRequestId, caller);
        assertEq(
            pendingSharesInNewRequest,
            fallbackSharesToClaimAndRetry,
            "A new pending redeem request should exist for the retried shares"
        );
    }
}

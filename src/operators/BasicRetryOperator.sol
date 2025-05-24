// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { BasketToken } from "src/BasketToken.sol";

/// @title BasicRetryOperator
/// @notice A minimal operator contract compatible with Cove's BasketToken. Once approved via
///         BasketToken.setOperator, anyone can call the handler functions to automatically claim
///         a user's fulfilled deposits/redeems (or their fall-backs) and route the resulting
///         assets/shares back to the original user.
contract BasicRetryOperator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Errors
    error ZeroAddress();
    error NothingToClaim();

    // Events
    event DepositClaimedForUser(address indexed user, address indexed basketToken, uint256 assets, uint256 shares);
    event RedeemClaimedForUser(address indexed user, address indexed basketToken, uint256 shares, uint256 assets);
    event FallbackAssetsClaimedForUser(address indexed user, address indexed basketToken, uint256 assets);
    event FallbackAssetsRetriedForUser(address indexed user, address indexed basketToken, uint256 assets);
    event FallbackSharesClaimedForUser(address indexed user, address indexed basketToken, uint256 shares);
    event FallbackSharesRetriedForUser(address indexed user, address indexed basketToken, uint256 shares);
    event DepositRetrySet(address indexed user, bool enabled);
    event RedeemRetrySet(address indexed user, bool enabled);

    // bit-packed retry flags per user. bit0 => deposit, bit1 => redeem
    // by default, users are considered opted-in for retry paths.
    mapping(address user => uint8 flags) private _retryDisabledFlags;

    uint8 private constant _DEPOSIT_RETRY_DISABLED_FLAG = 1 << 0;
    uint8 private constant _REDEEM_RETRY_DISABLED_FLAG = 1 << 1;

    /*//////////////////////////////////////////////////////////////
                        USER CONFIGURATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Enable / disable automatic fallback asset claims when deposits cannot be fulfilled.
    /// @dev    By default, users are considered opted-in for retry paths.
    function setDepositRetry(bool enabled) external {
        if (enabled) _retryDisabledFlags[msg.sender] &= ~_DEPOSIT_RETRY_DISABLED_FLAG;
        else _retryDisabledFlags[msg.sender] |= _DEPOSIT_RETRY_DISABLED_FLAG;
        emit DepositRetrySet(msg.sender, enabled);
    }

    /// @notice Enable / disable automatic fallback share claims when redeems cannot be fulfilled.
    /// @dev    By default, users are considered opted-in for retry paths.
    function setRedeemRetry(bool enabled) external {
        if (enabled) _retryDisabledFlags[msg.sender] &= ~_REDEEM_RETRY_DISABLED_FLAG;
        else _retryDisabledFlags[msg.sender] |= _REDEEM_RETRY_DISABLED_FLAG;
        emit RedeemRetrySet(msg.sender, enabled);
    }

    /// @notice Returns whether the deposit retry is enabled for `user`.
    /// @return true if the deposit retry is enabled for `user`, false otherwise.
    function isDepositRetryEnabled(address user) public view returns (bool) {
        return _retryDisabledFlags[user] & _DEPOSIT_RETRY_DISABLED_FLAG == 0;
    }

    /// @notice Returns whether the redeem retry is enabled for `user`.
    /// @return true if the redeem retry is enabled for `user`, false otherwise.
    function isRedeemRetryEnabled(address user) public view returns (bool) {
        return _retryDisabledFlags[user] & _REDEEM_RETRY_DISABLED_FLAG == 0;
    }

    /*//////////////////////////////////////////////////////////////
                           MAIN HANDLER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims a fulfilled deposit for `user`. If nothing is fulfilled and the caller opted-in,
    ///         attempts to pull fallback assets instead.
    function handleDeposit(address user, address basketToken) external nonReentrant {
        if (user == address(0) || basketToken == address(0)) revert ZeroAddress();

        BasketToken bt = BasketToken(basketToken);
        uint256 assets = bt.maxDeposit(user);

        // If there are assets to claim, claim them and send it back to the user.
        if (assets != 0) {
            uint256 shares = bt.deposit(assets, user, user);
            emit DepositClaimedForUser(user, basketToken, assets, shares);
            return;
        }

        // If there are fallback assets to claim, claim them and send it back to the user.
        uint256 fallbackAssets = bt.claimableFallbackAssets(user);
        // slither-disable-start unused-return
        if (fallbackAssets != 0) {
            // If the user has disabled retry on failed deposits, claim the fallback assets and send it back to the
            // user.
            if (!isDepositRetryEnabled(user)) {
                bt.claimFallbackAssets(user, user);
                emit FallbackAssetsClaimedForUser(user, basketToken, fallbackAssets);
                return;
            } else {
                // Otherwise, claim the fallback assets and request a new deposit for the user.
                bt.claimFallbackAssets(address(this), user);
                bt.requestDeposit(fallbackAssets, user, address(this));
                emit FallbackAssetsRetriedForUser(user, basketToken, fallbackAssets);
                return;
            }
        }
        // slither-disable-end unused-return
        revert NothingToClaim();
    }

    /// @notice Claims a fulfilled redeem for `user`. If nothing is fulfilled and the caller opted-in,
    ///         attempts to pull fallback shares instead.
    function handleRedeem(address user, address basketToken) external nonReentrant {
        if (user == address(0) || basketToken == address(0)) revert ZeroAddress();

        BasketToken bt = BasketToken(basketToken);
        uint256 shares = bt.maxRedeem(user);

        // If there are shares to claim, claim them and send it back to the user.
        if (shares != 0) {
            uint256 assets = bt.redeem(shares, user, user);
            emit RedeemClaimedForUser(user, basketToken, shares, assets);
            return;
        }

        uint256 fallbackShares = bt.claimableFallbackShares(user);
        // slither-disable-start unused-return
        if (fallbackShares != 0) {
            // If the user has disabled retry on failed redeems, claim the fallback shares and send it back to the user.
            if (!isRedeemRetryEnabled(user)) {
                bt.claimFallbackShares(user, user);
                emit FallbackSharesClaimedForUser(user, basketToken, fallbackShares);
                return;
            } else {
                // Otherwise, claim the fallback shares and request a new redeem for the user.
                bt.claimFallbackShares(address(this), user);
                bt.requestRedeem(fallbackShares, user, address(this));
                emit FallbackSharesRetriedForUser(user, basketToken, fallbackShares);
                return;
            }
        }
        // slither-disable-end unused-return
        revert NothingToClaim();
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves the asset of `basketToken` to be spent by `basketToken`.
    /// @dev This is necessary to allow retrying deposits to work without approving the asset beforehand every time.
    ///      Call this function after BasketToken is deployed to approve the asset to be spent by the operator.
    function approveDeposits(BasketToken basketToken) external {
        IERC20(basketToken.asset()).forceApprove(address(basketToken), type(uint256).max);
    }
}

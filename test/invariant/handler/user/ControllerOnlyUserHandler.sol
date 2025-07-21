pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

import { GlobalState } from "test/invariant/handler/GlobalState.sol";
import { UserHandlerBase } from "test/invariant/handler/user/UserBaseHandler.sol";

abstract contract ControllerOnlyUserHandlerBase is UserHandlerBase {
    uint256 successfull_deposit;
    uint256 successfull_mint;
    uint256 successfull_claimFallbackAssets;
    uint256 successfull_redeem;
    uint256 successfull_claimFallbackShares;

    /**
     * @notice Attempts to deposit maximum available amount for a basket
     * git zd     * @param idx Index of the basket to deposit into
     * @custom:preconditions none
     * @custom:action Call the deposit function
     * @custom:postcondition If the call is succesfull the caller was not a "malicious" actor
     */
    function deposit(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 maxDeposit = basketToken.maxDeposit(_controller());
        if (maxDeposit == 0) {
            return;
        }

        try basketToken.deposit(maxDeposit, address(this), _controller()) {
            successfull_deposit++;
            _success(); // This will check that the caller was not a "malicious" actor
        } catch {
            revert();
        }
    }

    /**
     * @notice Attempts to mint maximum available shares for a basket
     * @param idx Index of the basket to mint from
     * @custom:preconditions none
     * @custom:action Call the mint function
     * @custom:postcondition If the call is succesfull the caller was not a "malicious" actor
     */
    function mint(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 maxMint = basketToken.maxMint(_controller());
        if (maxMint == 0) {
            return;
        }

        try basketToken.mint(maxMint, address(this), _controller()) {
            successfull_mint++;
            _success(); // This will check that the caller was not a "malicious" actor
        } catch {
            revert();
        }
    }

    /**
     * @notice Verifies that deposit with wrong amount (different from maxDeposit) should revert
     * @custom:preconditions maxDeposit is greater than 0 and amount is different from maxDeposit
     * @custom:action Attempts to deposit an amount different from maxDeposit
     * @custom:postcondition The deposit function must revert when amount differs from maxDeposit (MustClaimFullAmount)
     */
    function depositWrongAmount(uint256 idx, uint256 amount) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 maxDeposit = basketToken.maxDeposit(_controller());

        if (maxDeposit == 0) {
            return;
        }

        if (maxDeposit >= amount) {
            amount = bound(amount, 1, maxDeposit - 1);
        }

        try basketToken.deposit(amount, address(this), _controller()) returns (uint256 shares) {
            // @Invariant: with an amount different from the requestDeposit, the function should revert
            // (MustClaimFullAmount)
            assert(false);
        } catch { }
    }

    /**
     * @notice Claims fallback assets for a basket
     * @param idx Index of the basket to claim from
     * @custom:preconditions none
     * @custom:action Call the claimFallbackAssets function
     * @custom:postcondition If the call is successful the caller was not a "malicious" actor
     */
    function claimFallbackAssets(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 claimableFallbackAssets = basketToken.claimableFallbackAssets(_controller());
        if (claimableFallbackAssets == 0) {
            return;
        }

        try basketToken.claimFallbackAssets(address(this), _controller()) {
            successfull_claimFallbackAssets++;
            _success(); // This will check that the caller was not a "malicious" actor
        } catch {
            revert();
        }
    }

    /**
     * @notice Attempts to redeem maximum available shares for a basket
     * @param idx Index of the basket to redeem from
     * @custom:preconditions none
     * @custom:action Call the redeem function
     * @custom:postcondition If the call is succesfull the caller was not a "malicious" actor
     */
    function redeem(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 maxRedeem = basketToken.maxRedeem(_controller());
        if (maxRedeem == 0) {
            return;
        }

        try basketToken.redeem(maxRedeem, address(this), _controller()) {
            successfull_redeem++;
            _success(); // This will check that the caller was not a "malicious" actor
        } catch {
            revert();
        }
    }

    /**
     * @notice Attempts to withdraw maximum available assets for a basket
     * @param idx Index of the basket to withdraw from
     * @custom:preconditions none
     * @custom:action Call the withdraw function
     * @custom:postcondition If the call is succesfull the caller was not a "malicious" actor
     */
    function withdraw(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 maxWithdraw = basketToken.maxWithdraw(_controller());
        if (maxWithdraw == 0) {
            return;
        }

        try basketToken.withdraw(maxWithdraw, address(this), _controller()) {
            successfull_redeem++;
            _success(); // This will check that the caller was not a "malicious" actor
        } catch {
            revert();
        }
    }

    /**
     * @notice Verifies that redeem with wrong amount (different from maxRedeem) should revert
     * @custom:preconditions maxRedeem is greater than 0 and amount is different from maxRedeem
     * @custom:action Attempts to redeem an amount different from maxRedeem
     * @custom:postcondition The redeem function must revert when amount differs from maxRedeem (MustClaimFullAmount)
     */
    function redeemWrongAmount(uint256 idx, uint256 amount) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 maxRedeem = basketToken.maxRedeem(_controller());

        if (maxRedeem == 0) {
            return;
        }

        if (maxRedeem >= amount) {
            amount = bound(amount, 1, maxRedeem - 1);
        }

        try basketToken.redeem(amount, address(this), _controller()) returns (uint256 shares) {
            // @Invariant: with an amount different from the requestRedeem, the function should revert
            // (MustClaimFullAmount)
            assert(false);
        } catch { }
    }

    /**
     * @notice Claims fallback shares for a basket
     * @param idx Index of the basket to claim from
     * @custom:preconditions none
     * @custom:action Call the claimFallbackShares function
     * @custom:postcondition If the call is succesfull the caller was not a "malicious" actor
     */
    function claimFallbackShares(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        uint256 claimableFallbackShares = basketToken.claimableFallbackShares(_controller());
        if (claimableFallbackShares == 0) {
            return;
        }

        try basketToken.claimFallbackShares(address(this), _controller()) {
            _success(); // This will check that the caller was not a "malicious" actor
            successfull_claimFallbackShares++;
        } catch {
            revert();
        }
    }
}

contract ControllerOnlyUserHandler is ControllerOnlyUserHandlerBase {
    constructor(
        BasketManager basketManager,
        GlobalState globalState,
        address controller,
        address owner,
        bool isMalicious
    )
        UserHandlerBase(basketManager, globalState, controller, owner, isMalicious)
    { }
}

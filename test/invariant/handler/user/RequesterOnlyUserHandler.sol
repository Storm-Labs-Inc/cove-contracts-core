pragma solidity 0.8.28;

import { ERC20DecimalsMock } from "test/utils/mocks/ERC20DecimalsMock.sol";

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

import { GlobalState } from "test/invariant/handler/GlobalState.sol";
import { UserHandlerBase } from "test/invariant/handler/user/UserBaseHandler.sol";

abstract contract RequesterOnlyUserHandlerBase is UserHandlerBase {
    uint256 requestIDDeposit;
    uint256 requestIDRedeem;

    uint256 successful_requestDeposit;
    uint256 successful_requestRedeem;

    uint256 successful_cancelDeposit;
    uint256 successful_cancelRedeem;

    /**
     * @notice Requests a deposit for a specific basket and amount
     * @param idxBasket Index of the basket to deposit into
     * @param amount Amount to deposit
     */
    function requestDeposit(uint256 idxBasket, uint256 amount) public {
        BasketToken basketToken = _get_basket(idxBasket);

        ERC20DecimalsMock token = ERC20DecimalsMock(basketToken.asset());

        uint256 balance = token.balanceOf(address(this));

        if (balance == 0) {
            return;
        }

        amount = bound(amount, 1, balance);

        token.approve(address(basketToken), amount);
        try basketToken.requestDeposit(amount, _controller(), _owner()) returns (uint256 id) {
            requestIDDeposit = id;

            successful_requestDeposit++;

            globalState.add_request_deposit_controller(address(basketToken), id, _controller());

            // Do not call success, as anyone can call requestDeposit on incorrect controller
        } catch {
            _could_revert();
        }
    }

    /**
     * @notice Cancels a pending deposit request
     * @param idxBasket Index of the basket with pending deposit
     */
    function cancelDepositRequest(uint256 idxBasket) public {
        BasketToken basketToken = _get_basket(idxBasket);

        try basketToken.cancelDepositRequest() {
            successful_cancelDeposit++;
        } catch {
            _could_revert();
        }
    }

    /**
     * @notice Requests a redeem for a specific basket and amount
     * @param idx Index of the basket to redeem from
     * @param amount Amount to redeem
     */
    function requestRedeem(uint256 idx, uint256 amount) public {
        BasketToken basketToken = _get_basket(idx);

        uint256 maxAmount = basketToken.balanceOf(address(this));

        if (maxAmount == 0) {
            return;
        }

        amount = bound(amount, 1, maxAmount);

        try basketToken.requestRedeem(amount, _controller(), _owner()) returns (uint256 id) {
            requestIDRedeem = id;

            successful_requestRedeem++;

            // Do not call success, as anyone can call requestDeposit on incorrect controller
        } catch {
            _could_revert();
        }
    }

    /**
     * @notice Cancels a pending redeem request
     * @param idxBasket Index of the basket with pending redeem
     */
    function cancelRedeemRequest(uint256 idxBasket) public {
        BasketToken basketToken = _get_basket(idxBasket);

        try basketToken.cancelRedeemRequest() {
            successful_cancelRedeem++;
        } catch {
            _could_revert();
        }
    }
}

contract RequesterOnlyUserHandler is RequesterOnlyUserHandlerBase {
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

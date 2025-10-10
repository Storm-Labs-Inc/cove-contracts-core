pragma solidity 0.8.28;

import { ControllerOnlyUserHandlerBase } from "test/invariant/handler/user/ControllerOnlyUserHandler.sol";
import { RequesterOnlyUserHandlerBase } from "test/invariant/handler/user/RequesterOnlyUserHandler.sol";

import { UserHandlerBase } from "./UserBaseHandler.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { GlobalState } from "test/invariant/handler/GlobalState.sol";

/**
 * @title UserHandler
 * @notice A comprehensive test handler contract that combines both requester and controller functionality
 *         for testing the BasketManager protocol's user interactions.
 * @dev This contract inherits from both ControllerOnlyUserHandlerBase and RequesterOnlyUserHandlerBase,
 *      providing a complete interface for testing all user-facing operations in the BasketManager protocol.
 *
 * The contract supports two main types of operations:
 * 1. **Requester Operations**: Request deposits and redeems (asynchronous operations)
 * 2. **Controller Operations**: Execute deposits, redeems, and claim fallback assets/shares (synchronous operations)
 *
 * This dual functionality allows for comprehensive testing of the complete user workflow:
 * - Users can request deposits/redeems and then execute them
 * - Users can claim fallback assets/shares when operations fail
 * - The contract tracks successful operations for invariant testing
 *
 * @custom:security This contract is intended for testing purposes only and should not be deployed to production.
 *
 */
contract UserHandler is ControllerOnlyUserHandlerBase, RequesterOnlyUserHandlerBase {
    uint256 successfull_proRataRedeem;

    /**
     * @notice Initializes the UserHandler with the required BasketManager and role addresses
     * @param basketManager The BasketManager contract instance to interact with
     * @param basketManager The global state contract
     * @param controller The address that will act as the controller for operations.
     *                             If set to address(0), defaults to this contract's address.
     * @param owner The address that will act as the owner for operations.
     *                       If set to address(0), defaults to this contract's address.
     * @param isMalicious If the user is malicious
     * @dev The constructor sets up the contract with the necessary permissions and references
     *      to interact with the BasketManager protocol. Both controller and owner parameters
     *      can be set to address(0) to use this contract as the default actor.
     *
     * Requirements:
     * - basketManager must not be address(0)
     * - The contract will have access to all user operations on the specified BasketManager
     *
     * @custom:example
     * ```solidity
     * // Deploy with this contract as both controller and owner
     * UserHandler handler = new UserHandler(basketManager, globalState, address(0), address(0), false);
     *
     * // Deploy with specific controller and owner addresses
     * UserHandler handler = new UserHandler(basketManager, globalState, controller, owner, false);
     * ```
     */
    constructor(
        BasketManager basketManager,
        GlobalState globalState,
        address controller,
        address owner,
        bool isMalicious
    )
        UserHandlerBase(basketManager, globalState, controller, owner, isMalicious)
    { }

    /**
     * @notice Performs pro-rata redeem of shares for a basket
     * @param shares Number of shares to redeem
     * @param idxBasket Index of the basket to redeem from
     */
    function proRataRedeem(uint256 shares, uint256 idxBasket) public {
        BasketToken basket = _get_basket(idxBasket);

        try basket.proRataRedeem(shares, address(this), address(this)) {
            successfull_proRataRedeem++;
        } catch {
            _could_revert();
        }
    }
}

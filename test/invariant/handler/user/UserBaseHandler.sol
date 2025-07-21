pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

import { GlobalState } from "test/invariant/handler/GlobalState.sol";
import { ERC20DecimalsMock } from "test/utils/mocks/ERC20DecimalsMock.sol";

/**
 * @title UserHandlerBase
 * @notice Base contract for all user handlers providing common functionality
 * @dev Supports configurable controller/owner relationships and malicious actor testing
 */
contract UserHandlerBase is Test {
    BasketManager public basketManager;
    GlobalState globalState;

    uint256 TOKEN_LIMIT = 10 ** 9; // max token balance per asset (without decimals)

    address _controller_target;
    address _owner_target;
    bool _is_malicious;

    /**
     * @notice Initializes the user handler with BasketManager and role configuration
     * @param basketManagerParameter The BasketManager contract to interact with
     * @param globalStateParameter The global state contract
     * @param controllerParameter The controller address (defaults to this contract if zero)
     * @param ownerParameter The owner address (defaults to this contract if zero)
     * @param isMaliciousParameter Whether this handler should behave maliciously
     */
    constructor(
        BasketManager basketManagerParameter,
        GlobalState globalStateParameter,
        address controllerParameter,
        address ownerParameter,
        bool isMaliciousParameter
    ) {
        require(address(basketManagerParameter) != address(0));
        basketManager = basketManagerParameter;

        require(address(globalStateParameter) != address(0));
        globalState = globalStateParameter;

        if (controllerParameter == address(0x0)) {
            controllerParameter = address(this);
        }
        _controller_target = controllerParameter;

        if (ownerParameter == address(0x0)) {
            ownerParameter = address(this);
        }
        _owner_target = ownerParameter;

        _is_malicious = isMaliciousParameter;
    }

    /**
     * @notice Mints tokens to this handler for testing purposes
     * @param amount Amount to mint
     * @param idxBasket Basket index (modulo'd to valid range)
     * @param idxToken Token index within the basket (modulo'd to valid range)
     */
    function mint(uint256 amount, uint256 idxBasket, uint256 idxToken) public {
        ERC20DecimalsMock token = _get_token(_get_basket(idxBasket), idxToken);

        uint256 balance = token.balanceOf(address(this));
        uint256 decimals = token.decimals();

        // Check for overflow + token limit
        unchecked {
            if (balance + amount < balance) {
                return;
            }
            if (balance + amount > TOKEN_LIMIT * 10 ** decimals) {
                return;
            }
        }

        token.mint(address(this), amount);
    }

    /**
     * @notice Gets a basket token by index (modulo'd to valid range)
     */
    function _get_basket(uint256 idx) internal view returns (BasketToken) {
        address[] memory candidates = basketManager.basketTokens();
        return BasketToken(candidates[idx % candidates.length]);
    }

    /**
     * @notice Gets a token from a basket by index (modulo'd to valid range)
     */
    function _get_token(BasketToken basketToken, uint256 idx) internal view returns (ERC20DecimalsMock) {
        address[] memory tokens = basketToken.getAssets();
        return ERC20DecimalsMock(tokens[idx % tokens.length]);
    }

    /**
     * @notice Returns the controller address for this handler
     */
    function _controller() internal virtual returns (address) {
        return _controller_target;
    }

    /**
     * @notice Returns the owner address for this handler
     */
    function _owner() internal virtual returns (address) {
        return _owner_target;
    }

    /**
     * @notice Called on successful operations - malicious actors should fail
     */
    function _success() internal virtual {
        // Malicious actor should not be able to do succesfull operations
        if (_is_malicious) {
            assert(false);
        }
    }

    /**
     * @notice Called when operations could revert. If used with foundry
     * fail_on_revert = true, this should be overidden to prevent the revert
     */
    function _could_revert() internal virtual {
        revert();
    }
}

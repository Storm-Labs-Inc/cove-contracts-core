pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";

/**
 * @title FeeCollectorHandler
 * @notice Handler for fee collection operations
 * @dev Requires admin role on FeeCollector
 */
contract FeeCollectorHandler {
    FeeCollector feeCollector;
    BasketManager public basketManager;

    /**
     * @notice Initializes the fee collector handler
     * @param feeCollectorParameter The FeeCollector contract
     * @param basketManagerParameter The BasketManager contract
     */
    constructor(FeeCollector feeCollectorParameter, BasketManager basketManagerParameter) {
        require(address(basketManagerParameter) != address(0));
        basketManager = basketManagerParameter;

        require(address(feeCollectorParameter) != address(0));
        feeCollector = feeCollectorParameter;
    }

    /**
     * @notice Claims sponsor fees for a basket
     * @param idx Basket index (modulo'd to valid range)
     */
    function claimSponsorFee(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        feeCollector.claimSponsorFee(address(basketToken));
    }

    /**
     * @notice Claims treasury fees for a basket
     * @param idx Basket index (modulo'd to valid range)
     */
    function claimTreasuryFee(uint256 idx) public {
        BasketToken basketToken = _get_basket(idx);
        feeCollector.claimTreasuryFee(address(basketToken));
    }

    /**
     * @notice Gets a basket token by index (modulo'd to valid range)
     */
    function _get_basket(uint256 idx) internal view returns (BasketToken) {
        address[] memory candidates = basketManager.basketTokens();
        return BasketToken(candidates[idx % candidates.length]);
    }
}

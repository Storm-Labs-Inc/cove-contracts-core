pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";

/**
 * @title FakeBasketManagerForFeeCollector
 * @notice Temporary contract used during FeeCollector deployment
 * @dev Allows FeeCollector to be deployed before BasketManager, then updated with real address
 */
contract FakeBasketManagerForFeeCollector {
    BasketManager public basketManager;

    /**
     * @notice Sets the real BasketManager address after deployment
     * @param _basketManager The actual BasketManager contract address
     */
    function setManager(BasketManager _basketManager) external {
        basketManager = _basketManager;
    }

    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return basketManager.hasRole(role, account);
    }
}

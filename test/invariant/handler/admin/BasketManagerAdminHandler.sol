pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";

/**
 * @title BasketManagerAdminHandler
 * @notice Handler for administrative operations on BasketManager
 * @dev Requires TIMELOCK_ROLE, MANAGER_ROLE, and DEFAULT_ADMIN_ROLE
 */
contract BasketManagerAdminHandler {
    BasketManager basketManager;

    uint256 successfull_setManagementFee;
    uint256 successfull_setSwapFee;
    uint256 successfull_setStepDelay;
    uint256 successfull_setRetryLimit;
    uint256 successfull_setSlippageLimit;
    uint256 successfull_setWeightDeviation;

    uint256 successfull_collectSwapFee;

    uint256 successfull_pause;
    uint256 successfull_unpause;

    /**
     * @notice Initializes the admin handler
     * @param basketManagerParameter The BasketManager contract to administer
     */
    constructor(BasketManager basketManagerParameter) {
        require(address(basketManagerParameter) != address(0));
        basketManager = basketManagerParameter;
    }

    // _TIMELOCK_ROLE actions

    /**
     * @notice Sets management fee for a specific basket
     */
    function setManagementFee(address basket, uint16 managementFee_) public {
        basketManager.setManagementFee(basket, managementFee_);
        successfull_setManagementFee++;
    }

    /**
     * @notice Sets global swap fee
     */
    function setSwapFee(uint16 swapFee_) public {
        basketManager.setSwapFee(swapFee_);
        successfull_setSwapFee++;
    }

    /**
     * @notice Sets step delay for rebalance operations
     */
    function setStepDelay(uint40 stepDelay_) public {
        basketManager.setStepDelay(stepDelay_);
        successfull_setStepDelay++;
    }

    /**
     * @notice Sets retry limit for failed operations
     */
    function setRetryLimit(uint8 retryLimit_) public {
        basketManager.setRetryLimit(retryLimit_);
        successfull_setRetryLimit++;
    }

    /**
     * @notice Sets slippage limit for trades
     */
    function setSlippageLimit(uint256 slippageLimit_) public {
        basketManager.setSlippageLimit(slippageLimit_);
        successfull_setSlippageLimit++;
    }

    /**
     * @notice Sets weight deviation limit for rebalancing
     */
    function setWeightDeviation(uint256 weightDeviationLimit_) public {
        basketManager.setWeightDeviation(weightDeviationLimit_);
        successfull_setWeightDeviation++;
    }

    // Manager actions
    // Don't implement updateBitFlag, given its likely to mess up with all the settings

    /**
     * @notice Collects accumulated swap fees for an asset
     */
    function collectSwapFee(address asset) public {
        basketManager.collectSwapFee(asset);
        successfull_collectSwapFee++;
    }

    // Admin role

    /**
     * @notice Pauses the BasketManager
     */
    function pause() public {
        basketManager.pause();
        successfull_pause++;
    }

    /**
     * @notice Unpauses the BasketManager
     */
    function unpause() public {
        basketManager.unpause();
        successfull_unpause++;
    }
}

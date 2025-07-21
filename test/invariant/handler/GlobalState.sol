pragma solidity 0.8.28;

/**
 * @title GlobalState
 * @notice Simple state management contract for coordinating between handlers
 * @dev Currently tracks price updates for conditional invariant execution
 */
contract GlobalState {
    bool public price_was_updated;

    mapping(address => mapping(uint256 => address[])) public requestDepositToController;
    // Keep an internal mapping to avoid dupplicate
    mapping(address => mapping(uint256 => mapping(address => bool))) requestDepositToController_internal;

    /**
     * @notice Marks that a price update has occurred
     */
    /**
     * @notice Marks that a price update has occurred
     */
    function price_updated() public {
        price_was_updated = true;
    }

    /**
     * @notice Resets price update flag when rebalance completes
     */
    /**
     * @notice Resets price update flag when rebalance completes
     */
    function rebalance_completed() public {
        price_was_updated = false;
    }

    function add_request_deposit_controller(address basketToken, uint256 id, address controller) public {
        if (requestDepositToController_internal[basketToken][id][controller]) {
            return;
        }
        requestDepositToController[basketToken][id].push(controller);
        requestDepositToController_internal[basketToken][id][controller] = true;
    }

    function get_controller_from_request_id(address basketToken, uint256 id) public view returns (address[] memory) {
        return requestDepositToController[basketToken][id];
    }
}

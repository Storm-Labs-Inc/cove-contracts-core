// SPDX-License-Identifier: BUSL-1.1
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC4626.sol)
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

pragma solidity 0.8.18;

contract AllocationResolver is AccessControl {
    // mapping of basket address to allocation
    mapping(address => bytes32[]) public allocations;
    mapping(address => uint256) public allocationLastUpdated;
    mapping(address => address) public basketAllocationResolver;

    modifier onlyBasketResolver(address basket) {
        require(msg.sender == basketAllocationResolver[basket], "NOT_BASKET_RESOLVER");
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setAllocation(address basket, bytes32[] memory newAllocation) public onlyBasketResolver(basket) {
        require(newAllocation.length == allocations[basket].length, "INVALID_ALLOCATION_LENGTH");
        allocations[basket] = newAllocation;
        allocationLastUpdated[basket] = block.timestamp;
        // ensure that all allocations sum to 1
        uint256 sum = 0;
        for (uint256 i = 0; i < newAllocation.length; i++) {
            sum += uint256(newAllocation[i]);
        }
        require(sum == 1e18, "INVALID_ALLOCATION_SUM");
    }

    function getTargetWeight(address basket) public view returns (bytes32[] memory) {
        return allocations[basket];
    }

    function getAllocationLength(address basket) public view returns (uint256) {
        return allocations[basket].length;
    }

    function getAllocationElement(address basket, uint256 index) public view returns (bytes32) {
        return allocations[basket][index];
    }

    function setBasketResolver(address basket, address resolver) public onlyRole(DEFAULT_ADMIN_ROLE) {
        basketAllocationResolver[basket] = resolver;
    }

    function enroll(address basket, address resolver, uint256 selectionsLength) public onlyRole(DEFAULT_ADMIN_ROLE) {
        basketAllocationResolver[basket] = resolver;
        allocations[basket] = new bytes32[](selectionsLength);
    }

    function isEnrolled(address basket) public view returns (bool) {
        return basketAllocationResolver[basket] != address(0);
    }

    function isSubscribed(address basket, address proposer) public view returns (bool) {
        return basketAllocationResolver[basket] == proposer;
    }

    /**
     * @notice Checks if the strategy supports the set of assets represented as a bitFlag
     * @param bitFlag The bitFlag representing the set of assets
     * @param strategyId The strategy ID to check if it supports the bitFlag
     * @return bool True if the strategy supports the bitFlag, false otherwise
     */
    function supportsStrategy(uint256 bitFlag, uint256 strategyId) public view returns (bool) {
        // TODO: Implement checking if the strategy supports the given bitFlag
        bitFlag;
        strategyId;
        return true;
    }
}

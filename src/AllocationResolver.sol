// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC4626.sol)
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

pragma solidity ^0.8.20;

contract AllocationResolver is AccessControl {
    // mapping of basket address to allocation
    mapping(address => uint256[]) public allocations;
    mapping(address => uint256) public allocationLastUpdated;
    mapping(address => address) public basketAllocationResolver;

    constructor() {
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setAllocation(address basket, uint256[] memory newAllocation) public {
        allocations[basket] = newAllocation;
        allocationLastUpdated[basket] = block.timestamp;
    }

    function getAllocation(address basket) public view returns (uint256[] memory) {
        return allocations[basket];
    }

    function getAllocationLength(address basket) public view returns (uint256) {
        return allocations[basket].length;
    }

    function getAllocationElement(address basket, uint256 index) public view returns (uint256) {
        return allocations[basket][index];
    }

    function setBasketResolver(address basket, address resolver) public onlyRole(DEFAULT_ADMIN_ROLE) {
        basketAllocationResolver[basket] = resolver;
    }
}

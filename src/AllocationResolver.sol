// SPDX-License-Identifier: BUSL-1.1
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

pragma solidity 0.8.23;

contract AllocationResolver is AccessControl {
    // mapping of basket address to allocation
    mapping(address => uint256[]) public allocations;
    mapping(address => uint256) public allocationLastUpdated;
    mapping(address => address) public basketAllocationResolver;

    error NotBasketResolver();
    error InvalidAllocationLength();
    error InvalidAllocationSum();

    modifier onlyBasketResolver(address basket) {
        if (basketAllocationResolver[basket] != msg.sender) {
            revert NotBasketResolver();
        }
        _;
    }

    // slither-disable-next-line locked-ether
    constructor() payable {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setAllocation(address basket, uint256[] memory newAllocation) public onlyBasketResolver(basket) {
        if (newAllocation.length != allocations[basket].length) {
            revert InvalidAllocationLength();
        }
        allocations[basket] = newAllocation;
        allocationLastUpdated[basket] = block.timestamp;
        // ensure that all allocations sum to 1
        uint256 sum = 0;
        uint256 length = newAllocation.length;
        for (uint256 i = 0; i < length;) {
            sum += uint256(newAllocation[i]);
            unchecked {
                ++i;
            }
        }
        if (sum != 1e18) {
            revert InvalidAllocationSum();
        }
    }

    function getTargetWeight(address basket) public view returns (uint256[] memory) {
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

    function enroll(address basket, address resolver, uint256 selectionsLength) public onlyRole(DEFAULT_ADMIN_ROLE) {
        basketAllocationResolver[basket] = resolver;
        allocations[basket] = new uint256[](selectionsLength);
    }

    function isEnrolled(address basket) public view returns (bool) {
        return basketAllocationResolver[basket] != address(0);
    }

    function isSubscribed(address basket, address proposer) public view returns (bool) {
        return basketAllocationResolver[basket] == proposer;
    }

    /**
     * @notice Gets the assets from the bitFlag.
     * @param bitFlag The bitFlag representing the set of assets.
     * @return address[] The assets from the bitFlag.
     */
    function getAssets(uint256 bitFlag) public view returns (address[] memory) {
        // TODO: Implement getting the assets from the bitFlag
        // workaround for slither for unused variables
        // slither-disable-next-line redundant-statements
        bitFlag;
        return new address[](0);
    }

    /**
     * @notice Checks if the strategy supports the set of assets represented as a bitFlag
     * @param bitFlag The bitFlag representing the set of assets
     * @param strategyId The strategy ID to check if it supports the bitFlag
     * @return bool True if the strategy supports the bitFlag, false otherwise
     */
    function supportsStrategy(uint256 bitFlag, uint256 strategyId) public view returns (bool) {
        // TODO: Implement checking if the strategy supports the given bitFlag
        // workaround for slither for unused variables
        // slither-disable-next-line redundant-statements
        bitFlag;
        // slither-disable-next-line redundant-statements
        strategyId;
        return true;
    }
}

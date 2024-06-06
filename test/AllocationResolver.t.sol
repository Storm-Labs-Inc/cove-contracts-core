// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { AllocationResolver } from "src/AllocationResolver.sol";

contract AllocationResolverTest is BaseTest {
    AllocationResolver public allocationResolver;
    address public owner;
    address public basket;
    address public resolver;

    function setUp() public override {
        super.setUp();
        owner = createUser("owner");
        basket = address(1);
        resolver = createUser("alice");
        vm.prank(owner);
        allocationResolver = new AllocationResolver();
        vm.label(address(allocationResolver), "allocationResolver");
    }

    function test_setAllocation() public {
        uint256[] memory newAllocation = new uint256[](2);
        newAllocation[0] = uint256(5e17); // 0.5 in fixed-point
        newAllocation[1] = uint256(5e17); // 0.5 in fixed-point

        vm.prank(owner);
        allocationResolver.enroll(basket, resolver, newAllocation.length);
        vm.prank(resolver);
        allocationResolver.setAllocation(basket, newAllocation);

        assertEq(
            uint256(allocationResolver.getAllocationElement(basket, 0)),
            uint256(5e17),
            "Allocation should be set to 0.5"
        );
        assertEq(
            uint256(allocationResolver.getAllocationElement(basket, 1)),
            uint256(5e17),
            "Allocation should be set to 0.5"
        );
    }

    function test_setAllocation_InvalidLength() public {
        uint256[] memory newAllocation = new uint256[](1);
        newAllocation[0] = uint256(1e18); // 1 in fixed-point

        vm.prank(owner);
        allocationResolver.enroll(basket, resolver, 2); // Enroll with length 2
        vm.expectRevert("INVALID_ALLOCATION_LENGTH");
        vm.prank(resolver);
        allocationResolver.setAllocation(basket, newAllocation);
    }

    function test_setAllocation_InvalidSum() public {
        uint256[] memory newAllocation = new uint256[](2);
        newAllocation[0] = uint256(6e17); // 0.6 in fixed-point
        newAllocation[1] = uint256(3e17); // 0.3 in fixed-point

        vm.prank(owner);
        allocationResolver.enroll(basket, resolver, newAllocation.length);
        vm.expectRevert("INVALID_ALLOCATION_SUM");
        vm.prank(resolver);
        allocationResolver.setAllocation(basket, newAllocation);
    }

    function test_setBasketResolver() public {
        vm.prank(owner);
        allocationResolver.setBasketResolver(basket, resolver);
        assertEq(allocationResolver.basketAllocationResolver(basket), resolver, "Resolver should be set");
    }

    function test_enroll() public {
        uint256 selectionsLength = 3;
        vm.prank(owner);
        allocationResolver.enroll(basket, resolver, selectionsLength);
        assertEq(allocationResolver.getAllocationLength(basket), selectionsLength, "Allocations length should match");
        assertEq(allocationResolver.basketAllocationResolver(basket), resolver, "Resolver should be set");
    }

    function test_isEnrolled() public {
        vm.prank(owner);
        allocationResolver.enroll(basket, resolver, 1);
        assertTrue(allocationResolver.isEnrolled(basket), "Basket should be enrolled");
    }

    function test_isSubscribed() public {
        vm.prank(owner);
        allocationResolver.enroll(basket, resolver, 1);
        assertTrue(allocationResolver.isSubscribed(basket, resolver), "Resolver should be subscribed to the basket");
    }
}

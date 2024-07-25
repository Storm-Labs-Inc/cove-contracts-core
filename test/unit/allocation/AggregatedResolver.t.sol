// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AssetRegistry } from "src/AssetRegistry.sol";
import { AggregatedResolver } from "src/allocation/AggregatedResolver.sol";
import { AllocationResolver } from "src/allocation/AllocationResolver.sol";
import { CustomAllocationResolver } from "src/allocation/CustomResolver.sol";

import { BitFlag } from "src/libraries/BitFlag.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

contract AggregatedResolverTest is BaseTest {
    AggregatedResolver public aggregatedResolver;
    CustomAllocationResolver public customResolver;
    address public admin;
    address public assetRegistry;

    bytes32 private constant _ALLOCATION_RESOLVER_ROLE = keccak256("ALLOCATION_RESOLVER");

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.startPrank(admin);

        assetRegistry = createUser("assetRegistry");
        aggregatedResolver = new AggregatedResolver(admin);
        vm.stopPrank();
    }

    function testFuzz_constructor(address admin_) public {
        AggregatedResolver aggregatedResolver_ = new AggregatedResolver(admin_);
        assertTrue(
            aggregatedResolver_.hasRole(aggregatedResolver_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
    }

    function testFuzz_grantRole_AllocationResolver(address resolver) public {
        vm.prank(admin);
        aggregatedResolver.grantRole(_ALLOCATION_RESOLVER_ROLE, resolver);
        assertTrue(aggregatedResolver.hasRole(_ALLOCATION_RESOLVER_ROLE, resolver));
    }

    function testFuzz_supportsBitFlag(uint256 bitFlag, string memory resolverName) public {
        address resolver = createUser(resolverName);
        testFuzz_grantRole_AllocationResolver(resolver);

        vm.expectCall(resolver, abi.encodeWithSelector(AllocationResolver.supportsBitFlag.selector, bitFlag));
        vm.mockCall(
            resolver, abi.encodeWithSelector(AllocationResolver.supportsBitFlag.selector, bitFlag), abi.encode(true)
        );
        aggregatedResolver.supportsBitFlag(bitFlag, resolver);
    }

    function testFuzz_supportsBitFlag_ResolverNotSupported(uint256 bitFlag, address resolver) public {
        vm.expectRevert(AggregatedResolver.ResolverNotSupported.selector);
        aggregatedResolver.supportsBitFlag(bitFlag, resolver);
    }

    // TODO: remove this after BasketManager is refactored to use AssetRegistry.getAssets(bitFlag)
    function test_getAssets() public {
        address[] memory ret = aggregatedResolver.getAssets(0);
        assertEq(ret.length, 0, "Should return empty array");
    }
}

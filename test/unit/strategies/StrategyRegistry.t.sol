// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AssetRegistry } from "src/AssetRegistry.sol";

import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

import { BitFlag } from "src/libraries/BitFlag.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

contract StrategyRegistryTest is BaseTest {
    StrategyRegistry public aggregatedResolver;
    ManagedWeightStrategy public customResolver;
    address public admin;
    address public assetRegistry;

    bytes32 private constant _WEIGHT_STRATEGY_ROLE = keccak256("WEIGHT_STRATEGY");

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.startPrank(admin);

        assetRegistry = createUser("assetRegistry");
        aggregatedResolver = new StrategyRegistry(admin);
        vm.stopPrank();
    }

    function testFuzz_constructor(address admin_) public {
        StrategyRegistry aggregatedResolver_ = new StrategyRegistry(admin_);
        assertTrue(
            aggregatedResolver_.hasRole(aggregatedResolver_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
    }

    function testFuzz_grantRole_WeightStrategy(address resolver) public {
        vm.prank(admin);
        aggregatedResolver.grantRole(_WEIGHT_STRATEGY_ROLE, resolver);
        assertTrue(aggregatedResolver.hasRole(_WEIGHT_STRATEGY_ROLE, resolver));
    }

    function testFuzz_supportsBitFlag(uint256 bitFlag, string memory resolverName) public {
        address resolver = createUser(resolverName);
        testFuzz_grantRole_WeightStrategy(resolver);

        vm.expectCall(resolver, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag));
        vm.mockCall(
            resolver, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag), abi.encode(true)
        );
        aggregatedResolver.supportsBitFlag(bitFlag, resolver);
    }

    function testFuzz_supportsBitFlag_ResolverNotSupported(uint256 bitFlag, address resolver) public {
        vm.expectRevert(StrategyRegistry.ResolverNotSupported.selector);
        aggregatedResolver.supportsBitFlag(bitFlag, resolver);
    }

    // TODO: remove this after BasketManager is refactored to use AssetRegistry.getAssets(bitFlag)
    function test_getAssets() public {
        address[] memory ret = aggregatedResolver.getAssets(0);
        assertEq(ret.length, 0, "Should return empty array");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { MarketCapResolver } from "src/allocation/MarketCapResolver.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract MarketCapResolverTest is BaseTest {
    MarketCapResolver public marketCapResolver;
    address public admin;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.prank(admin);
        marketCapResolver = new MarketCapResolver(admin);
    }

    function testFuzz_constructor(address admin_) public {
        MarketCapResolver marketCapResolver_ = new MarketCapResolver(admin_);
        assertTrue(
            marketCapResolver_.hasRole(marketCapResolver_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
    }

    // Add test functions here
}

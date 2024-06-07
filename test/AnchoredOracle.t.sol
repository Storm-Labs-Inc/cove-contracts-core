// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { BaseTest } from "./utils/BaseTest.t.sol";

import { Errors } from "euler-price-oracle/src/lib/Errors.sol";
import { StubPriceOracle } from "euler-price-oracle/test/adapter/StubPriceOracle.sol";
import { console2 as console } from "forge-std/console2.sol";
import { AnchoredOracle } from "src/deps/AnchoredOracle.sol";

contract AnchoredOracleTest is BaseTest {
    /// @notice The lower bound for `maxDivergence`, 0.1%.
    uint256 internal constant MAX_DIVERGENCE_LOWER_BOUND = 0.001e18;
    /// @notice The upper bound for `maxDivergence`, 50%.
    uint256 internal constant MAX_DIVERGENCE_UPPER_BOUND = 0.5e18;

    uint256 MAX_DIVERGENCE = 0.1e18;
    StubPriceOracle primary;
    StubPriceOracle anchor;
    AnchoredOracle oracle;

    function setUp() public override {
        primary = new StubPriceOracle();
        anchor = new StubPriceOracle();
        oracle = new AnchoredOracle(address(primary), address(anchor), MAX_DIVERGENCE);
    }

    function test_constructor() public view {
        assertEq(oracle.primaryOracle(), address(primary));
        assertEq(oracle.anchorOracle(), address(anchor));
        assertEq(oracle.maxDivergence(), MAX_DIVERGENCE);
    }

    function test_constructor_revertsWhen_maxDivergenceTooLow(
        address base,
        address quote,
        uint256 maxDivergence
    )
        public
    {
        maxDivergence = bound(maxDivergence, 0, MAX_DIVERGENCE_LOWER_BOUND - 1);
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new AnchoredOracle(base, quote, maxDivergence);
    }

    function test_constructor_revertsWhen_maxDivergenceTooHigh(
        address base,
        address quote,
        uint256 maxDivergence
    )
        public
    {
        maxDivergence = bound(maxDivergence, MAX_DIVERGENCE_UPPER_BOUND + 1, type(uint256).max);
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new AnchoredOracle(base, quote, maxDivergence);
    }
}

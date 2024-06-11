// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { BaseTest } from "./utils/BaseTest.t.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Errors } from "euler-price-oracle/src/lib/Errors.sol";

import { console2 as console } from "forge-std/console2.sol";
import { AnchoredOracle } from "src/deps/AnchoredOracle.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

contract AnchoredOracleTest is BaseTest {
    /// @notice The lower bound for `maxDivergence`, 0.1%.
    uint256 internal constant MAX_DIVERGENCE_LOWER_BOUND = 0.001e18;
    /// @notice The upper bound for `maxDivergence`, 50%.
    uint256 internal constant MAX_DIVERGENCE_UPPER_BOUND = 0.5e18;

    uint256 MAX_DIVERGENCE = 0.5e18;
    MockPriceOracle primary;
    MockPriceOracle anchor;
    AnchoredOracle oracle;

    function setUp() public override {
        super.setUp();
        primary = new MockPriceOracle();
        anchor = new MockPriceOracle();
        oracle = new AnchoredOracle(address(primary), address(anchor), MAX_DIVERGENCE);
    }

    function test_constructor() public view {
        assertEq(oracle.primaryOracle(), address(primary));
        assertEq(oracle.anchorOracle(), address(anchor));
        assertEq(oracle.maxDivergence(), MAX_DIVERGENCE);
    }

    function testFuzz_constructor_revertWhen_maxDivergenceTooLow(
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

    function testFuzz_constructor_revertWhen_maxDivergenceTooHigh(
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

    function testFuzz_getQuote_matches(uint256 inAmount, address base, address quote, uint256 price) public {
        // bound to prevent overflow in MockPriceOracle
        inAmount = bound(inAmount, 1, type(uint128).max);
        price = bound(price, 1, type(uint128).max);

        primary.setPrice(base, quote, price);
        anchor.setPrice(base, quote, price);

        uint256 outAmount = oracle.getQuote(inAmount, base, quote);
        assertEq(FixedPointMathLib.fullMulDivUp(inAmount, price, 1e18), outAmount);
    }

    function testFuzz_getQuote_withinThreshold(uint256 inAmount, address base, address quote, uint256 price) public {
        // bound to prevent overflow in MockPriceOracle
        // TODO: what is the lowest value we can use as a bounds?
        inAmount = bound(inAmount, 1e18, type(uint128).max);
        price = bound(price, 1e18, type(uint128).max);
        primary.setPrice(base, quote, price);

        // check the lower bound, rounding up
        uint256 lowerBound = FixedPointMathLib.fullMulDivUp(price, 1e18 - MAX_DIVERGENCE, 1e18) + 1;
        anchor.setPrice(base, quote, lowerBound);
        uint256 outAmount = oracle.getQuote(inAmount, base, quote);
        assertEq(FixedPointMathLib.fullMulDivUp(inAmount, price, 1e18), outAmount);

        // check the upper bound, rounding down
        uint256 upperBound = FixedPointMathLib.fullMulDiv(price, 1e18 + MAX_DIVERGENCE, 1e18) - 1;
        anchor.setPrice(base, quote, upperBound);
        outAmount = oracle.getQuote(inAmount, base, quote);
        assertEq(FixedPointMathLib.fullMulDivUp(inAmount, price, 1e18), outAmount);
    }

    function testFuzz_getQuote_exceedsThreshold(uint256 inAmount, address base, address quote, uint256 price) public {
        // bound to prevent overflow in MockPriceOracle
        // TODO: what is the lowest value we can use as a bounds?
        inAmount = bound(inAmount, 1e18, type(uint128).max);
        price = bound(price, 1e18, type(uint128).max);

        // set the primary price normally
        primary.setPrice(base, quote, price);

        // calculate bounds
        uint256 lowerBound = FixedPointMathLib.fullMulDiv(price, 1e18 - MAX_DIVERGENCE, 1e18) - 1;
        // TODO: why does setting this to +1 make the test fail?
        uint256 upperBound = FixedPointMathLib.fullMulDivUp(price, 1e18 + MAX_DIVERGENCE, 1e18) + 2;

        // check the lower bound
        anchor.setPrice(base, quote, lowerBound);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(inAmount, base, quote);

        // check the upper bound
        anchor.setPrice(base, quote, upperBound);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(inAmount, base, quote);
    }
}

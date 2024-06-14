// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Errors } from "euler-price-oracle/src/lib/Errors.sol";

import { AnchoredOracle } from "src/AnchoredOracle.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

contract AnchoredOracleTest is BaseTest {
    /// @notice The lower bound for `maxDivergence`, 0.1%.
    uint256 internal constant _MAX_DIVERGENCE_LOWER_BOUND = 0.001e18;
    /// @notice The upper bound for `maxDivergence`, 50%.
    uint256 internal constant _MAX_DIVERGENCE_UPPER_BOUND = 0.5e18;

    uint256 public MAX_DIVERGENCE = 0.5e18;
    MockPriceOracle public primary;
    MockPriceOracle public anchor;
    AnchoredOracle public oracle;

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

    function test_constructor_revertWhen_zeroPrimaryOracle() public {
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        oracle = new AnchoredOracle(address(0), address(anchor), MAX_DIVERGENCE);
    }

    function test_constructor_revertWhen_zeroAnchorOracle() public {
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        oracle = new AnchoredOracle(address(primary), address(0), MAX_DIVERGENCE);
    }

    function testFuzz_constructor_revertWhen_maxDivergenceTooLow(
        address primary_,
        address anchor_,
        uint256 maxDivergence
    )
        public
    {
        maxDivergence = bound(maxDivergence, 0, _MAX_DIVERGENCE_LOWER_BOUND - 1);
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new AnchoredOracle(primary_, anchor_, maxDivergence);
    }

    function testFuzz_constructor_revertWhen_maxDivergenceTooHigh(
        address primary_,
        address anchor_,
        uint256 maxDivergence
    )
        public
    {
        maxDivergence = bound(maxDivergence, _MAX_DIVERGENCE_UPPER_BOUND + 1, type(uint256).max);
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new AnchoredOracle(primary_, anchor_, maxDivergence);
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
        uint256 primaryOut = primary.getQuote(inAmount, base, quote);

        // check the lower bound, rounding up
        uint256 lowerBound = FixedPointMathLib.fullMulDivUp(primaryOut, 1e18 - MAX_DIVERGENCE, 1e18);
        uint256 anchorPrice = FixedPointMathLib.fullMulDivUp(lowerBound, 1e18, inAmount);

        // set the anchor price such that the quote output is equal to the lower bound
        anchor.setPrice(base, quote, anchorPrice);
        uint256 outAmount = oracle.getQuote(inAmount, base, quote);
        assertEq(FixedPointMathLib.fullMulDivUp(inAmount, price, 1e18), outAmount);

        // check the upper bound, rounding down
        uint256 upperBound = FixedPointMathLib.fullMulDiv(primaryOut, 1e18 + MAX_DIVERGENCE, 1e18);
        anchorPrice = FixedPointMathLib.fullMulDiv(upperBound, 1e18, inAmount);

        // set the anchor price such that the quote output is equal to the upper bound
        anchor.setPrice(base, quote, anchorPrice);
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
        uint256 primaryOut = primary.getQuote(inAmount, base, quote);

        // calculate bounds
        uint256 lowerBound = FixedPointMathLib.fullMulDivUp(primaryOut, 1e18 - MAX_DIVERGENCE, 1e18);
        uint256 anchorPrice = FixedPointMathLib.fullMulDivUp(lowerBound, 1e18, inAmount) - 1;

        // set the anchor price such that the quote output is 1 less than the lower bound
        anchor.setPrice(base, quote, anchorPrice - 1);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(inAmount, base, quote);

        // calculate bounds
        uint256 upperBound = FixedPointMathLib.fullMulDiv(primaryOut, 1e18 + MAX_DIVERGENCE, 1e18);
        anchorPrice = FixedPointMathLib.fullMulDiv(upperBound, 1e18, inAmount) + 1;

        // set the anchor price such that the quote output is 1 more than the upper bound
        anchor.setPrice(base, quote, anchorPrice);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(inAmount, base, quote);
    }
}

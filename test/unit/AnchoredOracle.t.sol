// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Errors } from "euler-price-oracle/src/lib/Errors.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";

contract AnchoredOracleTest is BaseTest {
    using FixedPointMathLib for uint256;
    /// @notice The lower bound for `maxDivergence`, 0.1%.

    uint256 internal constant _MAX_DIVERGENCE_LOWER_BOUND = 0.001e18;
    /// @notice The upper bound for `maxDivergence`, 50%.
    uint256 internal constant _MAX_DIVERGENCE_UPPER_BOUND = 0.5e18;
    /// @notice The denominator for `maxDivergence`.
    uint256 internal constant _WAD = 1e18;

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

    // Helper function to calculate values needed for checks, considering scaling
    function _calculateCheckValuesAndBounds(
        uint256 inAmount,
        address base,
        address quote
    )
        internal
        view
        returns (
            uint256 originalPrimaryOutAmount,
            uint256 scaledInAmount,
            uint256 primaryToCheck,
            uint256 lowerBound,
            uint256 upperBound
        )
    {
        originalPrimaryOutAmount = primary.getQuote(inAmount, base, quote);

        if (originalPrimaryOutAmount < _WAD) {
            // Prevent overflow when scaling the input amount
            // Use type(uint256).max / _WAD which is roughly 1.157e59
            uint256 maxInAmount = type(uint256).max / _WAD;
            vm.assume(inAmount <= maxInAmount);

            scaledInAmount = inAmount * _WAD;
            primaryToCheck = primary.getQuote(scaledInAmount, base, quote);
        } else {
            scaledInAmount = inAmount; // Use original amount if no scaling needed
            primaryToCheck = originalPrimaryOutAmount;
        }

        lowerBound = FixedPointMathLib.fullMulDivUp(primaryToCheck, _WAD - MAX_DIVERGENCE, _WAD);
        upperBound = FixedPointMathLib.fullMulDiv(primaryToCheck, _WAD + MAX_DIVERGENCE, _WAD);
    }

    function testFuzz_getQuote_matches(uint256 inAmount, address base, address quote, uint256 price) public {
        // bound to prevent overflow in MockPriceOracle
        inAmount = bound(inAmount, 0, type(uint128).max);
        price = bound(price, 1, type(uint128).max);

        primary.setPrice(base, quote, price);
        anchor.setPrice(base, quote, price);

        uint256 outAmount = oracle.getQuote(inAmount, base, quote);
        assertEq(outAmount, primary.getQuote(inAmount, base, quote), "returns primary quote");
    }

    function test_getQuote_withinThreshold() public {
        address a1 = makeAddr("a1");
        address a2 = makeAddr("a2");
        primary.setPrice(a1, a2, 1e18);

        // Test lower bound
        anchor.setPrice(a1, a2, 0.5e18);
        assertEq(oracle.getQuote(1e18, a1, a2), 1e18);

        // Test upper bound
        anchor.setPrice(a1, a2, 1.5e18);
        assertEq(oracle.getQuote(1e18, a1, a2), 1e18);

        // Test below lower bound - should revert
        anchor.setPrice(a1, a2, 0.5e18 - 1);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(1e18, a1, a2);

        // Test above upper bound - should revert
        anchor.setPrice(a1, a2, 1.5e18 + 1);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(1e18, a1, a2);

        // Test edge cases
        anchor.setPrice(a1, a2, 0.501e18); // Just above lower bound
        assertEq(oracle.getQuote(1e18, a1, a2), 1e18);

        anchor.setPrice(a1, a2, 1.499e18); // Just below upper bound
        assertEq(oracle.getQuote(1e18, a1, a2), 1e18);
    }

    function testFuzz_getQuote_withinThreshold(uint256 inAmount, address base, address quote, uint256 price) public {
        // bound to prevent overflow in MockPriceOracle
        inAmount = bound(inAmount, 0, type(uint128).max);
        price = bound(price, 1, type(uint128).max);

        primary.setPrice(base, quote, price);

        (uint256 originalPrimaryOut, uint256 scaledIn,, uint256 lowerBound, uint256 upperBound) =
            _calculateCheckValuesAndBounds(inAmount, base, quote);

        // Check lower bound: Mock anchor to return exactly lowerBound for the (potentially scaled) input
        vm.mockCall(
            address(anchor), abi.encodeCall(MockPriceOracle.getQuote, (scaledIn, base, quote)), abi.encode(lowerBound)
        );
        uint256 outAmountLower = oracle.getQuote(inAmount, base, quote);
        assertEq(outAmountLower, originalPrimaryOut, "Lower bound check failed");

        // Check upper bound: Mock anchor to return exactly upperBound for the (potentially scaled) input
        vm.mockCall(
            address(anchor), abi.encodeCall(MockPriceOracle.getQuote, (scaledIn, base, quote)), abi.encode(upperBound)
        );
        uint256 outAmountUpper = oracle.getQuote(inAmount, base, quote);
        assertEq(outAmountUpper, originalPrimaryOut, "Upper bound check failed");

        // Check middle value (if possible)
        if (upperBound > lowerBound) {
            uint256 midBound = lowerBound + (upperBound - lowerBound) / 2;
            vm.mockCall(
                address(anchor), abi.encodeCall(MockPriceOracle.getQuote, (scaledIn, base, quote)), abi.encode(midBound)
            );
            uint256 outAmountMid = oracle.getQuote(inAmount, base, quote);
            assertEq(outAmountMid, originalPrimaryOut, "Mid bound check failed");
        }
    }

    function testFuzz_getQuote_revertWhen_exceedsThreshold(
        uint256 inAmount,
        address base,
        address quote,
        uint256 price
    )
        public
    {
        // bound to prevent overflow in MockPriceOracle
        inAmount = bound(inAmount, 1, type(uint128).max);
        price = bound(price, 1, type(uint128).max);

        primary.setPrice(base, quote, price);

        (, uint256 scaledIn,, uint256 lowerBound, uint256 upperBound) =
            _calculateCheckValuesAndBounds(inAmount, base, quote);

        // Check below lower bound: Mock anchor to return lowerBound - 1 for the (potentially scaled) input
        if (lowerBound > 0) {
            // Avoid underflow
            vm.mockCall(
                address(anchor),
                abi.encodeCall(MockPriceOracle.getQuote, (scaledIn, base, quote)),
                abi.encode(lowerBound - 1)
            );
            vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
            oracle.getQuote(inAmount, base, quote);
        }

        // Check above upper bound: Mock anchor to return upperBound + 1 for the (potentially scaled) input
        if (upperBound < type(uint256).max) {
            // Avoid overflow
            vm.mockCall(
                address(anchor),
                abi.encodeCall(MockPriceOracle.getQuote, (scaledIn, base, quote)),
                abi.encode(upperBound + 1)
            );
            vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
            oracle.getQuote(inAmount, base, quote);
        }
    }

    function testFuzz_getQuote_revertWhen_AnchoredOracle_ScalingOverflow(
        uint256 inAmount,
        address base,
        address quote,
        uint256 primaryOracleOutAmount
    )
        public
    {
        inAmount = bound(inAmount, type(uint256).max / _WAD + 1, type(uint256).max);
        primaryOracleOutAmount = bound(primaryOracleOutAmount, 0, _WAD - 1);
        vm.mockCall(
            address(primary),
            abi.encodeCall(MockPriceOracle.getQuote, (inAmount, base, quote)),
            abi.encode(primaryOracleOutAmount)
        );
        vm.expectRevert(AnchoredOracle.AnchoredOracle_ScalingOverflow.selector);
        oracle.getQuote(inAmount, base, quote);
    }
}

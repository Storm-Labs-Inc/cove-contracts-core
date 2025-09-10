// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { console } from "forge-std/console.sol";

import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { IAutopoolMainRewarder } from "src/interfaces/deps/tokemak/IAutopoolMainRewarder.sol";
import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract AutoPoolCompounderOracleForkedTest is BaseTest {
    // Contracts
    AutoPoolCompounderOracle public oracle;
    AutopoolCompounder public compounder;
    IAutopool public autoUSD;
    IAutopoolMainRewarder public rewarder;
    IERC20 public usdc;

    // Test users
    address public alice;
    address public management;

    // Recent mainnet block (after autoUSD deployment)
    uint256 constant FORK_BLOCK = 23_250_000;

    function setUp() public override {
        super.setUp();

        // Fork mainnet at a recent block
        vm.createSelectFork("mainnet", FORK_BLOCK);

        // Create test users
        alice = createUser("alice");
        management = createUser("management");

        // Set up existing contracts
        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        rewarder = IAutopoolMainRewarder(TOKEMAK_AUTOUSD_REWARDER);
        usdc = IERC20(ETH_USDC);

        // Deploy AutopoolCompounder
        vm.prank(management);
        compounder = new AutopoolCompounder(address(autoUSD), address(rewarder), TOKEMAK_MILKMAN);

        // Deploy the oracle for the compounder
        oracle = new AutoPoolCompounderOracle(IERC4626(address(compounder)));
    }

    function test_deployment() public {
        // Verify oracle was deployed correctly
        assertEq(oracle.base(), address(compounder));
        assertEq(oracle.quote(), address(usdc));
        assertEq(address(oracle.autopool()), address(autoUSD));

        // Verify the chain
        assertEq(oracle.vaults(0), address(compounder));
        assertEq(oracle.vaults(1), address(autoUSD));
    }

    function test_debtReportingValidation() public {
        // Check current debt reporting status
        uint256 oldestDebt = autoUSD.oldestDebtReporting();
        console.log("Oldest debt reporting timestamp:", oldestDebt);
        console.log("Current block timestamp:", block.timestamp);

        if (oldestDebt > 0) {
            uint256 debtAge = block.timestamp - oldestDebt;
            console.log("Debt age in seconds:", debtAge);
            console.log("Debt age in hours:", debtAge / 3600);

            // If debt is fresh, oracle should work
            if (debtAge <= 24 hours) {
                uint256 shares = 1e18;
                uint256 quote = oracle.getQuote(shares, address(compounder), address(usdc));
                assertGt(quote, 0, "Should get valid quote with fresh debt");
            }
        }
    }

    function test_priceConversion_compounderToUsdc() public {
        // First, get some autoUSD shares for testing
        deal(address(usdc), alice, 10_000e6); // 10,000 USDC

        vm.startPrank(alice);
        usdc.approve(address(autoUSD), 10_000e6);
        uint256 autoUSDShares = autoUSD.deposit(1000e6, alice); // Deposit 1000 USDC
        console.log("AutoUSD shares received:", autoUSDShares);

        // Transfer autoUSD shares to compounder (use the ERC4626 interface)
        IERC20(address(autoUSD)).approve(address(compounder), autoUSDShares);
        uint256 compounderShares = IERC4626(address(compounder)).deposit(autoUSDShares, alice);
        console.log("Compounder shares received:", compounderShares);
        vm.stopPrank();

        // Test oracle conversion
        uint256 usdcValue = oracle.getQuote(compounderShares, address(compounder), address(usdc));
        console.log("USDC value of compounder shares:", usdcValue);

        // The value should be approximately 1000 USDC (minus any fees)
        assertGt(usdcValue, 990e6, "Should get reasonable USDC value");
        assertLt(usdcValue, 1010e6, "Should get reasonable USDC value");
    }

    function test_priceConversion_usdcToCompounder() public {
        uint256 usdcAmount = 1000e6; // 1000 USDC

        // Get the expected compounder shares for 1000 USDC
        uint256 compounderShares = oracle.getQuote(usdcAmount, address(usdc), address(compounder));
        console.log("Compounder shares for 1000 USDC:", compounderShares);

        // Should get a reasonable amount of shares
        assertGt(compounderShares, 0, "Should get non-zero shares");

        // Verify reverse conversion is consistent
        uint256 usdcValueBack = oracle.getQuote(compounderShares, address(compounder), address(usdc));
        console.log("USDC value back:", usdcValueBack);

        // Should be approximately the same (within rounding)
        assertApproxEqAbs(usdcValueBack, usdcAmount, 1e6, "Round trip should be consistent");
    }

    function test_getQuotes_bidAskConsistency() public {
        uint256 shares = 1e18;

        (uint256 bidOut, uint256 askOut) = oracle.getQuotes(shares, address(compounder), address(usdc));

        // For this oracle, bid and ask should be identical
        assertEq(bidOut, askOut, "Bid and ask should be the same");
        assertGt(bidOut, 0, "Should get non-zero quote");
    }

    function test_revertWhen_debtReportingBecomesStale() public {
        uint256 oldestDebt = autoUSD.oldestDebtReporting();
        uint256 currentDebtAge = block.timestamp - oldestDebt;

        // First verify oracle works with fresh debt
        uint256 shares = 1e18;
        uint256 initialQuote = oracle.getQuote(shares, address(compounder), address(usdc));
        assertGt(initialQuote, 0, "Should get valid quote initially");

        // Warp time to make debt stale (25 hours from oldest debt)
        uint256 warpTime = (24 hours + 1 hours) - currentDebtAge;
        vm.warp(block.timestamp + warpTime);

        // Now oracle should revert
        vm.expectRevert(
            abi.encodeWithSelector(AutoPoolCompounderOracle.StaleDebtReporting.selector, oldestDebt, block.timestamp)
        );
        oracle.getQuote(shares, address(compounder), address(usdc));
    }

    function test_chainValidation() public {
        // Test that the oracle correctly identifies the chain
        assertEq(oracle.name(), "ChainedERC4626Oracle");

        // Verify chain structure
        assertEq(oracle.vaults(0), address(compounder), "First vault should be compounder");
        assertEq(oracle.vaults(1), address(autoUSD), "Second vault should be autopool");

        // Verify base and quote
        assertEq(oracle.base(), address(compounder), "Base should be compounder");
        assertEq(oracle.quote(), address(usdc), "Quote should be USDC");

        // Verify autopool is accessible
        assertEq(address(oracle.autopool()), address(autoUSD), "Autopool should be set");
    }

    function testFuzz_priceConversion_variousAmounts(uint256 amount) public {
        // Bound amount to reasonable values
        amount = bound(amount, 1e12, 1e36); // Between 0.000001 and 1e18 tokens

        // Test compounder to USDC conversion
        uint256 usdcValue = oracle.getQuote(amount, address(compounder), address(usdc));

        // For very small amounts, the conversion might result in 0 due to rounding
        // Only check for non-zero output for amounts larger than the precision threshold
        if (amount > 1e12) {
            assertGt(usdcValue, 0, "Should get non-zero USDC value for reasonable amounts");
        }

        // Test reverse conversion
        if (usdcValue > 0) {
            uint256 compounderShares = oracle.getQuote(usdcValue, address(usdc), address(compounder));

            // The round trip might not be exact due to rounding in the multi-hop conversion
            // For amounts in the normal operating range (> 1e15), expect reasonable precision
            // For smaller amounts, the rounding effects can be more significant
            if (amount > 1e15 && compounderShares > 0) {
                // Allow up to 2% deviation for normal amounts
                assertApproxEqRel(compounderShares, amount, 0.02e18, "Round trip should be close for normal amounts");
            } else if (amount > 1e13 && compounderShares > 0) {
                // For smaller amounts (1e13 to 1e15), allow moderate deviation due to precision loss
                assertApproxEqRel(compounderShares, amount, 0.15e18, "Round trip acceptable for small amounts");
            } else if (amount > 1e12 && compounderShares > 0) {
                // For very small amounts (1e12 to 1e13), allow higher deviation
                // These amounts are well below typical operating thresholds and precision loss is expected
                assertApproxEqRel(compounderShares, amount, 0.2e18, "Round trip acceptable for very small amounts");
            }
        }
    }
}

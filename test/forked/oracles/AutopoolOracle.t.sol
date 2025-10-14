// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { console } from "forge-std/console.sol";

import { Errors as PriceOracleErrors } from "euler-price-oracle/src/lib/Errors.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { AutopoolOracle } from "src/oracles/AutopoolOracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract AutopoolOracleForkedTest is BaseTest {
    // Ethereum mainnet tests
    AutopoolOracle public autopoolOracleEth;
    IAutopool public autoUSD;
    IERC20 public usdc;

    // Base mainnet tests
    AutopoolOracle public autopoolOracleBase;
    IAutopool public baseUSD;
    IERC20 public usdcBase;

    // Test users
    address public alice;

    // Fork block numbers
    uint256 constant FORK_BLOCK_ETH = 23_543_285; // Current Ethereum block
    uint256 constant FORK_BLOCK_BASE = 36_368_200; // Default Base fork block from bash script

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
    }

    /*//////////////////////////////////////////////////////////////
                    ETHEREUM MAINNET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);

        // Deploy the oracle
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        // Verify oracle was deployed correctly
        assertEq(autopoolOracleEth.base(), address(autoUSD));
        assertEq(autopoolOracleEth.quote(), address(usdc));
        assertEq(address(autopoolOracleEth.autopool()), address(autoUSD));
        assertEq(autopoolOracleEth.name(), "AutopoolOracle");
    }

    function test_debtReportingValidation_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

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
                uint256 quote = autopoolOracleEth.getQuote(shares, address(autoUSD), address(usdc));
                assertGt(quote, 0, "Should get valid quote with fresh debt");
            }
        }
    }

    function test_priceConversion_autoUSDToUsdc_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        // Test with 1000 autoUSD shares
        uint256 shares = 1000e18;
        uint256 usdcValue = autopoolOracleEth.getQuote(shares, address(autoUSD), address(usdc));
        console.log("USDC value for 1000 autoUSD shares:", usdcValue);

        // Should get a reasonable USDC value (autoUSD is roughly 1:1 with USDC)
        assertGt(usdcValue, 900e6, "Should get reasonable USDC value");
        assertLt(usdcValue, 1100e6, "Should get reasonable USDC value");
    }

    function test_priceConversion_usdcToAutoUSD_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        uint256 usdcAmount = 1000e6; // 1000 USDC

        // Get the expected autoUSD shares for 1000 USDC
        uint256 shares = autopoolOracleEth.getQuote(usdcAmount, address(usdc), address(autoUSD));
        console.log("AutoUSD shares for 1000 USDC:", shares);

        // Should get a reasonable amount of shares
        assertGt(shares, 0, "Should get non-zero shares");

        // Verify reverse conversion is consistent
        uint256 usdcValueBack = autopoolOracleEth.getQuote(shares, address(autoUSD), address(usdc));
        console.log("USDC value back:", usdcValueBack);

        // Should be approximately the same (within rounding)
        assertApproxEqAbs(usdcValueBack, usdcAmount, 10e6, "Round trip should be consistent");
    }

    function test_revertWhen_debtReportingBecomesStale_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        uint256 oldestDebt = autoUSD.oldestDebtReporting();

        // Skip test if oldestDebt is 0
        if (oldestDebt == 0) {
            console.log("Skipping test - oldestDebtReporting is 0");
            return;
        }

        uint256 currentDebtAge = block.timestamp - oldestDebt;

        // First verify oracle works with fresh debt
        uint256 shares = 1e18;
        uint256 initialQuote = autopoolOracleEth.getQuote(shares, address(autoUSD), address(usdc));
        assertGt(initialQuote, 0, "Should get valid quote initially");

        // Warp time to make debt stale (25 hours from oldest debt)
        uint256 warpTime = (24 hours + 1 hours) - currentDebtAge;
        vm.warp(block.timestamp + warpTime);

        // Now oracle should revert
        vm.expectRevert(abi.encodeWithSelector(AutopoolOracle.StaleDebtReporting.selector, oldestDebt, block.timestamp));
        autopoolOracleEth.getQuote(shares, address(autoUSD), address(usdc));
    }

    function testFuzz_priceConversion_variousAmounts_ethereum(uint256 amount) public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        // Bound amount to reasonable values (0.01 to 1 billion autoUSD)
        amount = bound(amount, 1e16, 1e27);

        // Test autoUSD to USDC conversion
        uint256 usdcValue = autopoolOracleEth.getQuote(amount, address(autoUSD), address(usdc));

        // Should always get non-zero output for these amounts
        assertGt(usdcValue, 0, "Should get non-zero USDC value");

        // Test reverse conversion
        uint256 sharesBack = autopoolOracleEth.getQuote(usdcValue, address(usdc), address(autoUSD));

        // Allow up to 0.1% deviation due to rounding
        if (sharesBack > 0) {
            assertApproxEqRel(sharesBack, amount, 0.001e18, "Round trip should be close");
        }
    }

    function test_getQuote_revertWhen_invalidTokens_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        address randomAddress = address(0x123);

        // Test invalid base
        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, randomAddress, address(usdc))
        );
        autopoolOracleEth.getQuote(1e18, randomAddress, address(usdc));

        // Test invalid quote
        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, address(autoUSD), randomAddress)
        );
        autopoolOracleEth.getQuote(1e18, address(autoUSD), randomAddress);
    }

    function test_getQuote_zeroAmount_ethereum() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_ETH);

        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        usdc = IERC20(ETH_USDC);
        autopoolOracleEth = new AutopoolOracle(IERC4626(address(autoUSD)));

        // Zero amount should return zero
        uint256 result = autopoolOracleEth.getQuote(0, address(autoUSD), address(usdc));
        assertEq(result, 0);

        result = autopoolOracleEth.getQuote(0, address(usdc), address(autoUSD));
        assertEq(result, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    BASE MAINNET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment_base() public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);

        // Deploy the oracle
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        // Verify oracle was deployed correctly
        assertEq(autopoolOracleBase.base(), address(baseUSD));
        assertEq(autopoolOracleBase.quote(), address(usdcBase));
        assertEq(address(autopoolOracleBase.autopool()), address(baseUSD));
        assertEq(autopoolOracleBase.name(), "AutopoolOracle");
    }

    function test_debtReportingValidation_base() public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        // Check current debt reporting status
        uint256 oldestDebt = baseUSD.oldestDebtReporting();
        console.log("[BASE] Oldest debt reporting timestamp:", oldestDebt);
        console.log("[BASE] Current block timestamp:", block.timestamp);

        if (oldestDebt > 0) {
            uint256 debtAge = block.timestamp - oldestDebt;
            console.log("[BASE] Debt age in seconds:", debtAge);
            console.log("[BASE] Debt age in hours:", debtAge / 3600);

            // If debt is fresh, oracle should work
            if (debtAge <= 24 hours) {
                uint256 shares = 1e18;
                uint256 quote = autopoolOracleBase.getQuote(shares, address(baseUSD), address(usdcBase));
                assertGt(quote, 0, "Should get valid quote with fresh debt");
            }
        }
    }

    function test_priceConversion_baseUSDToUsdc_base() public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        // Test with 1000 baseUSD shares
        uint256 shares = 1000e18;
        uint256 usdcValue = autopoolOracleBase.getQuote(shares, address(baseUSD), address(usdcBase));
        console.log("[BASE] USDC value for 1000 baseUSD shares:", usdcValue);

        // Should get a reasonable USDC value (baseUSD is roughly 1:1 with USDC)
        assertGt(usdcValue, 900e6, "Should get reasonable USDC value");
        assertLt(usdcValue, 1100e6, "Should get reasonable USDC value");
    }

    function test_priceConversion_usdcToBaseUSD_base() public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        uint256 usdcAmount = 1000e6; // 1000 USDC

        // Get the expected baseUSD shares for 1000 USDC
        uint256 shares = autopoolOracleBase.getQuote(usdcAmount, address(usdcBase), address(baseUSD));
        console.log("[BASE] BaseUSD shares for 1000 USDC:", shares);

        // Should get a reasonable amount of shares
        assertGt(shares, 0, "Should get non-zero shares");

        // Verify reverse conversion is consistent
        uint256 usdcValueBack = autopoolOracleBase.getQuote(shares, address(baseUSD), address(usdcBase));
        console.log("[BASE] USDC value back:", usdcValueBack);

        // Should be approximately the same (within rounding)
        assertApproxEqAbs(usdcValueBack, usdcAmount, 10e6, "Round trip should be consistent");
    }

    function test_revertWhen_debtReportingBecomesStale_base() public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        uint256 oldestDebt = baseUSD.oldestDebtReporting();

        // Skip test if oldestDebt is 0
        if (oldestDebt == 0) {
            console.log("[BASE] Skipping test - oldestDebtReporting is 0");
            return;
        }

        uint256 currentDebtAge = block.timestamp - oldestDebt;

        // First verify oracle works with fresh debt
        uint256 shares = 1e18;
        uint256 initialQuote = autopoolOracleBase.getQuote(shares, address(baseUSD), address(usdcBase));
        assertGt(initialQuote, 0, "Should get valid quote initially");

        // Warp time to make debt stale (25 hours from oldest debt)
        uint256 warpTime = (24 hours + 1 hours) - currentDebtAge;
        vm.warp(block.timestamp + warpTime);

        // Now oracle should revert
        vm.expectRevert(abi.encodeWithSelector(AutopoolOracle.StaleDebtReporting.selector, oldestDebt, block.timestamp));
        autopoolOracleBase.getQuote(shares, address(baseUSD), address(usdcBase));
    }

    function testFuzz_priceConversion_variousAmounts_base(uint256 amount) public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        // Bound amount to reasonable values (0.01 to 1 billion baseUSD)
        amount = bound(amount, 1e16, 1e27);

        // Test baseUSD to USDC conversion
        uint256 usdcValue = autopoolOracleBase.getQuote(amount, address(baseUSD), address(usdcBase));

        // Should always get non-zero output for these amounts
        assertGt(usdcValue, 0, "Should get non-zero USDC value");

        // Test reverse conversion
        uint256 sharesBack = autopoolOracleBase.getQuote(usdcValue, address(usdcBase), address(baseUSD));

        // Allow up to 0.1% deviation due to rounding
        if (sharesBack > 0) {
            assertApproxEqRel(sharesBack, amount, 0.001e18, "Round trip should be close");
        }
    }

    function test_getQuote_zeroAmount_base() public {
        vm.createSelectFork("base", FORK_BLOCK_BASE);

        baseUSD = IAutopool(BASE_BASEUSD);
        usdcBase = IERC20(BASE_USDC);
        autopoolOracleBase = new AutopoolOracle(IERC4626(address(baseUSD)));

        // Zero amount should return zero
        uint256 result = autopoolOracleBase.getQuote(0, address(baseUSD), address(usdcBase));
        assertEq(result, 0);

        result = autopoolOracleBase.getQuote(0, address(usdcBase), address(baseUSD));
        assertEq(result, 0);
    }
}

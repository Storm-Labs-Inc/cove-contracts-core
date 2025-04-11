// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Errors as PriceOracleErrors } from "euler-price-oracle-1/src/adapter/BaseAdapter.sol";
import { ICurvePool } from "euler-price-oracle-1/src/adapter/curve/ICurvePool.sol";
import { Scale, ScaleUtils } from "euler-price-oracle-1/src/lib/ScaleUtils.sol";

import { CurveEMAOracleUnderlying } from "src/oracles/CurveEMAOracleUnderlying.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract CurveEMAOracleUnderlyingTest is BaseTest {
    // --- Constants ---

    // tricrypto-ng pool (USDT/WBTC/WETH)
    address constant TRICRYPTO_POOL = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address constant TRICRYPTO_USDT = ETH_USDT; // coins[0] = quote
    address constant TRICRYPTO_WBTC = ETH_WBTC; // coins[1] = base1, priceOracleIndex = 0
    address constant TRICRYPTO_WETH = ETH_WETH; // coins[2] = base2, priceOracleIndex = 1

    // crvUSD/USDC pool
    address constant CRVUSD_USDC_POOL = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // coins[1] = base
    address constant USDC = ETH_USDC; // coins[0] = quote
    uint256 constant CRVUSD_USDC_PRICE_INDEX = type(uint256).max; // Use price_oracle()

    // --- State Variables ---

    // Tricrypto WETH/USDT Oracle
    CurveEMAOracleUnderlying public wethUsdtOracle;
    ICurvePool internal tricryptoPool = ICurvePool(TRICRYPTO_POOL);
    Scale internal wethUsdtScale;
    uint256 constant WETH_USDT_PRICE_INDEX = 1;

    // frxUSD/USDe Oracle
    CurveEMAOracleUnderlying public frxusdUsdeOracle;
    ICurvePool internal frxusdUsdePool = ICurvePool(ETH_CURVE_SFRXUSD_SUSDE_POOL);
    Scale internal frxUsdeScale;
    uint256 constant FRXUSD_USDE_PRICE_INDEX = 0;

    // CRVUSD/USDC Oracle
    CurveEMAOracleUnderlying public crvusdUsdcOracle;
    ICurvePool internal crvusdUsdcPool = ICurvePool(CRVUSD_USDC_POOL);
    Scale internal crvusdUsdcScale;

    // --- Setup ---

    function setUp() public override {
        super.setUp();
        vm.createSelectFork("mainnet", 22_190_097);

        // --- Deploy WETH/USDT Oracle ---
        wethUsdtOracle = new CurveEMAOracleUnderlying(
            TRICRYPTO_POOL, // _pool
            TRICRYPTO_WETH, // _base (WETH)
            TRICRYPTO_USDT, // _quote (USDT)
            WETH_USDT_PRICE_INDEX, // _priceOracleIndex (for WETH)
            false, // isBaseUnderlying
            false // isQuoteUnderlying
        );
        wethUsdtScale = ScaleUtils.calcScale(18, 6, 18); // WETH (18), USDT (6), output (18)
        vm.label(TRICRYPTO_POOL, "TRICRYPTO_POOL");
        vm.label(TRICRYPTO_WETH, "TRICRYPTO_WETH");
        vm.label(TRICRYPTO_USDT, "TRICRYPTO_USDT");
        vm.label(address(wethUsdtOracle), "WETH/USDT Oracle");

        // --- Deploy frxUSD/USDe Oracle ---
        frxusdUsdeOracle = new CurveEMAOracleUnderlying(
            ETH_CURVE_SFRXUSD_SUSDE_POOL, // _pool
            ETH_USDE, // _base (USDE)
            ETH_FRXUSD, // _quote (frxUSD)
            FRXUSD_USDE_PRICE_INDEX, // _priceOracleIndex (USDE index minus 1)
            true, // isBaseUnderlying (price_oracle returns w.r.t. USDE)
            true // isQuoteUnderlying (price_oracle returns w.r.t. frxUSD)
        );
        frxUsdeScale = ScaleUtils.calcScale(18, 18, 18); // USDE (18), frxUSD (18), output (18)
        vm.label(ETH_CURVE_SFRXUSD_SUSDE_POOL, "SFRXUSD_SUSDE_POOL");
        vm.label(ETH_USDE, "USDE");
        vm.label(ETH_FRXUSD, "FRXUSD");
        vm.label(address(frxusdUsdeOracle), "USDe/frxUSD Oracle");

        // --- Deploy CRVUSD/USDC Oracle ---
        crvusdUsdcOracle = new CurveEMAOracleUnderlying(
            CRVUSD_USDC_POOL, // _pool
            CRVUSD, // _base (crvUSD)
            USDC, // _quote (USDC)
            CRVUSD_USDC_PRICE_INDEX, // _priceOracleIndex (max)
            false, // isBaseUnderlying
            false // isQuoteUnderlying
        );
        crvusdUsdcScale = ScaleUtils.calcScale(18, 6, 18); // crvUSD (18), USDC (6), output (18)
        vm.label(CRVUSD_USDC_POOL, "CRVUSD_USDC_POOL");
        vm.label(CRVUSD, "CRVUSD");
        vm.label(USDC, "USDC");
        vm.label(address(crvusdUsdcOracle), "CRVUSD/USDC Oracle");
    }

    // --- Constructor Tests ---

    function test_constructor_passWhen_initialized() public {
        // WETH/USDT Oracle
        assertEq(wethUsdtOracle.pool(), TRICRYPTO_POOL);
        assertEq(wethUsdtOracle.base(), TRICRYPTO_WETH);
        assertEq(wethUsdtOracle.quote(), TRICRYPTO_USDT);
        assertEq(wethUsdtOracle.priceOracleIndex(), WETH_USDT_PRICE_INDEX);
        assertEq(wethUsdtOracle.name(), "CurveEMAOracle");

        // frxUSD/USDe Oracle
        assertEq(frxusdUsdeOracle.pool(), ETH_CURVE_SFRXUSD_SUSDE_POOL);
        assertEq(frxusdUsdeOracle.base(), ETH_USDE);
        assertEq(frxusdUsdeOracle.quote(), ETH_FRXUSD);
        assertEq(frxusdUsdeOracle.priceOracleIndex(), FRXUSD_USDE_PRICE_INDEX);
        assertEq(frxusdUsdeOracle.name(), "CurveEMAOracle");

        // CRVUSD/USDC Oracle
        assertEq(crvusdUsdcOracle.pool(), CRVUSD_USDC_POOL);
        assertEq(crvusdUsdcOracle.base(), CRVUSD);
        assertEq(crvusdUsdcOracle.quote(), USDC);
        assertEq(crvusdUsdcOracle.priceOracleIndex(), CRVUSD_USDC_PRICE_INDEX);
        assertEq(crvusdUsdcOracle.name(), "CurveEMAOracle");
    }

    function test_constructor_revertWhen_baseAssetMismatch_noUnderlying() public {
        // Provide WBTC address instead of WETH
        vm.expectRevert(CurveEMAOracleUnderlying.BaseAssetMismatch.selector);
        new CurveEMAOracleUnderlying(
            TRICRYPTO_POOL, TRICRYPTO_WBTC, TRICRYPTO_USDT, WETH_USDT_PRICE_INDEX, false, false
        );
    }

    function test_constructor_revertWhen_quoteAssetMismatch_noUnderlying() public {
        // Provide WETH address instead of USDT
        vm.expectRevert(CurveEMAOracleUnderlying.QuoteAssetMismatch.selector);
        new CurveEMAOracleUnderlying(
            TRICRYPTO_POOL, TRICRYPTO_WETH, TRICRYPTO_WETH, WETH_USDT_PRICE_INDEX, false, false
        );
    }

    function test_constructor_revertWhen_baseAssetMismatch_withUnderlying() public {
        // Provide sfrxUSD (the wrapper) instead of frxUSD (the underlying) when isBaseUnderlying is true
        vm.expectRevert(CurveEMAOracleUnderlying.BaseAssetMismatch.selector);
        new CurveEMAOracleUnderlying(
            ETH_CURVE_SFRXUSD_SUSDE_POOL, ETH_SFRXUSD, ETH_USDE, FRXUSD_USDE_PRICE_INDEX, true, true
        );

        // Provide a random token instead of frxUSD
        address randomToken = address(0xdead);
        vm.expectRevert(CurveEMAOracleUnderlying.BaseAssetMismatch.selector);
        new CurveEMAOracleUnderlying(
            ETH_CURVE_SFRXUSD_SUSDE_POOL, randomToken, ETH_USDE, FRXUSD_USDE_PRICE_INDEX, true, true
        );
    }

    function test_constructor_revertWhen_quoteAssetMismatch_withUnderlying() public {
        // Test with sfrxUSD/sUSDe pool where quote coin (sfrxUSD) is a vault
        // coins[0] = sfrxUSD (vault, quote)
        // coins[1] = sUSDE (base)
        // Oracle Index for sUSDE = 0
        // We want to price sUSDE (base) in frxUSD (quote underlying)

        address poolAddress = ETH_CURVE_SFRXUSD_SUSDE_POOL;
        address baseVault = ETH_SUSDE;
        address baseUnderlying = ETH_USDE;
        address quoteUnderlying = ETH_FRXUSD;
        address quoteVault = ETH_SFRXUSD;
        uint256 priceIndex = 0; // Index for sUSDE

        // --- Check Pool Setup Correctly ---
        // Verify sfrxUSD is indeed coins[0] and sUSDE is coins[1]
        // If this fails, the constant definitions or pool understanding is wrong.
        assertEq(ICurvePool(poolAddress).coins(0), quoteVault, "Pool coins[0] is not sfrxUSD");
        assertEq(ICurvePool(poolAddress).coins(1), baseVault, "Pool coins[1] is not sUSDE");
        assertEq(IERC4626(quoteVault).asset(), quoteUnderlying, "sfrxUSD underlying is not frxUSD");

        // --- Test Pass Case ---
        // Provide the correct underlying (frxUSD) as the quote asset when isQuoteUnderlying=true
        new CurveEMAOracleUnderlying(
            poolAddress,
            baseUnderlying, // base = USDE
            quoteUnderlying, // quote = frxUSD (underlying of coins[0])
            priceIndex, // price index for sUSDE
            true, // isBaseUnderlying = true (the price oracle returns the USDE)
            true // isQuoteUnderlying = true (the price oracle returns the frxUSD)
        );

        // --- Test Fail Case ---
        // Provide the vault token (sfrxUSD) itself as the quote asset when isQuoteUnderlying=true
        vm.expectRevert(CurveEMAOracleUnderlying.QuoteAssetMismatch.selector);
        new CurveEMAOracleUnderlying(
            poolAddress,
            baseUnderlying, // base = USDE
            quoteVault, // INCORRECT: quote = sfrxUSD (vault token, not underlying)
            priceIndex, // price index for sUSDE
            true, // isBaseUnderlying = true (the price oracle returns the USDE)
            true // isQuoteUnderlying = true (the price oracle returns the frxUSD)
        );
    }

    function test_constructor_passWhen_maxIndex_noUnderlying() public {
        // Test constructor works with max index when no underlying involved
        new CurveEMAOracleUnderlying(CRVUSD_USDC_POOL, CRVUSD, USDC, CRVUSD_USDC_PRICE_INDEX, false, false);
    }

    function test_constructor_revertWhen_baseAssetMismatch_maxIndex_noUnderlying() public {
        // Provide USDC instead of CRVUSD for base with max index
        vm.expectRevert(CurveEMAOracleUnderlying.BaseAssetMismatch.selector);
        new CurveEMAOracleUnderlying(CRVUSD_USDC_POOL, USDC, USDC, CRVUSD_USDC_PRICE_INDEX, false, false);
    }

    function test_constructor_revertWhen_quoteAssetMismatch_maxIndex_noUnderlying() public {
        // Provide CRVUSD instead of USDC for quote with max index
        vm.expectRevert(CurveEMAOracleUnderlying.QuoteAssetMismatch.selector);
        new CurveEMAOracleUnderlying(CRVUSD_USDC_POOL, CRVUSD, CRVUSD, CRVUSD_USDC_PRICE_INDEX, false, false);
    }

    function test_constructor_revertWhen_zeroAddresses() public {
        // Test with pool address = 0
        vm.expectRevert(PriceOracleErrors.PriceOracle_InvalidConfiguration.selector);
        new CurveEMAOracleUnderlying(
            address(0), // Zero pool address
            TRICRYPTO_WETH,
            TRICRYPTO_USDT,
            WETH_USDT_PRICE_INDEX,
            false,
            false
        );

        // Test with base address = 0
        vm.expectRevert(PriceOracleErrors.PriceOracle_InvalidConfiguration.selector);
        new CurveEMAOracleUnderlying(
            TRICRYPTO_POOL,
            address(0), // Zero base address
            TRICRYPTO_USDT,
            WETH_USDT_PRICE_INDEX,
            false,
            false
        );

        // Test with quote address = 0
        vm.expectRevert(PriceOracleErrors.PriceOracle_InvalidConfiguration.selector);
        new CurveEMAOracleUnderlying(
            TRICRYPTO_POOL,
            TRICRYPTO_WETH,
            address(0), // Zero quote address
            WETH_USDT_PRICE_INDEX,
            false,
            false
        );
    }

    // --- getQuote Tests (WETH/USDT) ---

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_wethUsdt(uint96 amount96) public {
        uint256 inAmount = uint256(amount96); // Use uint96 to limit input size reasonably
        vm.assume(inAmount > 0);

        // price_oracle gives price of WETH (coins[2]) in USDT (coins[0])
        uint256 unitPrice = tricryptoPool.price_oracle(WETH_USDT_PRICE_INDEX);
        uint256 expectedOut = ScaleUtils.calcOutAmount(inAmount, unitPrice, wethUsdtScale, false); // false = not
            // inverse
        uint256 actualOut = wethUsdtOracle.getQuote(inAmount, TRICRYPTO_WETH, TRICRYPTO_USDT);

        assertEq(actualOut, expectedOut);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_wethUsdt(uint96 amount96) public {
        uint256 inAmount = uint256(amount96); // Use uint96 to limit input size reasonably
        vm.assume(inAmount > 0);

        // price_oracle gives price of USDT (coins[0]) in WETH (coins[2])
        uint256 unitPrice = tricryptoPool.price_oracle(WETH_USDT_PRICE_INDEX);
        uint256 expectedOut = ScaleUtils.calcOutAmount(inAmount, unitPrice, wethUsdtScale, true); // true = inverse
        uint256 actualOut = wethUsdtOracle.getQuote(inAmount, TRICRYPTO_USDT, TRICRYPTO_WETH);

        assertEq(actualOut, expectedOut);
    }

    // --- getQuote Tests (frxUSD/USDe) ---

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_frxusdUsde(uint96 amount96) public {
        uint256 inAmount = uint256(amount96); // Use uint96 to limit input size reasonably
        vm.assume(inAmount > 0);

        // price_oracle gives price of USDE (coins[1]) in frxUSD (coins[0])
        uint256 usdePerFrxusd_unitPrice = frxusdUsdePool.price_oracle(FRXUSD_USDE_PRICE_INDEX);
        uint256 expectedOut = ScaleUtils.calcOutAmount(inAmount, usdePerFrxusd_unitPrice, frxUsdeScale, false); // false
            // = not inverse
        uint256 actualOut = frxusdUsdeOracle.getQuote(inAmount, ETH_USDE, ETH_FRXUSD);

        assertEq(actualOut, expectedOut);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_frxusdUsde(uint96 amount96) public {
        uint256 inAmount = uint256(amount96); // Use uint96 to limit input size reasonably
        vm.assume(inAmount > 0);

        // price_oracle gives price of USDE (coins[1]) in frxUSD (coins[0])
        uint256 usdePerFrxusd_unitPrice = frxusdUsdePool.price_oracle(FRXUSD_USDE_PRICE_INDEX);
        uint256 expectedOut = ScaleUtils.calcOutAmount(inAmount, usdePerFrxusd_unitPrice, frxUsdeScale, true); // true =
            // inverse
        uint256 actualOut = frxusdUsdeOracle.getQuote(inAmount, ETH_FRXUSD, ETH_USDE);

        // Allow some tolerance due to division in unit price calculation
        assertEq(actualOut, expectedOut);
    }

    // --- getQuote Tests (CRVUSD/USDC) ---

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_crvusdUsdc(uint96 amount96) public {
        uint256 inAmount = uint256(amount96); // Use uint96 to limit input size reasonably
        vm.assume(inAmount > 0);

        // price_oracle() gives price of CRVUSD (coins[1]) in USDC (coins[0])
        uint256 unitPrice = crvusdUsdcPool.price_oracle();
        uint256 expectedOut = ScaleUtils.calcOutAmount(inAmount, unitPrice, crvusdUsdcScale, false); // false = not
            // inverse
        uint256 actualOut = crvusdUsdcOracle.getQuote(inAmount, CRVUSD, USDC);

        // Allow some tolerance due to EMA and potential slight depeg
        assertApproxEqAbs(actualOut, expectedOut, 1e4); // Tolerance for USDC (6 decimals)
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_crvusdUsdc(uint96 amount96) public {
        uint256 inAmount = uint256(amount96); // Use uint96 to limit input size reasonably
        vm.assume(inAmount > 0);

        // price_oracle() gives price of CRVUSD (coins[1]) in USDC (coins[0])
        uint256 unitPrice = crvusdUsdcPool.price_oracle();
        uint256 expectedOut = ScaleUtils.calcOutAmount(inAmount, unitPrice, crvusdUsdcScale, true); // true = inverse
        uint256 actualOut = crvusdUsdcOracle.getQuote(inAmount, USDC, CRVUSD);

        // Allow some tolerance due to division in unit price calculation and EMA
        assertApproxEqAbs(actualOut, expectedOut, 1e16); // Tolerance for CRVUSD (18 decimals)
    }

    // --- General getQuote Tests ---

    function test_getQuote_passWhen_zeroAmount(address base, address quote) public {
        // Test WETH/USDT oracle
        if ((base == TRICRYPTO_WETH && quote == TRICRYPTO_USDT) || (base == TRICRYPTO_USDT && quote == TRICRYPTO_WETH))
        {
            assertEq(wethUsdtOracle.getQuote(0, base, quote), 0);
        }

        // Test stETH/WETH oracle
        if ((base == ETH_USDE && quote == ETH_FRXUSD) || (base == ETH_FRXUSD && quote == ETH_USDE)) {
            assertEq(frxusdUsdeOracle.getQuote(0, base, quote), 0);
        }

        // Test CRVUSD/USDC oracle
        if ((base == CRVUSD && quote == USDC) || (base == USDC && quote == CRVUSD)) {
            assertEq(crvusdUsdcOracle.getQuote(0, base, quote), 0);
        }
    }

    function testFuzz_getQuote_revertWhen_invalidBaseOrQuote(uint96 amount96, address invalidAddress) public {
        uint256 amount = uint256(amount96);
        // Ensure invalidAddress is not one of the valid tokens for either oracle
        vm.assume(invalidAddress != address(0));
        vm.assume(invalidAddress != TRICRYPTO_WETH);
        vm.assume(invalidAddress != TRICRYPTO_USDT);
        vm.assume(invalidAddress != ETH_USDE);
        vm.assume(invalidAddress != ETH_FRXUSD);
        vm.assume(invalidAddress != CRVUSD);
        vm.assume(invalidAddress != USDC);

        // Test WETH/USDT Oracle
        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, invalidAddress, TRICRYPTO_USDT)
        );
        wethUsdtOracle.getQuote(amount, invalidAddress, TRICRYPTO_USDT);

        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, TRICRYPTO_WETH, invalidAddress)
        );
        wethUsdtOracle.getQuote(amount, TRICRYPTO_WETH, invalidAddress);

        // Test stETH/WETH Oracle
        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, invalidAddress, ETH_FRXUSD)
        );
        frxusdUsdeOracle.getQuote(amount, invalidAddress, ETH_FRXUSD);

        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, ETH_USDE, invalidAddress)
        );
        frxusdUsdeOracle.getQuote(amount, ETH_USDE, invalidAddress);

        // Test CRVUSD/USDC Oracle
        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, invalidAddress, USDC)
        );
        crvusdUsdcOracle.getQuote(amount, invalidAddress, USDC);

        vm.expectRevert(
            abi.encodeWithSelector(PriceOracleErrors.PriceOracle_NotSupported.selector, CRVUSD, invalidAddress)
        );
        crvusdUsdcOracle.getQuote(amount, CRVUSD, invalidAddress);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";

import { OraclePriceChecker } from "src/compounder/pricecheckers/OraclePriceChecker.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { IAutopoolMainRewarder } from "src/interfaces/deps/tokemak/IAutopoolMainRewarder.sol";

import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

// Price oracle imports

import { CrossAdapter } from "dependencies/euler-price-oracle-1/src/adapter/CrossAdapter.sol";

import { ChainlinkOracle } from "dependencies/euler-price-oracle-1/src/adapter/chainlink/ChainlinkOracle.sol";
import { CurveEMAOracle } from "dependencies/euler-price-oracle-1/src/adapter/curve/CurveEMAOracle.sol";
import { IPriceOracle } from "dependencies/euler-price-oracle-1/src/interfaces/IPriceOracle.sol";

contract AutopoolCompounderForkedTest is BaseTest {
    AutopoolCompounder public strategy;
    IAutopool public autoUSD;
    IAutopoolMainRewarder public rewarder;
    IERC20 public usdc;
    IERC20 public toke;

    // Price oracles
    CurveEMAOracle public curveOracle; // TOKE/ETH
    ChainlinkOracle public chainlinkOracle; // ETH/USDC
    CrossAdapter public crossAdapter; // TOKE -> ETH -> USDC
    OraclePriceChecker public priceChecker;

    address public management;
    address public keeper;
    address public user;

    // Oracle configuration
    address constant CURVE_TOKE_ETH_POOL = 0xe0e970a99bc4F53804D8145beBBc7eBc9422Ba7F;
    address constant CHAINLINK_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Recent mainnet block (after autoUSD deployment)
    uint256 constant FORK_BLOCK = 23_250_000;

    function setUp() public override {
        super.setUp();

        // Fork mainnet at a recent block
        forkNetworkAt("mainnet", FORK_BLOCK);

        // Set up contracts
        autoUSD = IAutopool(TOKEMAK_AUTOUSD);
        rewarder = IAutopoolMainRewarder(TOKEMAK_AUTOUSD_REWARDER);
        usdc = IERC20(ETH_USDC);
        toke = IERC20(TOKEMAK_TOKE);

        // Create users
        management = createUser("management");
        keeper = createUser("keeper");
        user = createUser("user");

        // Deploy strategy
        vm.prank(management);
        strategy = new AutopoolCompounder(address(autoUSD), address(rewarder), TOKEMAK_MILKMAN);

        // Set up keeper role
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setKeeper(keeper);

        // Deploy price oracles
        _deployPriceOracles();

        // Configure price checker for TOKE
        vm.prank(management);
        strategy.updatePriceChecker(address(toke), address(priceChecker));

        // Give user some USDC using deal (forge cheatcode to set balance)
        deal(address(usdc), user, 10_000e6); // 10,000 USDC
    }

    function test_deployment() public view {
        assertEq(ITokenizedStrategy(address(strategy)).asset(), address(autoUSD));
        assertEq(address(strategy.rewarder()), address(rewarder));
        assertEq(address(strategy.milkman()), TOKEMAK_MILKMAN);
        assertEq(address(strategy.baseAsset()), address(usdc));
    }

    function test_depositFlow() public {
        // User deposits USDC into autoUSD first
        vm.startPrank(user);

        uint256 usdcAmount = 1000e6; // 1000 USDC
        usdc.approve(address(autoUSD), usdcAmount);
        uint256 autoUSDShares = autoUSD.deposit(usdcAmount, user);

        assertGt(autoUSDShares, 0, "Should receive autoUSD shares");
        assertEq(autoUSD.balanceOf(user), autoUSDShares, "User should have autoUSD shares");

        // Now deposit autoUSD into strategy
        autoUSD.approve(address(strategy), autoUSDShares);
        uint256 strategyShares = ITokenizedStrategy(address(strategy)).deposit(autoUSDShares, user);

        vm.stopPrank();

        // Verify staking
        assertGt(strategyShares, 0, "Should receive strategy shares");
        assertEq(rewarder.balanceOf(address(strategy)), autoUSDShares, "Strategy should stake in rewarder");
        assertEq(strategy.stakedBalance(), autoUSDShares, "Staked balance should match");
    }

    function test_withdrawFlow() public {
        // Setup: deposit first
        vm.startPrank(user);
        uint256 usdcAmount = 1000e6;
        usdc.approve(address(autoUSD), usdcAmount);
        uint256 autoUSDShares = autoUSD.deposit(usdcAmount, user);
        autoUSD.approve(address(strategy), autoUSDShares);
        uint256 strategyShares = ITokenizedStrategy(address(strategy)).deposit(autoUSDShares, user);
        vm.stopPrank();

        // Withdraw
        vm.prank(user);
        uint256 withdrawn = ITokenizedStrategy(address(strategy)).redeem(strategyShares, user, user);

        assertEq(withdrawn, autoUSDShares, "Should withdraw all autoUSD shares");
        assertEq(autoUSD.balanceOf(user), autoUSDShares, "User should receive autoUSD back");
        assertEq(rewarder.balanceOf(address(strategy)), 0, "Strategy should unstake from rewarder");
    }

    function test_rewardsClaiming() public {
        // Setup: deposit first
        vm.startPrank(user);
        uint256 usdcAmount = 10_000e6; // Larger deposit for meaningful rewards
        usdc.approve(address(autoUSD), usdcAmount);
        uint256 autoUSDShares = autoUSD.deposit(usdcAmount, user);
        autoUSD.approve(address(strategy), autoUSDShares);
        ITokenizedStrategy(address(strategy)).deposit(autoUSDShares, user);
        vm.stopPrank();

        // Fast forward to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + (30 days / 12));

        // Check pending rewards
        uint256 pendingRewards = rewarder.earned(address(strategy));
        console.log("Pending TOKE rewards:", pendingRewards);
        assertEq(pendingRewards, 12_241_122_258_004_639_028, "Should have pending rewards");

        // Note: Actual reward claiming would require setting up price checkers
        // and would interact with real Milkman contract for swaps
        if (pendingRewards > 0) {
            // Would need to set up OraclePriceChecker with real price feeds
            // vm.prank(management);
            // strategy.updatePriceChecker(address(toke), address(priceChecker));

            // vm.prank(keeper);
            // strategy.claimRewardsAndSwap();
        }
    }

    function test_realAutopoolFunctions() public view {
        // Test that real autoUSD contract has expected functions
        assertEq(autoUSD.asset(), address(usdc), "Asset should be USDC");
        assertEq(autoUSD.symbol(), "autoUSD", "Symbol should be autoUSD");
        assertEq(autoUSD.name(), "Tokemak autoUSD", "Name should match");
        assertFalse(autoUSD.isShutdown(), "Vault should not be shutdown");

        // Check rewarder configuration
        assertEq(rewarder.stakingToken(), address(autoUSD), "Staking token should be autoUSD");
        assertEq(rewarder.rewardToken(), address(toke), "Reward token should be TOKE");
    }

    function test_priceOracleSetup() public view {
        // Test TOKE -> ETH price from Curve
        uint256 oneToken = 1e18;
        uint256 ethFromToke = curveOracle.getQuote(oneToken, address(toke), WETH);
        console.log("1 TOKE = ETH:", ethFromToke);
        assertGt(ethFromToke, 0, "Should get ETH price for TOKE");

        // Test ETH -> USDC price from Chainlink
        uint256 usdcFromEth = chainlinkOracle.getQuote(1e18, WETH, address(usdc));
        console.log("1 ETH = USDC:", usdcFromEth);
        assertGt(usdcFromEth, 0, "Should get USDC price for ETH");

        // Test TOKE -> USDC through CrossAdapter
        uint256 usdcFromToke = crossAdapter.getQuote(oneToken, address(toke), address(usdc));
        console.log("1 TOKE = USDC:", usdcFromToke);
        assertGt(usdcFromToke, 0, "Should get USDC price for TOKE through cross");

        // Test price checker integration
        bool priceOk = priceChecker.checkPrice(
            oneToken,
            address(toke),
            address(usdc),
            0, // feeAmount (0 for this test)
            usdcFromToke * 95 / 100, // 5% slippage tolerance
            ""
        );
        assertTrue(priceOk, "Price should be within tolerance");
    }

    function test_claimAndSwapWithRealOracle() public {
        // Setup: deposit first
        vm.startPrank(user);
        uint256 usdcAmount = 10_000e6;
        usdc.approve(address(autoUSD), usdcAmount);
        uint256 autoUSDShares = autoUSD.deposit(usdcAmount, user);
        autoUSD.approve(address(strategy), autoUSDShares);
        ITokenizedStrategy(address(strategy)).deposit(autoUSDShares, user);
        vm.stopPrank();

        // Simulate time passing to accrue staking rewards
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + (7 days / 12));
        _updateChainLinkOracleTimeStamp(CHAINLINK_ETH_USD_FEED);

        // Get expected output from oracle
        uint256 expectedUsdc = crossAdapter.getQuote(100e18, address(toke), address(usdc));
        console.log("Expected USDC from 100 TOKE:", expectedUsdc);

        // Check pending rewards
        uint256 pendingRewards = rewarder.earned(address(strategy));
        console.log("Pending rewards:", pendingRewards);

        // Claim rewards and initiate swap through Milkman
        vm.prank(keeper);
        strategy.claimRewardsAndSwap();

        // Note: In a real scenario, Milkman would execute the swap asynchronously
        // and we'd need to wait for the swap to settle before harvesting
    }

    /// HELPER FUNCTIONS ///

    function _deployPriceOracles() internal {
        // Deploy CurveEMAOracle for TOKE/ETH
        // The Curve pool has WETH as coins[0] and TOKE as coins[1]
        // CurveEMAOracle constructor: (pool, base, priceOracleIndex)
        // Use type(uint256).max to call non-indexed price_oracle()
        // This gives us TOKE priced in ETH which is what we want
        curveOracle = new CurveEMAOracle(
            CURVE_TOKE_ETH_POOL,
            address(toke), // base (TOKE is coins[1])
            type(uint256).max // Use non-indexed price_oracle()
        );

        // Deploy ChainlinkOracle for ETH/USDC
        // ChainlinkOracle constructor: (base, quote, feed, maxStaleness)
        chainlinkOracle = new ChainlinkOracle(
            WETH,
            address(usdc),
            CHAINLINK_ETH_USD_FEED,
            3600 // 1 hour max staleness
        );

        // Deploy CrossAdapter to chain TOKE -> ETH -> USDC
        // CrossAdapter constructor: (base, cross, quote, oracleBaseCross, oracleCrossQuote)
        crossAdapter = new CrossAdapter(
            address(toke), // base (TOKE)
            WETH, // cross (ETH)
            address(usdc), // quote (USDC)
            address(curveOracle), // oracle for TOKE/ETH
            address(chainlinkOracle) // oracle for ETH/USDC
        );

        // Deploy OraclePriceChecker wrapper for Milkman
        priceChecker = new OraclePriceChecker(
            IPriceOracle(address(crossAdapter)),
            500 // 5% max deviation
        );
    }
}

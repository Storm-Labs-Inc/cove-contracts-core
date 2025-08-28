// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";
import { MockAutopool } from "test/mocks/MockAutopool.sol";
import { MockAutopoolMainRewarder } from "test/mocks/MockAutopoolMainRewarder.sol";
import { MockMilkman } from "test/mocks/MockMilkman.sol";
import { MockPriceOracle } from "test/mocks/MockPriceOracle.sol";
import { OraclePriceChecker } from "src/compounder/pricecheckers/OraclePriceChecker.sol";
import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AutopoolCompounderTest is BaseTest {
    AutopoolCompounder public strategy;
    MockAutopool public autopool;
    MockAutopoolMainRewarder public rewarder;
    MockMilkman public milkman;
    MockPriceOracle public priceOracle;
    OraclePriceChecker public priceChecker;
    
    MockERC20 public baseAsset; // e.g., USDC
    MockERC20 public rewardToken; // e.g., TOKE
    
    address public alice;
    address public bob;
    address public management;
    address public keeper;
    
    function setUp() public override {
        super.setUp();
        
        // Create users
        alice = createUser("alice");
        bob = createUser("bob");
        management = createUser("management");
        keeper = createUser("keeper");
        
        // Deploy mock tokens
        baseAsset = new MockERC20("USDC", "USDC");
        rewardToken = new MockERC20("TOKE", "TOKE");
        
        // Deploy mock autopool
        autopool = new MockAutopool(address(baseAsset), "autoUSD", "autoUSD");
        
        // Deploy mock rewarder
        rewarder = new MockAutopoolMainRewarder(address(autopool), address(rewardToken));
        
        // Deploy mock Milkman and price oracle/checker
        milkman = new MockMilkman();
        priceOracle = new MockPriceOracle();
        priceChecker = new OraclePriceChecker(priceOracle, 500); // 5% max deviation
        
        // Deploy strategy
        vm.prank(management);
        strategy = new AutopoolCompounder(
            address(autopool),
            address(rewarder),
            address(milkman)
        );
        
        // Set up keeper role
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setKeeper(keeper);
        
        // Fund users with base asset
        baseAsset.mint(alice, 10000e6); // 10,000 USDC
        baseAsset.mint(bob, 10000e6);
        
        // Fund rewarder with reward tokens
        rewardToken.mint(address(rewarder), 1000000e18);
    }
    
    /// DEPLOYMENT TESTS ///
    
    function test_Deployment() public {
        assertEq(address(strategy.autopool()), address(autopool));
        assertEq(address(strategy.rewarder()), address(rewarder));
        assertEq(address(strategy.milkman()), address(milkman));
        assertEq(address(strategy.baseAsset()), address(baseAsset));
        assertEq(strategy.maxPriceDeviationBps(), 500);
    }
    
    function test_DeploymentRevertsOnZeroAddress() public {
        vm.expectRevert(AutopoolCompounder.ZeroAddress.selector);
        new AutopoolCompounder(address(0), address(rewarder), address(milkman));
        
        vm.expectRevert(AutopoolCompounder.ZeroAddress.selector);
        new AutopoolCompounder(address(autopool), address(0), address(milkman));
        
        vm.expectRevert(AutopoolCompounder.ZeroAddress.selector);
        new AutopoolCompounder(address(autopool), address(rewarder), address(0));
    }
    
    /// DEPOSIT AND STAKE TESTS ///
    
    function test_DepositAndStake() public {
        uint256 depositAmount = 1000e6; // 1000 USDC
        
        // Alice deposits base asset to autopool first
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        
        // Now deposit autopool shares to strategy
        autopool.approve(address(strategy), shares);
        uint256 strategyShares = ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Check that funds are staked
        assertEq(rewarder.balanceOf(address(strategy)), shares);
        assertEq(strategy.stakedBalance(), shares);
        assertEq(ITokenizedStrategy(address(strategy)).totalAssets(), shares);
    }
    
    /// PRICE CHECKER MANAGEMENT TESTS ///
    
    function test_UpdatePriceChecker() public {
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        assertEq(strategy.priceCheckerByToken(address(rewardToken)), address(priceChecker));
        
        address[] memory configuredTokens = strategy.getConfiguredRewardTokens();
        assertEq(configuredTokens.length, 1);
        assertEq(configuredTokens[0], address(rewardToken));
    }
    
    function test_UpdatePriceCheckerRevertsForAsset() public {
        vm.prank(management);
        vm.expectRevert(AutopoolCompounder.CannotSetCheckerForAsset.selector);
        strategy.updatePriceChecker(address(autopool), address(priceChecker));
    }
    
    function test_RemovePriceChecker() public {
        // First add
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        // Then remove
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(0));
        
        assertEq(strategy.priceCheckerByToken(address(rewardToken)), address(0));
        
        address[] memory configuredTokens = strategy.getConfiguredRewardTokens();
        assertEq(configuredTokens.length, 0);
    }
    
    /// HARVEST AND COMPOUND TESTS ///
    
    function test_ClaimRewardsAndSwap() public {
        // Setup: deposit and stake
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Set up oracle exchange rate (1 TOKE = 0.001 USDC for testing)
        priceOracle.setExchangeRate(address(rewardToken), address(baseAsset), 1e15); // 0.001 * 1e18
        
        // Configure price checker
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        // Set up rewards
        rewarder.setEarned(address(strategy), 100e18);
        
        // Claim rewards and swap
        vm.prank(keeper);
        strategy.claimRewardsAndSwap();
        
        // Check that swap was requested
        // Note: In real implementation, we'd check Milkman events
    }
    
    function test_HarvestAndReport() public {
        // Setup: deposit and stake
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Set up oracle exchange rate
        priceOracle.setExchangeRate(address(rewardToken), address(baseAsset), 1e15);
        
        // Configure price checker
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        // Set up rewards
        rewarder.setEarned(address(strategy), 100e18);
        
        // Put some base asset in strategy (simulating settled swap)
        baseAsset.mint(address(strategy), 50e6);
        
        // Report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();
        
        // Should have compounded the base asset (profit should be positive)
        assertTrue(profit > 0);
        assertEq(loss, 0);
    }
    
    /// WITHDRAWAL TESTS ///
    
    function test_Withdrawal() public {
        // Setup: deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        uint256 strategyShares = ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        // Withdraw
        vm.prank(alice);
        uint256 withdrawn = ITokenizedStrategy(address(strategy)).redeem(strategyShares, alice, alice);
        
        assertEq(withdrawn, shares);
        assertEq(autopool.balanceOf(alice), shares);
        assertEq(ITokenizedStrategy(address(strategy)).balanceOf(alice), 0);
    }
    
    /// ACCESS CONTROL TESTS ///
    
    function test_OnlyManagementCanUpdatePriceChecker() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
    }
    
    function test_OnlyKeepersCanClaimRewards() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.claimRewardsAndSwap();
        
        vm.prank(keeper);
        strategy.claimRewardsAndSwap();
        
        vm.prank(management);
        strategy.claimRewardsAndSwap(); // Management can also call keeper functions
    }
    
    /// PARAMETER SETTING TESTS ///
    
    // Removed test_SetMinRewardToSell and test_SetMinBaseAssetToCompound - functions no longer exist
    
    function test_SetMaxPriceDeviation() public {
        vm.prank(management);
        strategy.setMaxPriceDeviation(1000); // 10%
        
        assertEq(strategy.maxPriceDeviationBps(), 1000);
    }
    
    function test_SetMaxPriceDeviationReverts() public {
        vm.prank(management);
        vm.expectRevert(AutopoolCompounder.InvalidMaxDeviation.selector);
        strategy.setMaxPriceDeviation(10001); // > 100%
    }
    
    /// HARVEST TRIGGER TESTS ///
    
    // Removed harvest trigger tests - harvestTrigger function no longer exists
    
    /// VIEW FUNCTION TESTS ///
    
    function test_GetConfiguredRewardTokens() public {
        vm.startPrank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        MockERC20 extraReward = new MockERC20("EXTRA", "EXTRA");
        // Create a separate price checker for the extra reward token
        MockPriceOracle extraOracle = new MockPriceOracle();
        OraclePriceChecker extraChecker = new OraclePriceChecker(extraOracle, 500);
        strategy.updatePriceChecker(address(extraReward), address(extraChecker));
        vm.stopPrank();
        
        address[] memory tokens = strategy.getConfiguredRewardTokens();
        assertEq(tokens.length, 2);
        assertTrue(tokens[0] == address(rewardToken) || tokens[1] == address(rewardToken));
        assertTrue(tokens[0] == address(extraReward) || tokens[1] == address(extraReward));
    }
    
    function test_StakedBalance() public {
        // Deposit and check staked balance
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        assertEq(strategy.stakedBalance(), shares);
        assertEq(strategy.stakedBalance(), rewarder.balanceOf(address(strategy)));
    }
    
    function test_PendingRewards() public {
        rewarder.setEarned(address(strategy), 123e18);
        assertEq(strategy.pendingRewards(), 123e18);
    }
}
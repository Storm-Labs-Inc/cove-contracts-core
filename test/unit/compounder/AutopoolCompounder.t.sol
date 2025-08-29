// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";
import { IPriceOracle } from "euler-price-oracle-1/src/interfaces/IPriceOracle.sol";
import { MockAutopool } from "test/utils/mocks/MockAutopool.sol";
import { MockAutopoolMainRewarder } from "test/utils/mocks/MockAutopoolMainRewarder.sol";
import { MockMilkman } from "test/utils/mocks/MockMilkman.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";
import { OraclePriceChecker } from "src/compounder/pricecheckers/OraclePriceChecker.sol";
import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";
import { TokenizedStrategy } from "tokenized-strategy-3.0.4/src/TokenizedStrategy.sol";
import { IFactory } from "tokenized-strategy-3.0.4/src/interfaces/IFactory.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Minimal mock factory for TokenizedStrategy
contract MockFactory is IFactory {
    uint16 public protocolFee;
    address public protocolFeeRecipient;
    
    constructor(uint16 _protocolFee, address _protocolFeeRecipient) {
        protocolFee = _protocolFee;
        protocolFeeRecipient = _protocolFeeRecipient;
    }
    
    function apiVersion() external pure returns (string memory) {
        return "3.0.4";
    }
    
    function protocol_fee_config() external view returns (uint16, address) {
        return (protocolFee, protocolFeeRecipient);
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
    
    // TokenizedStrategy address that strategies expect
    address constant TOKENIZED_STRATEGY = 0xD377919FA87120584B21279a491F82D5265A139c;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy and etch TokenizedStrategy at the expected address
        _deployTokenizedStrategy();
        
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
        baseAsset.mint(alice, 10000000e6); // 10 million USDC for fuzz tests
        baseAsset.mint(bob, 10000000e6);
        
        // Fund rewarder with reward tokens
        rewardToken.mint(address(rewarder), 1000000e18);
    }
    
    /// DEPLOYMENT TESTS ///
    
    function test_deployment() public {
        assertEq(address(strategy.autopool()), address(autopool));
        assertEq(address(strategy.rewarder()), address(rewarder));
        assertEq(address(strategy.milkman()), address(milkman));
        assertEq(address(strategy.baseAsset()), address(baseAsset));
        assertEq(strategy.maxPriceDeviationBps(), 500);
    }
    
    function test_deployment_revertsWhen_zeroAddress() public {
        // When autopool is zero, TokenizedStrategy.initialize reverts trying to call decimals()
        vm.expectRevert();
        new AutopoolCompounder(address(0), address(rewarder), address(milkman));
        
        vm.expectRevert(AutopoolCompounder.ZeroAddress.selector);
        new AutopoolCompounder(address(autopool), address(0), address(milkman));
        
        vm.expectRevert(AutopoolCompounder.ZeroAddress.selector);
        new AutopoolCompounder(address(autopool), address(rewarder), address(0));
    }
    
    /// DEPOSIT AND STAKE TESTS ///
    
    function testFuzz_depositAndStake(uint256 depositAmount) public {
        // Bound the deposit amount to reasonable values (1 USDC to 10k USDC)
        depositAmount = bound(depositAmount, 1e6, 10000e6);
        
        // Alice deposits base asset to autopool first
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        
        // Now deposit autopool shares to strategy
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Check that funds are staked
        assertEq(rewarder.balanceOf(address(strategy)), shares);
        assertEq(strategy.stakedBalance(), shares);
        assertEq(ITokenizedStrategy(address(strategy)).totalAssets(), shares);
    }
    
    /// PRICE CHECKER MANAGEMENT TESTS ///
    
    function test_updatePriceChecker() public {
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        assertEq(strategy.priceCheckerByToken(address(rewardToken)), address(priceChecker));
        
        address[] memory configuredTokens = strategy.getConfiguredRewardTokens();
        assertEq(configuredTokens.length, 1);
        assertEq(configuredTokens[0], address(rewardToken));
    }
    
    function test_updatePriceChecker_revertsWhen_settingForAsset() public {
        vm.prank(management);
        vm.expectRevert(AutopoolCompounder.CannotSetCheckerForAsset.selector);
        strategy.updatePriceChecker(address(autopool), address(priceChecker));
    }
    
    function test_removePriceChecker() public {
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
    
    function test_claimRewardsAndSwap() public {
        // Setup: deposit and stake
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Set up oracle exchange rate (1 TOKE = 0.001 USDC for testing)
        priceOracle.setPrice(address(rewardToken), address(baseAsset), 1e15); // 0.001 * 1e18
        
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
    
    function test_harvestAndReport() public {
        // Setup: deposit and stake
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();
        
        // Set up oracle exchange rate
        priceOracle.setPrice(address(rewardToken), address(baseAsset), 1e15);
        
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
    
    function testFuzz_withdrawal(uint256 depositAmount) public {
        // Bound deposit amount to reasonable values
        depositAmount = bound(depositAmount, 1e6, 10000e6);
        
        // Setup: deposit
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
    
    function test_updatePriceChecker_revertsWhen_notManagement() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
    }
    
    function test_claimRewardsAndSwap_revertsWhen_notKeeper() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.claimRewardsAndSwap();
        
        vm.prank(keeper);
        strategy.claimRewardsAndSwap();
        
        vm.prank(management);
        strategy.claimRewardsAndSwap(); // Management can also call keeper functions
    }
    
    /// CANCEL SWAP TESTS ///
    
    function test_cancelSwap() public {
        // Setup: First initiate a swap
        rewardToken.mint(address(strategy), 100e18);
        
        // Configure price checker
        vm.prank(management);
        strategy.updatePriceChecker(address(rewardToken), address(priceChecker));
        
        // Claim rewards and initiate swap
        vm.prank(keeper);
        strategy.claimRewardsAndSwap();
        
        // Verify tokens were transferred to Milkman
        assertEq(rewardToken.balanceOf(address(milkman)), 100e18);
        assertEq(rewardToken.balanceOf(address(strategy)), 0);
        
        // Now cancel the swap as management
        vm.prank(management);
        strategy.cancelSwap(
            100e18,
            address(rewardToken),
            address(baseAsset),
            address(priceChecker),
            abi.encode(500) // 5% max deviation
        );
        
        // Verify tokens were returned
        assertEq(rewardToken.balanceOf(address(strategy)), 100e18);
        assertEq(rewardToken.balanceOf(address(milkman)), 0);
    }
    
    function test_cancelSwap_revertsWhen_notManagement() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.cancelSwap(
            100e18,
            address(rewardToken),
            address(baseAsset),
            address(priceChecker),
            abi.encode(500)
        );
    }
    
    /// PARAMETER SETTING TESTS ///
    
    function testFuzz_setMaxPriceDeviation(uint256 deviation) public {
        // Bound deviation to valid range (0 to 10000 bps = 100%)
        deviation = bound(deviation, 0, 10000);
        
        vm.prank(management);
        strategy.setMaxPriceDeviation(deviation);
        
        assertEq(strategy.maxPriceDeviationBps(), deviation);
    }
    
    function test_setMaxPriceDeviation_revertsWhen_tooHigh() public {
        vm.prank(management);
        vm.expectRevert(AutopoolCompounder.InvalidMaxDeviation.selector);
        strategy.setMaxPriceDeviation(10001); // > 100%
    }
    
    /// VIEW FUNCTION TESTS ///
    
    function test_getConfiguredRewardTokens() public {
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
    
    function test_stakedBalance() public {
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
    
    function test_pendingRewards() public {
        rewarder.setEarned(address(strategy), 123e18);
        assertEq(strategy.pendingRewards(), 123e18);
    }
    
    /// HELPER FUNCTIONS ///
    
    function _deployTokenizedStrategy() internal {
        // Deploy a mock factory
        MockFactory factory = new MockFactory(0, address(0));
        
        // Deploy TokenizedStrategy with the factory
        TokenizedStrategy tokenizedStrategyImpl = new TokenizedStrategy(address(factory));
        
        // Get the bytecode of the deployed TokenizedStrategy
        bytes memory bytecode = address(tokenizedStrategyImpl).code;
        
        // Etch the bytecode to the expected address
        vm.etch(TOKENIZED_STRATEGY, bytecode);
        
        // Label for debugging
        vm.label(TOKENIZED_STRATEGY, "TokenizedStrategy");
    }
}
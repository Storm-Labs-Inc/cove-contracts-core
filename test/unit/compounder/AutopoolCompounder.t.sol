// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AutopoolCompounder } from "src/compounder/AutopoolCompounder.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";

import { OraclePriceChecker } from "src/compounder/pricecheckers/OraclePriceChecker.sol";
import { MockAutopool } from "test/utils/mocks/MockAutopool.sol";
import { MockAutopoolMainRewarder } from "test/utils/mocks/MockAutopoolMainRewarder.sol";
import { MockMilkman } from "test/utils/mocks/MockMilkman.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

import { TokenizedStrategy } from "tokenized-strategy-3.0.4/src/TokenizedStrategy.sol";
import { IFactory } from "tokenized-strategy-3.0.4/src/interfaces/IFactory.sol";
import { ITokenizedStrategy } from "tokenized-strategy-3.0.4/src/interfaces/ITokenizedStrategy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mock autopool that can simulate slippage by returning fewer shares than expected
contract MockMaliciousAutopool is ERC4626, IAutopool {
    bool public isShutdown;
    bool public paused;
    uint256 public oldestDebtReporting;
    uint256 public slippageRatio = 10_000; // Basis points, 10000 = 100% (no slippage)

    constructor(
        address _baseAsset,
        string memory name,
        string memory symbol
    )
        ERC20(name, symbol)
        ERC4626(IERC20(_baseAsset))
    {
        // baseAsset is stored in ERC4626's _asset variable
    }

    function setSlippageRatio(uint256 _slippageRatio) external {
        slippageRatio = _slippageRatio;
    }

    function deposit(uint256 assets, address receiver) public override(ERC4626, IERC4626) returns (uint256 shares) {
        // Normal preview calculation
        shares = previewDeposit(assets);

        // Apply slippage - return fewer shares than expected
        uint256 actualShares = (shares * slippageRatio) / 10_000;

        // Transfer assets from sender
        IERC20(asset()).transferFrom(msg.sender, address(this), assets);

        // Mint the reduced amount of shares (simulating slippage)
        _mint(receiver, actualShares);

        emit Deposit(msg.sender, receiver, assets, actualShares);
        return actualShares;
    }

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }

    function shutdown() external {
        isShutdown = true;
    }

    // ERC20Permit functions (stub implementation)
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        // Stub implementation
    }

    function nonces(address) external pure returns (uint256) {
        return 0;
    }

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0);
    }

    function setOldestDebtReporting(uint256 timestamp) external {
        oldestDebtReporting = timestamp;
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
        strategy = new AutopoolCompounder(address(autopool), address(rewarder), address(milkman));

        // Set up keeper role
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setKeeper(keeper);

        // Fund users with base asset
        baseAsset.mint(alice, 10_000_000e6); // 10 million USDC for fuzz tests
        baseAsset.mint(bob, 10_000_000e6);

        // Fund rewarder with reward tokens
        rewardToken.mint(address(rewarder), 1_000_000e18);
    }

    /// DEPLOYMENT TESTS ///

    function test_deployment() public {
        assertEq(ITokenizedStrategy(address(strategy)).asset(), address(autopool));
        assertEq(address(strategy.rewarder()), address(rewarder));
        assertEq(address(strategy.milkman()), address(milkman));
        assertEq(address(strategy.baseAsset()), address(baseAsset));
        assertEq(strategy.maxPriceDeviationBps(), 500);
        assertEq(strategy.maxDepositSlippageBps(), 100);
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
        depositAmount = bound(depositAmount, 1e6, 10_000e6);

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

    function test_harvestAndReport_withSlippageProtection() public {
        // Setup: deposit and stake
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();

        // Put base asset in strategy (simulating settled swap)
        uint256 baseBalance = 50e6;
        baseAsset.mint(address(strategy), baseBalance);

        // Store initial state
        uint256 initialStakedBalance = strategy.stakedBalance();

        // Report should succeed with normal conditions
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();

        // Should have compounded the base asset
        assertTrue(profit > 0);
        assertEq(loss, 0);
        assertTrue(strategy.stakedBalance() > initialStakedBalance);
    }

    function test_harvestAndReport_revertsWhen_slippageExceeded() public {
        // Setup: deposit and stake
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();

        // Set very low slippage tolerance (0.1%)
        vm.prank(management);
        strategy.setMaxDepositSlippage(10);

        // Put base asset in strategy
        uint256 baseBalance = 50e6;
        baseAsset.mint(address(strategy), baseBalance);

        // Create a malicious mock autopool that returns fewer shares than expected
        // This simulates the slippage scenario
        MockMaliciousAutopool maliciousPool = new MockMaliciousAutopool(address(baseAsset), "Malicious", "MAL");

        // Create a rewarder for the malicious autopool
        MockAutopoolMainRewarder maliciousRewarder =
            new MockAutopoolMainRewarder(address(maliciousPool), address(rewardToken));

        // Deploy a new strategy with the malicious autopool
        vm.prank(management);
        AutopoolCompounder maliciousStrategy =
            new AutopoolCompounder(address(maliciousPool), address(maliciousRewarder), address(milkman));

        vm.prank(management);
        maliciousStrategy.setMaxDepositSlippage(10); // 0.1%

        // Set up keeper role for the malicious strategy
        vm.prank(management);
        ITokenizedStrategy(address(maliciousStrategy)).setKeeper(keeper);

        // Put base asset in the malicious strategy
        baseAsset.mint(address(maliciousStrategy), baseBalance);

        // Set the malicious pool to return 90% fewer shares (simulating extreme slippage)
        maliciousPool.setSlippageRatio(100); // 1% of expected shares

        // Report should revert due to slippage
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                AutopoolCompounder.SlippageExceeded.selector,
                baseBalance, // expectedShares (1:1 in previewDeposit)
                baseBalance / 100, // actualShares (1% due to slippage)
                (baseBalance * 9990) / 10_000 // minShares (99.9% of expected)
            )
        );
        ITokenizedStrategy(address(maliciousStrategy)).report();
    }

    /// WITHDRAWAL TESTS ///

    function testFuzz_withdrawal(uint256 depositAmount) public {
        // Bound deposit amount to reasonable values
        depositAmount = bound(depositAmount, 1e6, 10_000e6);

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
        vm.prank(keeper);
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

    function testFuzz_cancelSwap_revertsWhen_notKeeper(address account) public {
        vm.assume(account != keeper);
        vm.prank(account);
        vm.expectRevert();
        strategy.cancelSwap(100e18, address(rewardToken), address(baseAsset), address(priceChecker), abi.encode(500));
    }

    /// PARAMETER SETTING TESTS ///

    function testFuzz_setMaxPriceDeviation(uint256 deviation) public {
        // Bound deviation to valid range (0 to 10000 bps = 100%)
        deviation = bound(deviation, 0, 10_000);

        vm.prank(management);
        strategy.setMaxPriceDeviation(deviation);

        assertEq(strategy.maxPriceDeviationBps(), deviation);
    }

    function test_setMaxPriceDeviation_revertsWhen_tooHigh() public {
        vm.prank(management);
        vm.expectRevert(AutopoolCompounder.InvalidMaxDeviation.selector);
        strategy.setMaxPriceDeviation(10_001); // > 100%
    }

    function testFuzz_setMaxDepositSlippage(uint256 slippage) public {
        // Bound slippage to valid range (0 to 10000 bps = 100%)
        slippage = bound(slippage, 0, 10_000);

        vm.prank(management);
        strategy.setMaxDepositSlippage(slippage);

        assertEq(strategy.maxDepositSlippageBps(), slippage);
    }

    function test_setMaxDepositSlippage_revertsWhen_tooHigh() public {
        vm.prank(management);
        vm.expectRevert(AutopoolCompounder.InvalidMaxDeviation.selector);
        strategy.setMaxDepositSlippage(10_001); // > 100%
    }

    function test_setMaxDepositSlippage_revertsWhen_notManagement() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.setMaxDepositSlippage(200);

        vm.prank(management);
        strategy.setMaxDepositSlippage(200);
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

    function test_harvestAndReport_skipWhen_noBaseBalance() public {
        // Setup: deposit and stake but no base asset to compound
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        baseAsset.approve(address(autopool), depositAmount);
        uint256 shares = autopool.deposit(depositAmount, alice);
        autopool.approve(address(strategy), shares);
        ITokenizedStrategy(address(strategy)).deposit(shares, alice);
        vm.stopPrank();

        uint256 initialStakedBalance = strategy.stakedBalance();

        // Report without any base balance to compound
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();

        // Should report no change since no base balance to compound
        assertEq(profit, 0);
        assertEq(loss, 0);
        assertEq(strategy.stakedBalance(), initialStakedBalance);
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

    function test_maxDepositSlippageBps_defaultValue() public {
        assertEq(strategy.maxDepositSlippageBps(), 100); // 1%
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

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { AutoPoolCompounderOracle } from "src/oracles/AutoPoolCompounderOracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "test/utils/mocks/ERC4626Mock.sol";
import { MockAutopool } from "test/utils/mocks/MockAutopool.sol";

/// @notice Mock AutopoolCompounder that acts as an ERC4626 vault holding Autopool tokens
contract MockAutopoolCompounder is ERC4626Mock {
    constructor(
        IERC20 _autopool,
        string memory _name,
        string memory _symbol
    )
        ERC4626Mock(_autopool, _name, _symbol, 18)
    { }
}

contract AutoPoolCompounderOracleTest is BaseTest {
    // Mock contracts
    ERC20Mock public mockBaseAsset; // e.g., USDC
    MockAutopool public mockAutopool;
    MockAutopoolCompounder public mockCompounder;
    AutoPoolCompounderOracle public oracle;

    // Test users
    address public alice;

    function setUp() public override {
        super.setUp();

        // Create test users
        alice = createUser("alice");

        // Deploy mock contracts in the correct order
        // 1. Base asset (e.g., USDC)
        mockBaseAsset = new ERC20Mock();

        // 2. Autopool that holds base asset
        mockAutopool = new MockAutopool(address(mockBaseAsset), "Mock Autopool", "mAP");

        // 3. Compounder that holds Autopool tokens
        mockCompounder = new MockAutopoolCompounder(IERC20(address(mockAutopool)), "Mock Compounder", "mCOMP");

        // Set initial fresh debt reporting
        // Use a reasonable timestamp to avoid underflow at block.timestamp = 0
        vm.warp(2 days);
        mockAutopool.setOldestDebtReporting(block.timestamp - 1 hours);

        // Deploy the oracle
        oracle = new AutoPoolCompounderOracle(IERC4626(address(mockCompounder)));
    }

    // Constructor Tests
    function test_constructor_passWhen_validChain() public {
        // Verify the chain was properly discovered
        assertEq(oracle.vaults(0), address(mockCompounder));
        assertEq(oracle.vaults(1), address(mockAutopool));

        // Verify base and quote are set correctly
        assertEq(oracle.base(), address(mockCompounder));
        assertEq(oracle.quote(), address(mockBaseAsset));

        // Verify autopool is set
        assertEq(address(oracle.autopool()), address(mockAutopool));
    }

    function test_constructor_revertWhen_debtReportingStale() public {
        // Create fresh instances for this test
        ERC20Mock localBaseAsset = new ERC20Mock();
        MockAutopool localAutopool = new MockAutopool(address(localBaseAsset), "Local Autopool", "lAP");
        MockAutopoolCompounder localCompounder =
            new MockAutopoolCompounder(IERC20(address(localAutopool)), "Local Compounder", "lCOMP");

        // Set stale debt reporting (25 hours ago)
        localAutopool.setOldestDebtReporting(block.timestamp - 25 hours);

        // Should revert when trying to create oracle with stale debt
        vm.expectRevert(
            abi.encodeWithSelector(
                AutoPoolCompounderOracle.StaleDebtReporting.selector, block.timestamp - 25 hours, block.timestamp
            )
        );
        new AutoPoolCompounderOracle(IERC4626(address(localCompounder)));
    }

    // Price Conversion Tests
    function test_getQuote_passWhen_freshDebtReporting() public {
        // Set fresh debt reporting (1 hour ago)
        mockAutopool.setOldestDebtReporting(block.timestamp - 1 hours);

        uint256 compounderShares = 1e18; // 1 compounder share

        // Calculate expected conversion through the chain
        uint256 expectedAssets = mockCompounder.convertToAssets(compounderShares);
        expectedAssets = mockAutopool.convertToAssets(expectedAssets);

        uint256 actualAssets = oracle.getQuote(compounderShares, address(mockCompounder), address(mockBaseAsset));
        assertEq(actualAssets, expectedAssets);
    }

    function test_getQuote_revertWhen_debtReportingStale() public {
        // Initially set fresh debt reporting
        mockAutopool.setOldestDebtReporting(block.timestamp - 1 hours);

        // Warp time forward to make debt reporting stale
        vm.warp(block.timestamp + 24 hours);

        uint256 compounderShares = 1e18;

        // Should revert when trying to get quote with stale debt
        vm.expectRevert(
            abi.encodeWithSelector(
                AutoPoolCompounderOracle.StaleDebtReporting.selector, block.timestamp - 25 hours, block.timestamp
            )
        );
        oracle.getQuote(compounderShares, address(mockCompounder), address(mockBaseAsset));
    }

    function test_getQuote_passWhen_exactlyAtThreshold() public {
        // Set debt reporting to exactly 24 hours ago
        mockAutopool.setOldestDebtReporting(block.timestamp - 24 hours);

        uint256 compounderShares = 1e18;

        // Should work when exactly at the 24-hour threshold
        uint256 expectedAssets = mockCompounder.convertToAssets(compounderShares);
        expectedAssets = mockAutopool.convertToAssets(expectedAssets);

        uint256 actualAssets = oracle.getQuote(compounderShares, address(mockCompounder), address(mockBaseAsset));
        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_getQuote_passWhen_convertingCompounderToBase(uint256 shares, uint256 debtAge) public {
        // Bound inputs
        shares = bound(shares, 0, type(uint128).max);
        debtAge = bound(debtAge, 0, 23 hours); // Keep debt fresh

        // Set debt reporting age
        mockAutopool.setOldestDebtReporting(block.timestamp - debtAge);

        // Calculate expected conversion
        uint256 expectedAssets = shares;
        expectedAssets = mockCompounder.convertToAssets(expectedAssets);
        expectedAssets = mockAutopool.convertToAssets(expectedAssets);

        uint256 actualAssets = oracle.getQuote(shares, address(mockCompounder), address(mockBaseAsset));
        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_getQuote_passWhen_convertingBaseToCompounder(uint256 assets, uint256 debtAge) public {
        // Bound inputs
        assets = bound(assets, 0, type(uint128).max);
        debtAge = bound(debtAge, 0, 23 hours); // Keep debt fresh

        // Set debt reporting age
        mockAutopool.setOldestDebtReporting(block.timestamp - debtAge);

        // Calculate expected conversion (reverse direction)
        uint256 expectedShares = assets;
        expectedShares = mockAutopool.convertToShares(expectedShares);
        expectedShares = mockCompounder.convertToShares(expectedShares);

        uint256 actualShares = oracle.getQuote(assets, address(mockBaseAsset), address(mockCompounder));
        assertEq(actualShares, expectedShares);
    }

    function test_getQuotes_passWhen_bidAskSame() public {
        // Set fresh debt reporting
        mockAutopool.setOldestDebtReporting(block.timestamp - 1 hours);

        uint256 compounderShares = 1e18;

        // Calculate expected
        uint256 expectedAssets = mockCompounder.convertToAssets(compounderShares);
        expectedAssets = mockAutopool.convertToAssets(expectedAssets);

        (uint256 bidOut, uint256 askOut) =
            oracle.getQuotes(compounderShares, address(mockCompounder), address(mockBaseAsset));

        // For this oracle, bid and ask should be the same
        assertEq(bidOut, expectedAssets);
        assertEq(askOut, expectedAssets);
        assertEq(bidOut, askOut);
    }

    function test_maxDebtReportingAge() public view {
        assertEq(oracle.MAX_DEBT_REPORTING_AGE(), 24 hours);
    }

    function test_name() public view {
        assertEq(oracle.name(), "ChainedERC4626Oracle");
    }
}

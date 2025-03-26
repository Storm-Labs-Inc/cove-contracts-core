// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Errors as PriceOracleErrors } from "euler-price-oracle/src/lib/Errors.sol";
import { ChainedERC4626Oracle } from "src/oracles/ChainedERC4626Oracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "test/utils/mocks/ERC4626Mock.sol";

contract ChainedERC4626OracleTest is BaseTest {
    // ysyG-yvUSDS-1, boosties strategy for yG-yvUSDS-1
    address constant YSYG_YVUSDS = 0x81f78DeF7a3a8B0F6aABa69925efC69E70239D95;
    // yG-yvUSDS-1, yearn gauge for yvUSDS-1
    address constant YG_YVUSDS = 0xd57aEa3686d623dA2dCEbc87010a4F2F38Ac7B15;
    // yvUSDS-1, yearn vault
    address constant YVUSDS = 0x182863131F9a4630fF9E27830d945B1413e347E8;
    // USDS, base asset
    address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // Mock contracts for testing chain discovery
    ERC20Mock public mockBaseAsset;
    ERC4626Mock public mockVault1;
    ERC4626Mock public mockVault2;
    ERC4626Mock public mockVault3;
    ChainedERC4626Oracle public mockOracle;

    // Real contract for mainnet fork testing
    ChainedERC4626Oracle public yearnOracle;

    function setUp() public override {
        super.setUp();

        // Fork mainnet for real contract tests
        // Use block number after ysyG-yvUSDS-1 was deployed
        vm.createSelectFork("mainnet", 22_134_359);

        // Setup mock environment with 3 chained vaults
        mockBaseAsset = new ERC20Mock();
        mockVault1 = new ERC4626Mock(IERC20(mockBaseAsset), "Mock Vault 1", "mVLT1", 18);
        mockVault2 = new ERC4626Mock(IERC20(mockVault1), "Mock Vault 2", "mVLT2", 18);
        mockVault3 = new ERC4626Mock(IERC20(mockVault2), "Mock Vault 3", "mVLT3", 18);
        mockOracle = new ChainedERC4626Oracle(IERC4626(address(mockVault3)), address(mockBaseAsset));

        // Setup real contract oracle for Yearn Staked USDS vault chain
        yearnOracle = new ChainedERC4626Oracle(IERC4626(YSYG_YVUSDS), USDS);
    }

    // Constructor Tests
    function test_constructor_revertWhen_invalidVault() public {
        vm.expectRevert(ChainedERC4626Oracle.InvalidVaultChain.selector);
        new ChainedERC4626Oracle(IERC4626(address(0)), address(mockBaseAsset));
    }

    function test_constructor_revertWhen_targetAssetNotReached() public {
        address randomAsset = address(0x123);
        vm.expectRevert(ChainedERC4626Oracle.TargetAssetNotReached.selector);
        new ChainedERC4626Oracle(IERC4626(address(mockVault3)), randomAsset);
    }

    // Mock Chain Tests
    function test_constructor_passWhen_mockChainDiscovered() public {
        // Verify the chain was properly discovered
        assertEq(mockOracle.vaults(0), address(mockVault3));
        assertEq(mockOracle.vaults(1), address(mockVault2));
        assertEq(mockOracle.vaults(2), address(mockVault1));

        // Verify base and quote are set correctly
        assertEq(address(mockOracle.base()), address(mockVault3));
        assertEq(address(mockOracle.quote()), address(mockBaseAsset));
    }

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_mock(uint256 shares) public {
        // Bound shares to avoid overflow
        shares = bound(shares, 0, type(uint128).max);

        // Calculate expected conversion through the chain
        uint256 expectedAssets = shares;
        expectedAssets = mockVault3.convertToAssets(expectedAssets);
        expectedAssets = mockVault2.convertToAssets(expectedAssets);
        expectedAssets = mockVault1.convertToAssets(expectedAssets);

        uint256 actualAssets = mockOracle.getQuote(shares, address(mockVault3), address(mockBaseAsset));
        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_mock(uint256 assets) public {
        // Bound assets to avoid overflow
        assets = bound(assets, 0, type(uint128).max);

        // Calculate expected conversion through the chain
        uint256 expectedShares = assets;
        expectedShares = mockVault1.convertToShares(expectedShares);
        expectedShares = mockVault2.convertToShares(expectedShares);
        expectedShares = mockVault3.convertToShares(expectedShares);

        uint256 actualShares = mockOracle.getQuote(assets, address(mockBaseAsset), address(mockVault3));
        assertEq(actualShares, expectedShares);
    }

    // Yearn Staked USDS Tests
    function test_constructor_passWhen_yearnChainDiscovered() public {
        // Verify the chain was properly discovered
        assertEq(yearnOracle.vaults(0), YSYG_YVUSDS);
        assertEq(yearnOracle.vaults(1), YG_YVUSDS);
        assertEq(yearnOracle.vaults(2), YVUSDS);

        // Verify base and quote are set correctly
        assertEq(address(yearnOracle.base()), YSYG_YVUSDS);
        assertEq(address(yearnOracle.quote()), USDS);
    }

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_yearn(uint256 shares) public {
        // Bound shares to avoid overflow and unrealistic values
        shares = bound(shares, 0, 1e24); // 1 million tokens

        // Calculate conversion through the Yearn vault chain
        uint256 expectedAssets = shares;
        expectedAssets = IERC4626(YSYG_YVUSDS).convertToAssets(expectedAssets);
        expectedAssets = IERC4626(YG_YVUSDS).convertToAssets(expectedAssets);
        expectedAssets = IERC4626(YVUSDS).convertToAssets(expectedAssets);

        uint256 actualAssets = yearnOracle.getQuote(shares, YSYG_YVUSDS, USDS);
        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_yearn(uint256 assets) public {
        // Bound assets to avoid overflow and unrealistic values
        assets = bound(assets, 0, 1e24); // 1 million tokens

        // Calculate conversion through the Yearn vault chain
        uint256 expectedShares = assets;
        expectedShares = IERC4626(YVUSDS).convertToShares(expectedShares);
        expectedShares = IERC4626(YG_YVUSDS).convertToShares(expectedShares);
        expectedShares = IERC4626(YSYG_YVUSDS).convertToShares(expectedShares);

        uint256 actualShares = yearnOracle.getQuote(assets, USDS, YSYG_YVUSDS);
        assertEq(actualShares, expectedShares);
    }

    function test_getQuote_revertWhen_unsupportedTokens() public {
        address randomAddress = address(0x123);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracleErrors.PriceOracle_NotSupported.selector, randomAddress, address(mockBaseAsset)
            )
        );
        mockOracle.getQuote(1e18, randomAddress, address(mockBaseAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracleErrors.PriceOracle_NotSupported.selector, address(mockVault3), randomAddress
            )
        );
        mockOracle.getQuote(1e18, address(mockVault3), randomAddress);
    }
}

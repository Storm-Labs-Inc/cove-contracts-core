// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Errors as PriceOracleErrors } from "euler-price-oracle/src/lib/Errors.sol";
import { ERC4626Oracle } from "src/oracles/ERC4626Oracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "test/utils/mocks/ERC4626Mock.sol";

contract ERC4626OracleTest is BaseTest {
    // Constants for Yearn USDC vaults
    address public constant YEARN_USDC_VAULT_1 = 0xAe7d8Db82480E6d8e3873ecbF22cf17b3D8A7308;
    address public constant YEARN_USDC_VAULT_2 = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;

    // Mock contracts
    ERC20Mock public mockAsset;
    ERC4626Mock public mockVault;
    ERC4626Oracle public mockOracle;

    // Real contracts
    ERC4626Oracle public sdaiOracle;
    ERC4626Oracle public yearnOracle1;
    ERC4626Oracle public yearnOracle2;

    function setUp() public override {
        super.setUp();

        // Setup mock environment
        mockAsset = new ERC20Mock();
        mockVault = new ERC4626Mock(IERC20(mockAsset), "Mock Vault", "mVLT", 18);
        mockOracle = new ERC4626Oracle(IERC4626(address(mockVault)));

        // Fork mainnet for real contract tests
        vm.createSelectFork("mainnet", BLOCK_NUMBER_MAINNET_FORK);

        // Setup real contract oracles
        sdaiOracle = new ERC4626Oracle(IERC4626(ETH_SDAI));
        yearnOracle1 = new ERC4626Oracle(IERC4626(YEARN_USDC_VAULT_1));
        yearnOracle2 = new ERC4626Oracle(IERC4626(YEARN_USDC_VAULT_2));
    }

    function test_constructor_revertWhen_invalidVault() public {
        vm.expectRevert();
        new ERC4626Oracle(IERC4626(address(0)));
        vm.expectRevert();
        new ERC4626Oracle(IERC4626(address(ETH_DAI)));
    }

    // Mock Tests
    function test_constructor_passWhen_mockOracleInitialized() public {
        assertEq(address(mockOracle.base()), address(mockVault));
        assertEq(address(mockOracle.quote()), address(mockAsset));
    }

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_mock(uint256 shares) public {
        // Bound shares to avoid overflow
        shares = bound(shares, 0, type(uint128).max);

        uint256 expectedAssets = mockVault.convertToAssets(shares);
        uint256 actualAssets = mockOracle.getQuote(shares, address(mockVault), address(mockAsset));
        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_mock(uint256 assets) public {
        // Bound assets to avoid overflow
        assets = bound(assets, 0, type(uint128).max);

        uint256 expectedShares = mockVault.convertToShares(assets);
        uint256 actualShares = mockOracle.getQuote(assets, address(mockAsset), address(mockVault));
        assertEq(actualShares, expectedShares);
    }

    function testFuzz_getQuote_passWhen_zeroAmount(
        bool isBaseToQuote,
        address randomBase,
        address randomQuote
    )
        public
    {
        vm.assume(randomBase != address(0));
        vm.assume(randomQuote != address(0));

        address base = isBaseToQuote ? address(mockVault) : address(mockAsset);
        address quote = isBaseToQuote ? address(mockAsset) : address(mockVault);

        uint256 result = mockOracle.getQuote(0, base, quote);
        assertEq(result, 0);
    }

    function testFuzz_getQuote_revertWhen_invalidBaseOrQuote(uint256 amount, address invalidAddress) public {
        vm.assume(invalidAddress != address(mockVault));
        vm.assume(invalidAddress != address(mockAsset));
        vm.assume(invalidAddress != address(0));

        // Test invalid base
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracleErrors.PriceOracle_NotSupported.selector, invalidAddress, address(mockAsset)
            )
        );
        mockOracle.getQuote(amount, invalidAddress, address(mockAsset));

        // Test invalid quote
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracleErrors.PriceOracle_NotSupported.selector, address(mockVault), invalidAddress
            )
        );
        mockOracle.getQuote(amount, address(mockVault), invalidAddress);
    }

    // sDAI Tests
    function test_constructor_passWhen_sdaiOracleInitialized() public {
        assertEq(address(sdaiOracle.base()), ETH_SDAI);
        assertEq(address(sdaiOracle.quote()), ETH_DAI);
    }

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_sdai(uint256 shares) public {
        // Bound shares to avoid overflow and unrealistic values
        shares = bound(shares, 0, 1e27); // 1 billion sDAI

        uint256 expectedAssets = IERC4626(ETH_SDAI).convertToAssets(shares);
        uint256 actualAssets = sdaiOracle.getQuote(shares, ETH_SDAI, ETH_DAI);
        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_sdai(uint256 assets) public {
        // Bound assets to avoid overflow and unrealistic values
        assets = bound(assets, 0, 1e27); // 1 billion DAI

        uint256 expectedShares = IERC4626(ETH_SDAI).convertToShares(assets);
        uint256 actualShares = sdaiOracle.getQuote(assets, ETH_DAI, ETH_SDAI);
        assertEq(actualShares, expectedShares);
    }

    // Yearn USDC Vault Tests
    function test_constructor_passWhen_yearnOracleInitialized() public {
        assertEq(address(yearnOracle1.base()), YEARN_USDC_VAULT_1);
        assertEq(address(yearnOracle1.quote()), ETH_USDC);

        assertEq(address(yearnOracle2.base()), YEARN_USDC_VAULT_2);
        assertEq(address(yearnOracle2.quote()), ETH_USDC);
    }

    function testFuzz_getQuote_passWhen_convertingBaseToQuote_yearn(uint256 shares) public {
        // Bound shares to avoid overflow and unrealistic values
        shares = bound(shares, 0, 1e12); // 1 million USDC worth of shares

        // Test first Yearn vault
        uint256 expectedAssets1 = IERC4626(YEARN_USDC_VAULT_1).convertToAssets(shares);
        uint256 actualAssets1 = yearnOracle1.getQuote(shares, YEARN_USDC_VAULT_1, ETH_USDC);
        assertEq(actualAssets1, expectedAssets1);

        // Test second Yearn vault
        uint256 expectedAssets2 = IERC4626(YEARN_USDC_VAULT_2).convertToAssets(shares);
        uint256 actualAssets2 = yearnOracle2.getQuote(shares, YEARN_USDC_VAULT_2, ETH_USDC);
        assertEq(actualAssets2, expectedAssets2);
    }

    function testFuzz_getQuote_passWhen_convertingQuoteToBase_yearn(uint256 assets) public {
        // Bound assets to avoid overflow and unrealistic values
        assets = bound(assets, 0, 1e12); // 1 million USDC

        // Test first Yearn vault
        uint256 expectedShares1 = IERC4626(YEARN_USDC_VAULT_1).convertToShares(assets);
        uint256 actualShares1 = yearnOracle1.getQuote(assets, ETH_USDC, YEARN_USDC_VAULT_1);
        assertEq(actualShares1, expectedShares1);

        // Test second Yearn vault
        uint256 expectedShares2 = IERC4626(YEARN_USDC_VAULT_2).convertToShares(assets);
        uint256 actualShares2 = yearnOracle2.getQuote(assets, ETH_USDC, YEARN_USDC_VAULT_2);
        assertEq(actualShares2, expectedShares2);
    }

    function test_getQuote_revertWhen_unsupportedTokens() public {
        address randomAddress = address(0x123);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracleErrors.PriceOracle_NotSupported.selector, randomAddress, address(mockAsset)
            )
        );
        mockOracle.getQuote(1e18, randomAddress, address(mockAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracleErrors.PriceOracle_NotSupported.selector, address(mockVault), randomAddress
            )
        );
        mockOracle.getQuote(1e18, address(mockVault), randomAddress);
    }
}

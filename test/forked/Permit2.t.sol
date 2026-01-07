// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { console } from "forge-std/console.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";

interface IVyperPermit {
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 expiry,
        bytes calldata signature
    )
        external
        returns (bool);
}

contract Permit2Test is BaseTest {
    BasketToken public basket;
    BasketToken public basket2;

    function setUp() public override {
        forkNetworkAt("mainnet", BLOCK_NUMBER_MAINNET_FORK);
        super.setUp();
        address assetRegistry = createUser("assetRegistry");
        address implementation = address(new BasketToken());
        basket = BasketToken(Clones.clone(implementation));
        basket2 = BasketToken(Clones.clone(implementation));
        basket.initialize((IERC20(ETH_WEETH)), "test", "TEST", 1, address(1), assetRegistry);
        basket2.initialize((IERC20(ETH_WETH)), "test2", "TEST2", 8, address(1), assetRegistry);

        // mock call to return ENABLED for the asset
        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket.bitFlag()), abi.encode(false)
        );
        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket2.bitFlag()), abi.encode(false)
        );
    }

    // Testing for ERC-2612 compatible tokens, without using Permit2
    function testFuzz_multicallPermit_requestDeposit_erc2612(uint256 amount) public {
        amount = bound(amount, 1, type(uint160).max);
        (address from, uint256 key) = makeAddrAndKey("bob");

        address asset = BasketToken(basket).asset();
        deal(asset, from, amount);

        // No direct approval exists
        assertEq(IERC20(asset).allowance(from, address(basket)), 0);

        uint256 deadline = vm.getBlockTimestamp() + 1000;

        // Generate the ERC-2612 signature
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(asset, from, key, address(basket), amount, deadline);

        // Use multicall to call permit2 and requestDeposit
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            BasketToken.permit2.selector, IERC20(address(asset)), from, address(basket), amount, deadline, v, r, s
        );
        data[1] = abi.encodeWithSelector(BasketToken.requestDeposit.selector, amount, from, from);
        vm.prank(from);
        basket.multicall(data);

        // Check state and verify it worked without doing any approval tx.
        assertEq(basket.pendingDepositRequest(2, from), amount);
    }

    // Testing for non-permit tokens, using Permit2
    function testFuzz_multicallPermit_requestDeposit_permit2(uint256 amount) public {
        amount = bound(amount, 1, type(uint160).max);
        (address from, uint256 key) = makeAddrAndKey("bob");

        address asset = BasketToken(basket2).asset();
        deal(asset, from, amount);

        // Allow Permit2 to spend the asset
        vm.prank(from);
        IERC20(asset).approve(ETH_PERMIT2, _MAX_UINT256);

        uint256 deadline = vm.getBlockTimestamp() + 1000;

        // Generate the Permit2 signature
        (uint8 v, bytes32 r, bytes32 s) =
            _generatePermit2Signature(asset, from, key, address(basket2), amount, deadline);

        // Use multicall to call permit2 and requestDeposit
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            BasketToken.permit2.selector, IERC20(address(asset)), from, address(basket2), amount, deadline, v, r, s
        );
        data[1] = abi.encodeWithSelector(BasketToken.requestDeposit.selector, amount, from, from);
        vm.prank(from);
        basket2.multicall(data);

        // Check state
        assertEq(basket2.pendingDepositRequest(2, from), amount);
    }

    function test_confirm_permit_standard_availability() public {
        address[44] memory assets = [
            // Yearn Vaults and Gauges
            0x790a60024bC3aea28385b60480f15a0771f26D09, // MAINNET_ETH_YFI_VAULT_V2
            0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3, // MAINNET_ETH_YFI_GAUGE
            0xf70B3F1eA3BFc659FFb8b27E84FAE7Ef38b5bD3b, // MAINNET_DYFI_ETH_VAULT_V2
            0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc, // MAINNET_DYFI_ETH_GAUGE
            0x58900d761Ae3765B75DDFc235c1536B527F25d8F, // MAINNET_WETH_YETH_VAULT_V2
            0x81d93531720d86f0491DeE7D03f30b3b5aC24e59, // MAINNET_WETH_YETH_GAUGE
            0xbA61BaA1D96c2F4E25205B331306507BcAeA4677, // MAINNET_PRISMA_YPRISMA_VAULT_V2
            0x6130E6cD924a40b24703407F246966D7435D4998, // MAINNET_PRISMA_YPRISMA_GAUGE
            0x6E9455D109202b426169F0d8f01A3332DAE160f3, // MAINNET_CRV_YCRV_VAULT_V2
            0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C, // MAINNET_CRV_YCRV_GAUGE
            0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204, // MAINNET_YVUSDC_VAULT_V3
            0x622fA41799406B120f9a40dA843D358b7b2CFEE3, // MAINNET_YVUSDC_GAUGE
            0x028eC7330ff87667b6dfb0D94b954c820195336c, // MAINNET_YVDAI_VAULT_V3
            0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9, // MAINNET_YVDAI_GAUGE
            0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0, // MAINNET_YVWETH_VAULT_V3
            0x5943F7090282Eb66575662EADf7C60a717a7cE4D, // MAINNET_YVWETH_GAUGE
            0x6A5694C1b37fFA30690b6b60D8Cf89c937d408aD, // MAINNET_COVEYFI_YFI_VAULT_V2
            0x97A597CBcA514AfCc29cD300f04F98d9DbAA3624, // MAINNET_COVEYFI_YFI_GAUGE
            0x92545bCE636E6eE91D88D2D017182cD0bd2fC22e, // MAINNET_YVDAI_VAULT_V3_2
            0x38E3d865e34f7367a69f096C80A4fc329DB38BF4, // MAINNET_YVDAI_2_GAUGE
            0xAc37729B76db6438CE62042AE1270ee574CA7571, // MAINNET_YVWETH_VAULT_V3_2
            0x8E2485942B399EA41f3C910c1Bb8567128f79859, // MAINNET_YVWETH_2_GAUGE
            0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F, // MAINNET_YVCRVUSD_VAULT_V3_2
            0x71c3223D6f836f84cAA7ab5a68AAb6ECe21A9f3b, // MAINNET_YVCRVUSD_2_GAUGE
            // Curve LP Tokens and Pools
            0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490, // MAINNET_CRV3POOL_LP_TOKEN
            0xE8449F1495012eE18dB7Aa18cD5706b47e69627c, // MAINNET_DYFI_ETH_POOL_LP_TOKEN
            0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B, // MAINNET_TRI_CRYPTO_USDC
            0xc4AD29ba4B3c580e6D59105FFf484999997675Ff, // MAINNET_TRI_CRYPTO_2_LP_TOKEN
            0x29059568bB40344487d62f7450E78b8E6C74e0e5, // MAINNET_ETH_YFI_POOL_LP_TOKEN
            0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC, // MAINNET_FRAX_USDC_POOL_LP_TOKEN
            0x69ACcb968B19a53790f43e57558F5E443A91aF22, // MAINNET_WETH_YETH_POOL
            0x69833361991ed76f9e8DBBcdf9ea1520fEbFb4a7, // MAINNET_PRISMA_YPRISMA_POOL
            0x99f5aCc8EC2Da2BC0771c32814EFF52b712de1E5, // MAINNET_CRV_YCRV_POOL
            0xa3f152837492340dAAf201F4dFeC6cD73A8a9760, // MAINNET_COVEYFI_YFI_POOL
            // Other tokens
            0x41252E8691e964f7DE35156B68493bAb6797a275, // MAINNET_DYFI
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // MAINNET_USDC
            0xdAC17F958D2ee523a2206206994597C13D831ec7, // MAINNET_USDT
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // MAINNET_WETH
            0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, // MAINNET_YFI
            0x853d955aCEf822Db058eb8505911ED77F175b99e, // MAINNET_FRAX
            0xD533a949740bb3306d119CC777fa900bA034cd52, // MAINNET_CRV
            0xFCc5c47bE19d06BF83eB04298b026F81069ff65b, // MAINNET_YCRV
            0xdA47862a83dac0c112BA89c6abC2159b95afd71C, // MAINNET_PRISMA
            0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E // MAINNET_CRVUSD
        ];

        (address from, uint256 key) = makeAddrAndKey("bob");

        // Iterate through each asset to test ERC-2612 permit compatibility
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            string memory symbol = IERC20Metadata(asset).symbol();

            // First check if token implements DOMAIN_SEPARATOR() from ERC-2612
            try IERC20Permit(asset).DOMAIN_SEPARATOR() returns (bytes32) {
                // Generate permit signature for max approval
                (uint8 v, bytes32 r, bytes32 s) =
                    _generatePermitSignature(asset, from, key, address(this), UINT256_MAX, UINT256_MAX);

                // Store initial approval amount
                uint256 approvalBefore = IERC20(asset).allowance(from, address(this));

                // Try standard ERC-2612 permit first
                try IERC20Permit(asset).permit(from, address(this), UINT256_MAX, UINT256_MAX, v, r, s) {
                    uint256 approvalAfter = IERC20(asset).allowance(from, address(this));
                    assertGt(approvalAfter, approvalBefore);
                    console.log(string.concat(unicode"✅ ", vm.toString(asset), " ", symbol, " implements ERC-2612"));
                } catch {
                    // If standard permit fails, try Vyper-style permit which takes signature as packed bytes r, s, v
                    try IVyperPermit(asset)
                        .permit(from, address(this), UINT256_MAX, UINT256_MAX, abi.encodePacked(r, s, v)) {
                        uint256 approvalAfter = IERC20(asset).allowance(from, address(this));
                        assertGt(approvalAfter, approvalBefore);
                        console.log(
                            string.concat(
                                unicode"😵‍ ",
                                vm.toString(asset),
                                " ",
                                symbol,
                                " implements ERC-2612 (with last param as bytes r, s, v)"
                            )
                        );
                    } catch {
                        // Both permit attempts failed
                        console.log(string.concat(unicode"❓ ", vm.toString(asset), " ", symbol, " failed to permit"));
                    }
                }
            } catch {
                // Token does not implement DOMAIN_SEPARATOR, so not ERC-2612 compatible
                console.log(
                    string.concat(unicode"❌ ", vm.toString(asset), " ", symbol, " does not implement ERC-2612")
                );
            }
        }
    }
}

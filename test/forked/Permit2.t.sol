// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { IERC2612 } from "@openzeppelin/contracts/interfaces/IERC2612.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";
import { IPermit2 } from "src/interfaces/deps/permit2/IPermit2.sol";

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
}

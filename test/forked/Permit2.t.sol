// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";

contract Permit2Test is BaseTest {
    BasketToken public basket;
    BasketToken public basket2;

    function setUp() public override {
        forkNetworkAt("mainnet", 21_238_272);
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

    function testFuzz_multicallPermit_requestDeposit(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);
        (address from, uint256 key) = makeAddrAndKey("bob");

        address asset = BasketToken(basket).asset();
        deal(asset, from, amount);

        // Permit transfer
        vm.prank(from);
        IERC20(asset).approve(ETH_PERMIT2, _MAX_UINT256);

        (,, uint48 currentNonce) = IPermit2(ETH_PERMIT2).allowance(from, asset, address(basket));
        uint256 deadline = vm.getBlockTimestamp() + 1000;
        (uint8 v, bytes32 r, bytes32 s) =
            _generatePermitSignature(asset, from, key, address(basket), amount, currentNonce, deadline);

        // Use multicall to call permit and requestDeposit
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            BasketToken.permit2.selector, ERC20(address(asset)), from, address(basket), amount, deadline, v, r, s
        );
        data[1] = abi.encodeWithSelector(BasketToken.requestDeposit.selector, amount, from, from);
        vm.prank(from);
        basket.multicall(data);

        // Check state
        assertEq(basket.pendingDepositRequest(2, from), amount);
    }

    // Testing for non-permit tokens
    function testFuzz_multicallPermit_requestDeposit_approve(uint256 amount) public {
        amount = bound(amount, 1, type(uint160).max);
        (address from, uint256 key) = makeAddrAndKey("bob");

        address asset = BasketToken(basket2).asset();
        deal(asset, from, amount);

        // Permit transfer
        vm.prank(from);
        IERC20(asset).approve(ETH_PERMIT2, _MAX_UINT256);

        (,, uint48 currentNonce) = IPermit2(ETH_PERMIT2).allowance(from, asset, address(basket2));
        uint256 deadline = vm.getBlockTimestamp() + 1000;
        (uint8 v, bytes32 r, bytes32 s) =
            _generatePermit2Signature(asset, key, address(basket2), amount, currentNonce, deadline);
        // Use multicall to call permit and requestDeposit
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            BasketToken.permit2.selector, ERC20(address(asset)), from, address(basket2), amount, deadline, v, r, s
        );
        data[1] = abi.encodeWithSelector(BasketToken.requestDeposit.selector, amount, from, from);
        vm.prank(from);
        basket2.multicall(data);

        // Check state
        assertEq(basket2.pendingDepositRequest(2, from), amount);
    }
}

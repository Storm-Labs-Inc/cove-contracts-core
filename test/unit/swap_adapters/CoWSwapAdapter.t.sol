// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { CoWSwapAdapter } from "src/swap_adapters/CoWSwapAdapter.sol";
import { CoWSwapClone } from "src/swap_adapters/CoWSwapClone.sol";
import { BasketTradeOwnership, ExternalTrade } from "src/types/Trades.sol";

contract CoWSwapAdapterTest is Test {
    CoWSwapAdapter private adapter;
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    /// @dev Hash of the `_PROXY_INITCODE`.
    /// Equivalent to `keccak256(abi.encodePacked(hex"67363d3d37363d34f03d5260086018f3"))`.
    bytes32 internal constant _PROXY_INITCODE_HASH = 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;
    address clone;

    struct ExternalTradeWithoutBasketOwnership {
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 minAmount;
    }

    function setUp() public {
        // Deploy the CoWSwapAdapter contract
        clone = address(new CoWSwapClone());
        adapter = new CoWSwapAdapter(clone);
    }

    function testFuzz_constructor(address impl) public {
        vm.assume(impl != address(0));
        assertEq(new CoWSwapAdapter(impl).cloneImplementation(), impl, "Incorrect clone implementation address");
    }

    function testFuzz_executeTokenSwap(ExternalTradeWithoutBasketOwnership[] calldata externalTrades) public {
        vm.assume(externalTrades.length < 5);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            bytes32 salt = keccak256(
                abi.encodePacked(
                    externalTrades[i].sellToken,
                    externalTrades[i].buyToken,
                    externalTrades[i].sellAmount,
                    externalTrades[i].minAmount,
                    uint32(block.timestamp + 15 minutes)
                )
            );
            address deployed = _predictDeterministicAddress(salt, address(adapter));
            vm.mockCall(
                externalTrades[i].sellToken,
                abi.encodeWithSelector(IERC20.transfer.selector, deployed, externalTrades[i].sellAmount),
                abi.encode(true)
            );
            vm.mockCall(
                externalTrades[i].sellToken,
                abi.encodeWithSelector(IERC20.approve.selector, _VAULT_RELAYER, type(uint256).max),
                abi.encode(true)
            );
        }
        ExternalTrade[] memory trades = new ExternalTrade[](externalTrades.length);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            trades[i] = ExternalTrade({
                sellToken: externalTrades[i].sellToken,
                buyToken: externalTrades[i].buyToken,
                sellAmount: externalTrades[i].sellAmount,
                minAmount: externalTrades[i].minAmount,
                basketTradeOwnership: new BasketTradeOwnership[](0) // Use empty array for basket trade ownership
             });
        }
        adapter.executeTokenSwap(trades, "");
    }

    function testFuzz_completeTokenSwap(ExternalTradeWithoutBasketOwnership[] calldata externalTrades) public {
        testFuzz_executeTokenSwap(externalTrades);
        ExternalTrade[] memory trades = new ExternalTrade[](externalTrades.length);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            trades[i] = ExternalTrade({
                sellToken: externalTrades[i].sellToken,
                buyToken: externalTrades[i].buyToken,
                sellAmount: externalTrades[i].sellAmount,
                minAmount: externalTrades[i].minAmount,
                basketTradeOwnership: new BasketTradeOwnership[](0) // Use empty array for basket trade ownership
             });
            bytes32 salt = keccak256(
                abi.encodePacked(
                    externalTrades[i].sellToken,
                    externalTrades[i].buyToken,
                    externalTrades[i].sellAmount,
                    externalTrades[i].minAmount,
                    uint32(block.timestamp + 15 minutes)
                )
            );
            address deployed = _predictDeterministicAddress(salt, address(adapter));
            vm.mockCall(
                deployed,
                abi.encodeWithSelector(CoWSwapClone(deployed).claim.selector),
                abi.encodePacked(externalTrades[i].sellAmount, externalTrades[i].minAmount)
            );
        }
        uint256[2][] memory claimedAmounts = adapter.completeTokenSwap(trades);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            assertEq(claimedAmounts[i][0], externalTrades[i].sellAmount, "Incorrect claimed sell amount");
            assertEq(claimedAmounts[i][1], externalTrades[i].minAmount, "Incorrect claimed buy amount");
        }
    }

    /// @dev Returns the deterministic address for `salt` with `deployer`.
    function _predictDeterministicAddress(bytes32 salt, address deployer) internal pure returns (address deployed) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, deployer) // Store `deployer`.
            mstore8(0x0b, 0xff) // Store the prefix.
            mstore(0x20, salt) // Store the salt.
            mstore(0x40, _PROXY_INITCODE_HASH) // Store the bytecode hash.

            mstore(0x14, keccak256(0x0b, 0x55)) // Store the proxy's address.
            mstore(0x40, m) // Restore the free memory pointer.
            // 0xd6 = 0xc0 (short RLP prefix) + 0x16 (length of: 0x94 ++ proxy ++ 0x01).
            // 0x94 = 0x80 + 0x14 (0x14 = the length of an address, 20 bytes, in hex).
            mstore(0x00, 0xd694)
            mstore8(0x34, 0x01) // Nonce of the proxy contract (1).
            deployed := and(keccak256(0x1e, 0x17), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}

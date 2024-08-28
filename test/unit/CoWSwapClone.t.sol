// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import { Test } from "forge-std/Test.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";
import { CoWSwapClone } from "src/swap_adapters/CoWSwapClone.sol";

contract CoWSwapCloneTest is Test {
    using GPv2Order for GPv2Order.Data;

    CoWSwapClone private impl;
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    bytes32 internal constant _COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;

    function setUp() public {
        // Deploy the CoWSwapClone implementation
        impl = new CoWSwapClone();
    }

    function testFuzz_clone(
        bytes32 orderHash,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
        returns (address clone)
    {
        clone = ClonesWithImmutableArgs.clone3(
            address(impl),
            abi.encodePacked(orderHash, sellToken, buyToken, sellAmount, buyAmount, receiver, operator),
            salt
        );
        CoWSwapClone cloneInstance = CoWSwapClone(clone);
        // Test that the clone contract was deployed and cloned correctly
        assertEq(cloneInstance.storedOrderDigest(), orderHash, "Incorrect stored order digest");
        assertEq(cloneInstance.sellToken(), sellToken, "Incorrect sell token");
        assertEq(cloneInstance.buyToken(), buyToken, "Incorrect buy token");
        assertEq(cloneInstance.sellAmount(), sellAmount, "Incorrect sell amount");
        assertEq(cloneInstance.buyAmount(), buyAmount, "Incorrect buy amount");
        assertEq(cloneInstance.receiver(), receiver, "Incorrect receiver");
        assertEq(cloneInstance.operator(), operator, "Incorrect operator");
    }

    function testFuzz_initialize_revertWhen_SellTokenIsNotERC20(
        bytes32 orderHash,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        vm.assume(sellToken.code.length == 0);
        address clone = testFuzz_clone(orderHash, sellToken, buyToken, sellAmount, buyAmount, receiver, operator, salt);
        vm.expectRevert();
        CoWSwapClone(clone).initialize();
    }

    function testFuzz_initialize(
        bytes32 orderHash,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        address sellToken = address(new ERC20Mock());
        address clone = testFuzz_clone(orderHash, sellToken, buyToken, sellAmount, buyAmount, receiver, operator, salt);
        uint256 allowanceBefore = IERC20(sellToken).allowance(address(clone), _VAULT_RELAYER);
        assertEq(allowanceBefore, 0, "Allowance should be 0 before initialization");
        vm.expectCall(
            sellToken, abi.encodeWithSelector(IERC20(sellToken).approve.selector, _VAULT_RELAYER, type(uint256).max)
        );
        CoWSwapClone(clone).initialize();
        uint256 allowanceAfter = IERC20(sellToken).allowance(address(clone), _VAULT_RELAYER);
        assertEq(allowanceAfter, type(uint256).max, "Allowance should be max after initialization");
    }

    function testFuzz_isValidSignature(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: receiver,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: uint32(block.timestamp + 15 minutes),
            appData: 0,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        bytes32 orderDigest = order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR);
        address clone =
            testFuzz_clone(orderDigest, sellToken, buyToken, sellAmount, buyAmount, receiver, operator, salt);

        bytes memory encodedOrder = abi.encode(order);
        bytes4 result = CoWSwapClone(clone).isValidSignature(orderDigest, encodedOrder);
        assertEq(result, _ERC1271_MAGIC_VALUE, "Invalid signature magic value");
    }

    function testClaim() public {
        // // Test that the claim function transfers the correct amounts to the receiver
        // uint256 initialSellBalance = 1000;
        // uint256 initialBuyBalance = 500;

        // // Mint tokens to the clone contract
        // deal(address(sellToken), address(clone), initialSellBalance);
        // deal(address(buyToken), address(clone), initialBuyBalance);

        // // Claim the tokens
        // vm.prank(operator);
        // (uint256 claimedSellAmount, uint256 claimedBuyAmount) = clone.claim();

        // // Check that the tokens were transferred to the receiver
        // assertEq(claimedSellAmount, initialSellBalance, "Incorrect claimed sell amount");
        // assertEq(claimedBuyAmount, initialBuyBalance, "Incorrect claimed buy amount");
        // assertEq(sellToken.balanceOf(receiver), initialSellBalance, "Incorrect sell token balance");
        // assertEq(buyToken.balanceOf(receiver), initialBuyBalance, "Incorrect buy token balance");
    }

    function testFuzz_claim_revertWhen_CallerIsNotOperatorOrReceiver(
        bytes32 orderHash,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address receiver,
        address operator,
        bytes32 salt,
        address caller
    )
        public
    {
        address clone = testFuzz_clone(orderHash, sellToken, buyToken, sellAmount, buyAmount, receiver, operator, salt);
        // Test that the claim function reverts if called by someone other than the operator or receiver
        vm.assume(caller != operator && caller != receiver);
        vm.expectRevert(CoWSwapClone.CallerIsNotOperatorOrReceiver.selector);
        CoWSwapClone(clone).claim();
    }
}

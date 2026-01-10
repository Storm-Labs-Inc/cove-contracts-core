// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import { Test } from "forge-std/Test.sol";

import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";
import { CoWSwapCloneWith4626 } from "src/swap_adapters/experimental/CoWSwapCloneWith4626.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "test/utils/mocks/ERC4626Mock.sol";

contract CoWSwapCloneWith4626Test is Test {
    using GPv2Order for GPv2Order.Data;

    CoWSwapCloneWith4626 private impl;
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    bytes32 internal constant _COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;

    function setUp() public {
        impl = new CoWSwapCloneWith4626();
    }

    function _deployCloneAndAssertArgs(
        address sellUnderlying,
        address buyUnderlying,
        uint8 depthSell,
        uint8 depthBuy,
        uint256 sellAmount,
        uint256 buyAmount,
        address outerSellToken,
        address outerBuyToken,
        address receiver,
        address operator,
        bytes32 salt
    )
        internal
        returns (address cloneAddress)
    {
        uint32 validTo = uint32(block.timestamp + 1 hours);
        bytes memory creationArgs = abi.encodePacked(
            sellUnderlying,
            buyUnderlying,
            sellAmount,
            buyAmount,
            uint64(validTo),
            receiver,
            operator,
            outerSellToken,
            outerBuyToken,
            depthSell,
            depthBuy
        );
        cloneAddress = ClonesWithImmutableArgs.clone3(address(impl), creationArgs, salt);

        CoWSwapCloneWith4626 cloneInstance = CoWSwapCloneWith4626(cloneAddress);
        assertEq(cloneInstance.sellToken(), sellUnderlying, "Incorrect sell token (underlying)");
        assertEq(cloneInstance.buyToken(), buyUnderlying, "Incorrect buy token (underlying)");
        assertEq(cloneInstance.sellAmount(), sellAmount, "Incorrect sell amount");
        assertEq(cloneInstance.minBuyAmount(), buyAmount, "Incorrect min buy amount");
        assertEq(cloneInstance.validTo(), validTo, "Incorrect valid to");
        assertEq(cloneInstance.receiver(), receiver, "Incorrect receiver");
        assertEq(cloneInstance.operator(), operator, "Incorrect operator");
        assertEq(cloneInstance.outerSellToken(), outerSellToken, "Incorrect outer sell token");
        assertEq(cloneInstance.outerBuyToken(), outerBuyToken, "Incorrect outer buy token");
        assertEq(cloneInstance.sellDepth(), depthSell, "Incorrect sell depth");
        assertEq(cloneInstance.buyDepth(), depthBuy, "Incorrect buy depth");
    }

    function test_fuzz_cloneAndInitialize(
        address sellUnderlyingAddr,
        address buyUnderlyingAddr,
        uint8 depthSell,
        uint8 depthBuy,
        uint96 sAmount, // Using smaller uints for fuzzing amounts to avoid overflow with ether
        uint96 bAmount,
        address outerSellTokenAddr,
        address outerBuyTokenAddr,
        address receiverAddr,
        address operatorAddr,
        bytes32 salt
    )
        public
    {
        // Ensure distinct addresses for tokens to avoid mock issues
        vm.assume(sellUnderlyingAddr != address(0) && buyUnderlyingAddr != address(0));
        vm.assume(outerSellTokenAddr != address(0) && outerBuyTokenAddr != address(0));
        vm.assume(receiverAddr != address(0) && operatorAddr != address(0));
        vm.assume(sellUnderlyingAddr != buyUnderlyingAddr);
        vm.assume(outerSellTokenAddr != outerBuyTokenAddr);
        vm.assume(sellUnderlyingAddr != outerSellTokenAddr);

        ERC20Mock sellUnderlying = new ERC20Mock(); // Fresh mock for each fuzz run
        uint256 sellAmount = uint256(sAmount) * 1 ether;
        uint256 minBuyAmount = uint256(bAmount) * 1 ether;

        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellUnderlying),
            buyUnderlyingAddr,
            depthSell,
            depthBuy,
            sellAmount,
            minBuyAmount,
            outerSellTokenAddr,
            outerBuyTokenAddr,
            receiverAddr,
            operatorAddr,
            salt
        );

        // Test initialize
        uint256 allowanceBefore = IERC20(address(sellUnderlying)).allowance(cloneAddr, _VAULT_RELAYER);
        assertEq(allowanceBefore, 0, "Allowance should be 0 before initialization");

        vm.expectCall(
            address(sellUnderlying), abi.encodeWithSelector(IERC20.approve.selector, _VAULT_RELAYER, type(uint256).max)
        );
        vm.expectEmit();
        emit CoWSwapCloneWith4626.CoWSwapCloneCreated(
            address(sellUnderlying),
            buyUnderlyingAddr,
            sellAmount,
            minBuyAmount,
            CoWSwapCloneWith4626(cloneAddr).validTo(),
            receiverAddr,
            operatorAddr
        );
        CoWSwapCloneWith4626(cloneAddr).initialize();
        uint256 allowanceAfter = IERC20(address(sellUnderlying)).allowance(cloneAddr, _VAULT_RELAYER);
        assertEq(allowanceAfter, type(uint256).max, "Allowance should be max after initialization");
    }

    function _prepareVaults(
        uint8 depth,
        IERC20 underlying
    )
        private
        returns (ERC4626Mock currentVault, address[] memory path)
    {
        path = new address[](depth);
        if (depth == 0) return (ERC4626Mock(payable(address(0))), path);

        ERC20Mock tokenA = underlying == IERC20(address(0)) ? new ERC20Mock() : ERC20Mock(payable(address(underlying)));

        ERC4626Mock vaultA = new ERC4626Mock(tokenA, "VaultA0", "VA0", 18);
        path[depth - 1] = address(vaultA);
        currentVault = vaultA;

        for (uint8 i = 1; i < depth; ++i) {
            ERC4626Mock nextVault = new ERC4626Mock(
                IERC20(address(currentVault)),
                string(abi.encodePacked("VaultA", vm.toString(i))),
                string(abi.encodePacked("VA", vm.toString(i))),
                18
            );
            path[depth - 1 - i] = address(nextVault);
            currentVault = nextVault;
        }
    }

    function test_claim_wrapsTokens_MultiDepth() public {
        uint8 depth = 2;
        ERC20Mock sellUnderlying = new ERC20Mock();
        ERC20Mock buyUnderlying = new ERC20Mock();

        (ERC4626Mock outerSellVault,) = _prepareVaults(depth, sellUnderlying);
        (ERC4626Mock outerBuyVault,) = _prepareVaults(depth, buyUnderlying);

        uint256 sellAmount = 1000 ether;
        uint256 buyAmount = 500 ether;
        address receiver = payable(address(0xCAFEBABE));
        address operator = address(this);
        bytes32 salt = keccak256(abi.encodePacked("saltMultiDepth"));

        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellUnderlying),
            address(buyUnderlying),
            depth,
            depth,
            sellAmount,
            buyAmount,
            address(outerSellVault),
            address(outerBuyVault),
            receiver,
            operator,
            salt
        );

        sellUnderlying.mint(cloneAddr, sellAmount);
        buyUnderlying.mint(cloneAddr, buyAmount);

        vm.expectEmit();
        emit CoWSwapCloneWith4626.OrderClaimed(operator, sellAmount, buyAmount);

        vm.prank(operator);
        (uint256 claimedSell, uint256 claimedBuy) = CoWSwapCloneWith4626(cloneAddr).claim();

        assertEq(outerSellVault.balanceOf(receiver), sellAmount, "sell vault multi-depth share bal");
        assertEq(outerBuyVault.balanceOf(receiver), buyAmount, "buy vault multi-depth share bal");
        assertEq(claimedSell, sellAmount, "outer sell token amount returned");
        assertEq(claimedBuy, buyAmount, "outer buy token amount returned");
        assertEq(sellUnderlying.balanceOf(cloneAddr), 0);
        assertEq(buyUnderlying.balanceOf(cloneAddr), 0);
    }

    function test_claim_noWrapping_DepthZero() public {
        ERC20Mock sellToken = new ERC20Mock();
        ERC20Mock buyToken = new ERC20Mock();

        uint256 sellAmount = 100 ether;
        uint256 buyAmount = 20 ether;
        address receiver = payable(address(0x9ECe1fEBCaFE0000000000000000000000000000));
        address operator = address(this);
        bytes32 salt = keccak256(abi.encodePacked("saltDepthZero"));

        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellToken),
            address(buyToken),
            0, // sellDepth
            0, // buyDepth
            sellAmount,
            buyAmount,
            address(sellToken), // outerSellToken is same as underlying
            address(buyToken), // outerBuyToken is same as underlying
            receiver,
            operator,
            salt
        );

        sellToken.mint(cloneAddr, sellAmount);
        buyToken.mint(cloneAddr, buyAmount);

        vm.expectEmit();
        emit CoWSwapCloneWith4626.OrderClaimed(operator, sellAmount, buyAmount);

        vm.prank(operator);
        (uint256 claimedSell, uint256 claimedBuy) = CoWSwapCloneWith4626(cloneAddr).claim();

        assertEq(sellToken.balanceOf(receiver), sellAmount, "sell token (depth 0) balance");
        assertEq(buyToken.balanceOf(receiver), buyAmount, "buy token (depth 0) balance");
        assertEq(claimedSell, sellAmount, "outer sell token amount returned");
        assertEq(claimedBuy, buyAmount, "outer buy token amount returned");
        assertEq(sellToken.balanceOf(cloneAddr), 0);
        assertEq(buyToken.balanceOf(cloneAddr), 0);
    }

    function test_claim_onlySellTokens_depthOne() public {
        ERC20Mock sellUnderlying = new ERC20Mock();
        ERC4626Mock sellVault = new ERC4626Mock(sellUnderlying, "SV", "SV", 18);
        ERC20Mock buyTokenPlaceholder = new ERC20Mock(); // Will have 0 balance in clone

        uint256 sellAmount = 777 ether;
        address receiver = payable(makeAddr("Alice"));
        address operator = address(this);
        bytes32 salt = keccak256(abi.encodePacked("saltOnlySell"));

        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellUnderlying),
            address(buyTokenPlaceholder), // Underlying buy token
            1, // sellDepth
            0, // buyDepth (expecting underlying placeholder)
            sellAmount,
            0, // minBuyAmount for order, but we're testing claim of residual sell
            address(sellVault), // outerSellToken
            address(buyTokenPlaceholder), // outerBuyToken
            receiver,
            operator,
            salt
        );

        sellUnderlying.mint(cloneAddr, sellAmount);
        // No buy tokens minted to cloneAddr

        vm.expectEmit();
        // Expect buyAmount to be 0 as none were in the clone for buyTokenPlaceholder
        emit CoWSwapCloneWith4626.OrderClaimed(operator, sellAmount, 0);

        vm.prank(operator);
        (uint256 claimedSell, uint256 claimedBuy) = CoWSwapCloneWith4626(cloneAddr).claim();

        assertEq(claimedSell, sellAmount, "outer sell token amount returned");
        assertEq(claimedBuy, 0, "Claimed buy (zero balance)");
        assertEq(sellVault.balanceOf(receiver), sellAmount, "Sell vault shares for receiver");
        assertEq(buyTokenPlaceholder.balanceOf(receiver), 0, "Buy placeholder for receiver");
        assertEq(sellUnderlying.balanceOf(cloneAddr), 0);
    }

    function test_claim_onlyBuyTokens_depthOne() public {
        ERC20Mock sellTokenPlaceholder = new ERC20Mock(); // Will have 0 balance
        ERC20Mock buyUnderlying = new ERC20Mock();
        ERC4626Mock buyVault = new ERC4626Mock(buyUnderlying, "BV", "BV", 18);

        uint256 buyAmount = 888 ether;
        address receiver = payable(makeAddr("Bob"));
        address operator = address(this);
        bytes32 salt = keccak256(abi.encodePacked("saltOnlyBuy"));

        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellTokenPlaceholder), // Underlying sell token
            address(buyUnderlying), // Underlying buy token
            0, // sellDepth
            1, // buyDepth
            0, // sellAmount for order
            buyAmount, // minBuyAmount for order
            address(sellTokenPlaceholder), // outerSellToken
            address(buyVault), // outerBuyToken
            receiver,
            operator,
            salt
        );

        buyUnderlying.mint(cloneAddr, buyAmount);
        // No sell tokens minted

        vm.expectEmit();
        emit CoWSwapCloneWith4626.OrderClaimed(operator, 0, buyAmount);

        vm.prank(operator);
        (uint256 claimedSell, uint256 claimedBuy) = CoWSwapCloneWith4626(cloneAddr).claim();

        assertEq(claimedSell, 0, "Claimed sell (depth 0, zero balance)");
        assertEq(claimedBuy, buyAmount, "Claimed buy (depth 1)");
        assertEq(sellTokenPlaceholder.balanceOf(receiver), 0, "Sell placeholder for receiver");
        assertEq(buyVault.balanceOf(receiver), buyAmount, "Buy vault shares for receiver");
        assertEq(buyUnderlying.balanceOf(cloneAddr), 0);
    }

    function test_revert_claim_notOperatorOrReceiver() public {
        ERC20Mock sellToken = new ERC20Mock();
        ERC20Mock buyToken = new ERC20Mock();
        address receiver = payable(address(0x9EcE1FEbCaFE0000000000000000000000000001));
        address operator = payable(address(0x09e7a702feFe0000000000000000000000000002));
        address attacker = payable(address(0xBadAC702dEAD0000000000000000000000000003));
        vm.assume(attacker != receiver && attacker != operator);

        bytes32 salt = keccak256(abi.encodePacked("saltRevertClaim"));
        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellToken),
            address(buyToken),
            0,
            0,
            100,
            100,
            address(sellToken),
            address(buyToken),
            receiver,
            operator,
            salt
        );

        vm.prank(attacker);
        vm.expectRevert(CoWSwapCloneWith4626.CallerIsNotOperatorOrReceiver.selector);
        CoWSwapCloneWith4626(cloneAddr).claim();
    }

    function _getOrderData(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmountOrder, // Actual buy amount for order, can be >= minBuyAmount in clone
        uint32 validTo,
        address orderReceiver // This is the receiver in GPv2Order.Data, should be cloneAddr
    )
        internal
        pure
        returns (GPv2Order.Data memory)
    {
        return GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: orderReceiver,
            sellAmount: sellAmount,
            buyAmount: buyAmountOrder,
            validTo: validTo,
            appData: 0,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    function test_isValidSignature_basic() public {
        ERC20Mock sellUnderlying = new ERC20Mock();
        ERC20Mock buyUnderlying = new ERC20Mock();
        uint256 sellAmount = 100 ether;
        uint256 minBuyAmount = 50 ether; // For clone storage
        uint256 orderBuyAmount = 55 ether; // Actual amount for the GPv2Order.Data
        address receiver = address(this); // For clone
        address operator = address(this); // For clone
        bytes32 salt = keccak256(abi.encodePacked("saltSig"));

        address cloneAddr = _deployCloneAndAssertArgs(
            address(sellUnderlying),
            address(buyUnderlying),
            0, // depthSell
            0, // depthBuy
            sellAmount,
            minBuyAmount,
            address(sellUnderlying), // outerSellToken
            address(buyUnderlying), // outerBuyToken
            receiver, // clone's receiver for claimed tokens
            operator,
            salt
        );

        CoWSwapCloneWith4626 cloneInstance = CoWSwapCloneWith4626(cloneAddr);
        GPv2Order.Data memory order = _getOrderData(
            address(sellUnderlying),
            address(buyUnderlying),
            sellAmount,
            orderBuyAmount, // Using orderBuyAmount for the GPv2Order struct
            cloneInstance.validTo(),
            cloneAddr // The order receiver is the clone contract itself
        );
        bytes32 orderDigest = order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR);

        assertEq(
            cloneInstance.isValidSignature(orderDigest, abi.encode(order)),
            _ERC1271_MAGIC_VALUE,
            "Invalid signature magic value"
        );
    }
}

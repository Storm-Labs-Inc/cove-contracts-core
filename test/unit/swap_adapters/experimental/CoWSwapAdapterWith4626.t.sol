// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { CoWSwapAdapterWith4626 } from "src/swap_adapters/experimental/CoWSwapAdapterWith4626.sol";
import { CoWSwapCloneWith4626 } from "src/swap_adapters/experimental/CoWSwapCloneWith4626.sol";
import { BasketTradeOwnership, ExternalTrade } from "src/types/Trades.sol";

import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "test/utils/mocks/ERC4626Mock.sol";

contract CoWSwapAdapterWith4626Test is BaseTest {
    CoWSwapAdapterWith4626 private adapter;
    address internal cloneImpl;

    uint32 internal constant DEFAULT_VALID_TO_OFFSET = 60 minutes;
    address internal constant COW_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    function setUp() public override {
        super.setUp();
        cloneImpl = address(new CoWSwapCloneWith4626());
        adapter = new CoWSwapAdapterWith4626(cloneImpl);
    }

    function _prepareTradeAndOpts(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint8 depthSell,
        uint8 depthBuy
    )
        internal
        pure
        returns (ExternalTrade[] memory trades, bytes memory extraData)
    {
        trades = new ExternalTrade[](1);
        trades[0] = ExternalTrade({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            minAmount: minBuyAmount,
            basketTradeOwnership: new BasketTradeOwnership[](0)
        });

        CoWSwapAdapterWith4626.UnderlyingOptions[] memory opts = new CoWSwapAdapterWith4626.UnderlyingOptions[](1);
        opts[0] =
            CoWSwapAdapterWith4626.UnderlyingOptions({ underlyingDepthSell: depthSell, underlyingDepthBuy: depthBuy });
        extraData = abi.encode(opts);
    }

    function _mockRedeem(
        ERC4626Mock vault,
        ERC20Mock underlying,
        uint256 sharesToRedeem,
        uint256 assetsToReceive
    )
        internal
    {
        // Ensure vault has enough underlying to transfer out if its actual redeem were called.
        // For a mocked redeem, this ensures any subsequent logic that might check vault balance (not typical) sees it.
        deal(address(underlying), address(vault), assetsToReceive);

        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.redeem.selector, sharesToRedeem, address(adapter), address(adapter)), // owner
                // is adapter
            abi.encode(assetsToReceive)
        );
    }

    function _mockConvertToAssets(ERC4626Mock vault, uint256 shares, uint256 assets) internal {
        vm.mockCall(
            address(vault), abi.encodeWithSelector(IERC4626.convertToAssets.selector, shares), abi.encode(assets)
        );
    }

    function test_execute_redeemSell_noBuyConvert() public {
        ERC20Mock sellUnderlying = new ERC20Mock();
        ERC4626Mock sellVault = new ERC4626Mock(sellUnderlying, "SV", "SV", 18);
        ERC20Mock buyToken = new ERC20Mock();

        uint256 sellShares = 100 ether;
        uint256 underlyingSellAmount = 95 ether; // e.g. after fees
        uint256 minBuyAmount = 50 ether;

        deal(address(sellVault), address(adapter), sellShares); // Adapter has shares to redeem
        // Vault needs underlying to give on redeem
        sellUnderlying.mint(address(sellVault), underlyingSellAmount);

        (ExternalTrade[] memory trades, bytes memory extraData) =
            _prepareTradeAndOpts(address(sellVault), address(buyToken), sellShares, minBuyAmount, 1, 0);

        uint32 validTo = uint32(block.timestamp + DEFAULT_VALID_TO_OFFSET);
        bytes32 salt =
            keccak256(abi.encodePacked(address(sellVault), address(buyToken), sellShares, minBuyAmount, validTo));
        address predictedClone = _predictDeterministicAddress(salt, address(adapter));

        // Mocks for _handleSellToken
        _mockRedeem(sellVault, sellUnderlying, sellShares, underlyingSellAmount);
        // After the mocked redeem, adapter should have the underlying. Deal it explicitly.
        deal(address(sellUnderlying), address(adapter), underlyingSellAmount);
        deal(address(sellUnderlying), address(sellVault), 0);

        // Mocks for _createOrder (transfer to clone, approve relayer)
        vm.mockCall(
            address(sellUnderlying),
            abi.encodeWithSelector(IERC20.transfer.selector, predictedClone, underlyingSellAmount),
            abi.encode(true)
        );
        vm.mockCall(
            address(sellUnderlying),
            abi.encodeWithSelector(IERC20.approve.selector, COW_RELAYER, type(uint256).max),
            abi.encode(true)
        );

        vm.expectEmit();
        emit CoWSwapAdapterWith4626.OrderCreated(
            address(sellVault), // Outer sell token
            address(buyToken), // Outer buy token
            sellShares, // Outer sell amount
            minBuyAmount, // Outer buy amount
            validTo,
            predictedClone
        );
        adapter.executeTokenSwap(trades, extraData);
    }

    function test_execute_noSellRedeem_convertBuy() public {
        ERC20Mock sellToken = new ERC20Mock();
        ERC20Mock buyUnderlying = new ERC20Mock();
        ERC4626Mock buyVault = new ERC4626Mock(buyUnderlying, "BV", "BV", 18);

        uint256 sellAmount = 100 ether;
        uint256 minBuyShares = 50 ether;
        uint256 underlyingBuyAmount = 45 ether; // after conversion

        deal(address(sellToken), address(adapter), sellAmount);

        (ExternalTrade[] memory trades, bytes memory extraData) =
            _prepareTradeAndOpts(address(sellToken), address(buyVault), sellAmount, minBuyShares, 0, 1);

        uint32 validTo = uint32(block.timestamp + DEFAULT_VALID_TO_OFFSET);
        bytes32 salt =
            keccak256(abi.encodePacked(address(sellToken), address(buyVault), sellAmount, minBuyShares, validTo));
        address predictedClone = _predictDeterministicAddress(salt, address(adapter));

        // Mocks for _handleBuyToken
        _mockConvertToAssets(buyVault, minBuyShares, underlyingBuyAmount);

        // Mocks for _createOrder
        vm.mockCall(
            address(sellToken),
            abi.encodeWithSelector(IERC20.transfer.selector, predictedClone, sellAmount),
            abi.encode(true)
        );
        vm.mockCall(
            address(sellToken), // Sell token is directly used for approval as no redemption
            abi.encodeWithSelector(IERC20.approve.selector, COW_RELAYER, type(uint256).max),
            abi.encode(true)
        );

        vm.expectEmit();
        emit CoWSwapAdapterWith4626.OrderCreated(
            address(sellToken), // Outer sell token (no redemption)
            address(buyVault), // Outer buy token
            sellAmount, // Outer sell amount
            minBuyShares, // Outer buy amount
            validTo,
            predictedClone
        );
        adapter.executeTokenSwap(trades, extraData);
    }

    function test_execute_multiDepth_redeemAndConvert() public {
        ERC20Mock sellL2 = new ERC20Mock(); // Deepest sell underlying
        ERC4626Mock sellL1 = new ERC4626Mock(sellL2, "SL1", "SL1", 18);
        ERC4626Mock sellVault = new ERC4626Mock(sellL1, "SV", "SV", 18); // Outer sell

        ERC20Mock buyL2 = new ERC20Mock(); // Deepest buy underlying
        ERC4626Mock buyL1 = new ERC4626Mock(buyL2, "BL1", "BL1", 18);
        ERC4626Mock buyVault = new ERC4626Mock(buyL1, "BV", "BV", 18); // Outer buy

        uint256 sellSharesOuter = 100 ether;
        uint256 sellSharesL1 = 98 ether;
        uint256 sellUnderlyingL2Amount = 95 ether;

        uint256 minBuySharesOuter = 50 ether;
        uint256 minBuySharesL1 = 48 ether;
        uint256 buyUnderlyingL2Amount = 45 ether;

        deal(address(sellVault), address(adapter), sellSharesOuter);
        // Vaults need their respective underlying assets to be able to be redeemed from.
        // _mockRedeem will deal these amounts to the vaults before mocking the redeem call.

        (ExternalTrade[] memory trades, bytes memory extraData) =
            _prepareTradeAndOpts(address(sellVault), address(buyVault), sellSharesOuter, minBuySharesOuter, 2, 2);

        uint32 validTo = uint32(block.timestamp + DEFAULT_VALID_TO_OFFSET);
        bytes32 salt = keccak256(
            abi.encodePacked(address(sellVault), address(buyVault), sellSharesOuter, minBuySharesOuter, validTo)
        );
        address predictedClone = _predictDeterministicAddress(salt, address(adapter));

        // Mocks for _handleSellToken (2 levels of redeem)
        _mockRedeem(sellVault, ERC20Mock(address(sellL1)), sellSharesOuter, sellSharesL1);
        deal(address(sellL1), address(adapter), sellSharesL1); // Adapter gets L1 shares from sellVault.redeem
        deal(address(sellL1), address(sellVault), 0); // sellVault no longer has L1 shares

        _mockRedeem(sellL1, sellL2, sellSharesL1, sellUnderlyingL2Amount);
        deal(address(sellL2), address(adapter), sellUnderlyingL2Amount); // Adapter gets L2 underlying from
            // sellL1.redeem
        deal(address(sellL2), address(sellL1), 0); // sellL1 no longer has L2 underlying

        // Mocks for _handleBuyToken (2 levels of convertToAssets)
        _mockConvertToAssets(buyVault, minBuySharesOuter, minBuySharesL1);
        _mockConvertToAssets(buyL1, minBuySharesL1, buyUnderlyingL2Amount);

        // Mocks for _createOrder
        vm.mockCall(
            address(sellL2), // Deepest sell underlying is transferred
            abi.encodeWithSelector(IERC20.transfer.selector, predictedClone, sellUnderlyingL2Amount),
            abi.encode(true)
        );
        vm.mockCall(
            address(sellL2),
            abi.encodeWithSelector(IERC20.approve.selector, COW_RELAYER, type(uint256).max),
            abi.encode(true)
        );

        vm.expectEmit();
        emit CoWSwapAdapterWith4626.OrderCreated(
            address(sellVault), // Outer sell
            address(buyVault), // Outer buy
            sellSharesOuter, // Expected sell in outer sell
            minBuySharesOuter, // Expected buy in outer buy
            validTo,
            predictedClone
        );
        adapter.executeTokenSwap(trades, extraData);
    }

    function test_execute_emptyExtraData() public {
        ERC20Mock sellToken = new ERC20Mock();
        ERC20Mock buyToken = new ERC20Mock();
        uint256 sellAmount = 100 ether;
        uint256 minBuyAmount = 50 ether;

        deal(address(sellToken), address(adapter), sellAmount);

        ExternalTrade[] memory trades = new ExternalTrade[](1);
        trades[0] = ExternalTrade({
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            sellAmount: sellAmount,
            minAmount: minBuyAmount,
            basketTradeOwnership: new BasketTradeOwnership[](0)
        });

        uint32 validTo = uint32(block.timestamp + DEFAULT_VALID_TO_OFFSET);
        bytes32 salt =
            keccak256(abi.encodePacked(address(sellToken), address(buyToken), sellAmount, minBuyAmount, validTo));
        address predictedClone = _predictDeterministicAddress(salt, address(adapter));

        // No underlying options, so direct transfer and approve
        vm.mockCall(
            address(sellToken),
            abi.encodeWithSelector(IERC20.transfer.selector, predictedClone, sellAmount),
            abi.encode(true)
        );
        vm.mockCall(
            address(sellToken),
            abi.encodeWithSelector(IERC20.approve.selector, COW_RELAYER, type(uint256).max),
            abi.encode(true)
        );

        vm.expectRevert(CoWSwapAdapterWith4626.OptLengthMismatch.selector);
        adapter.executeTokenSwap(trades, ""); // Empty extraData
    }

    function test_revert_optsLengthMismatch() public {
        ExternalTrade[] memory trades = new ExternalTrade[](1); // 1 trade
        CoWSwapAdapterWith4626.UnderlyingOptions[] memory opts = new CoWSwapAdapterWith4626.UnderlyingOptions[](2); // 2
            // options
        bytes memory extraData = abi.encode(opts);
        vm.expectRevert(CoWSwapAdapterWith4626.OptLengthMismatch.selector);
        adapter.executeTokenSwap(trades, extraData);
    }

    // function test_revert_depthSellZero_withShouldTrade() public {
    //     (ExternalTrade[] memory trades, bytes memory extraData) = _prepareTradeAndOpts(
    //         address(0x1), address(0x2), 100, 50, 0, 0
    //     );
    //     vm.expectRevert(bytes("CoWSwapAdapter4626: depthSell zero"));
    //     adapter.executeTokenSwap(trades, extraData);
    // }

    // function test_revert_depthBuyZero_withShouldTrade() public {
    //     (ExternalTrade[] memory trades, bytes memory extraData) = _prepareTradeAndOpts(
    //         address(0x1), address(0x2), 100, 50, 0, 0 // shouldTradeBuy=true, depthBuy=0
    //     );
    //     vm.expectRevert(bytes("CoWSwapAdapter4626: depthBuy zero"));
    //     adapter.executeTokenSwap(trades, extraData);
    // }

    function test_completeTokenSwap_basic() public {
        ERC20Mock sellToken = new ERC20Mock();
        ERC20Mock buyToken = new ERC20Mock();
        uint256 sellAmount = 200 ether;
        uint256 minBuyAmount = 100 ether;

        deal(address(sellToken), address(adapter), sellAmount);

        (ExternalTrade[] memory trades, bytes memory extraData) =
            _prepareTradeAndOpts(address(sellToken), address(buyToken), sellAmount, minBuyAmount, 0, 0);
        bytes32 salt = keccak256(
            abi.encodePacked(
                address(sellToken),
                address(buyToken),
                sellAmount,
                minBuyAmount,
                uint32(vm.getBlockTimestamp() + DEFAULT_VALID_TO_OFFSET)
            ) // Use stored orderValidTo via getter
        );
        address predictedClone = _predictDeterministicAddress(salt, address(adapter));
        vm.expectEmit();
        emit CoWSwapAdapterWith4626.OrderCreated(
            address(sellToken),
            address(buyToken),
            sellAmount,
            minBuyAmount,
            uint32(vm.getBlockTimestamp() + DEFAULT_VALID_TO_OFFSET),
            predictedClone
        );

        // Execute first to set up the orderValidTo and potentially create clone
        adapter.executeTokenSwap(trades, extraData);

        // Mock the claim call on the clone
        vm.mockCall(
            predictedClone,
            abi.encodeWithSelector(CoWSwapCloneWith4626.claim.selector),
            abi.encode(sellAmount, minBuyAmount) // Mocked return values from claim
        );

        vm.expectEmit();
        emit CoWSwapAdapterWith4626.TokenSwapCompleted(
            address(sellToken), address(buyToken), sellAmount, minBuyAmount, predictedClone
        );

        uint256[2][] memory claimedAmounts = adapter.completeTokenSwap(trades);
        assertEq(claimedAmounts[0][0], sellAmount, "claimed sell");
        assertEq(claimedAmounts[0][1], minBuyAmount, "claimed buy");
    }
}

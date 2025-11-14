// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

import { CoWSwapAdapterWithAppData } from "src/swap_adapters/CoWSwapAdapterWithAppData.sol";
import { CoWSwapCloneWithAppData } from "src/swap_adapters/CoWSwapCloneWithAppData.sol";
import { BasketTradeOwnership, ExternalTrade } from "src/types/Trades.sol";

contract CoWSwapAdapterWithAppDataTest is BaseTest {
    CoWSwapAdapterWithAppData private adapter;
    CoWSwapCloneWithAppData private implementation;

    ERC20Mock private sellToken;
    ERC20Mock private buyToken;

    bytes32 internal constant _APP_DATA = STAGING_COWSWAP_APPDATA_HASH;
    bytes32 internal constant _ORDER_CREATED_SIGNATURE =
        keccak256("OrderCreated(address,address,uint256,uint256,uint32,address)");

    function setUp() public override {
        implementation = new CoWSwapCloneWithAppData();
        adapter = new CoWSwapAdapterWithAppData(address(implementation), _APP_DATA);
        sellToken = new ERC20Mock();
        buyToken = new ERC20Mock();
    }

    function test_constructor_setsImmutableAppData() public {
        assertEq(adapter.cloneImplementation(), address(implementation), "Incorrect clone implementation");
        assertEq(adapter.appDataHash(), _APP_DATA, "Incorrect appData hash");
    }

    function test_constructor_revertWhen_AppDataIsZero() public {
        vm.expectRevert(CoWSwapAdapterWithAppData.InvalidAppDataHash.selector);
        new CoWSwapAdapterWithAppData(address(implementation), bytes32(0));
    }

    function test_executeTokenSwap_propagatesAppDataHash() public {
        uint256 sellAmount = 1e18;
        uint256 minAmount = 5e17;

        ExternalTrade[] memory trades = new ExternalTrade[](1);
        trades[0] = ExternalTrade({
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            sellAmount: sellAmount,
            minAmount: minAmount,
            basketTradeOwnership: new BasketTradeOwnership[](0)
        });

        deal(address(sellToken), address(adapter), sellAmount);

        vm.warp(1_000_000);
        vm.recordLogs();
        adapter.executeTokenSwap(trades, "");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        address swapContract;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(adapter) || logs[i].topics.length == 0) {
                continue;
            }
            if (logs[i].topics[0] != _ORDER_CREATED_SIGNATURE) {
                continue;
            }
            (, uint256 buyAmount,, address emittedSwapContract) =
                abi.decode(logs[i].data, (uint256, uint256, uint32, address));
            assertEq(buyAmount, minAmount, "Incorrect event min amount");
            swapContract = emittedSwapContract;
            break;
        }

        assertTrue(swapContract != address(0), "swapContract not emitted");
        assertEq(CoWSwapCloneWithAppData(swapContract).appDataHash(), _APP_DATA, "Incorrect clone appData hash");
        assertEq(IERC20(address(sellToken)).balanceOf(swapContract), sellAmount, "Incorrect sell token transferred");
    }
}

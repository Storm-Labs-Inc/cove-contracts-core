// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { TokenSwapAdapter } from "./TokenSwapAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";
import { Errors } from "src/libraries/Errors.sol";

import { MilkBoy } from "src/swap_adapters/MilkBoy.sol";
import { ExternalTrade } from "src/types/Trades.sol";

contract MilkBoyAdapter is TokenSwapAdapter {
    using GPv2Order for GPv2Order.Data;

    bytes32 internal constant _DOMAIN_SEPARATOR = 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    bytes32 internal constant _MILKBOY_ADAPTER_STORAGE =
        bytes32(uint256(keccak256("cove.basketmanager.milkboyadapter.storage")) - 1);

    error ERC1271NotImplemented();

    address public immutable milkboyImplementation;

    constructor(address milkboyImplementation_) {
        if (milkboyImplementation_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        milkboyImplementation = milkboyImplementation_;
    }

    struct MilkBoyAdapterStorage {
        uint32 orderValidTo;
        mapping(bytes32 => bool) isOrderValid;
    }

    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata
    )
        external
        override
        returns (bytes32[] memory hashes)
    {
        // MilkBoyAdapterStorage storage S = _milkBoyAdapterStorage();
        uint256 validTo = block.timestamp + 15 minutes;
        // TODO: emit events for each trade
        for (uint256 i = 0; i < externalTrades.length; i++) {
            _createOrder(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                externalTrades[i].sellAmount,
                externalTrades[i].minAmount,
                validTo
            );
        }
    }

    function isValidSignature(bytes32, bytes calldata) external pure override returns (bytes4) {
        revert ERC1271NotImplemented();
    }

    function _createOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 validTo
    )
        internal
    {
        // Create the order with the receiver being the cloned contract
        bytes32 salt = keccak256(abi.encode(sellToken, buyToken, sellAmount, buyAmount, validTo));
        address swapContract = ClonesWithImmutableArgs.addressOfClone3(salt);
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: swapContract,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: uint32(validTo),
            appData: 0,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        ClonesWithImmutableArgs.clone3(
            milkboyImplementation,
            abi.encodePacked(
                order.hash(_DOMAIN_SEPARATOR),
                order.sellToken,
                order.buyToken,
                order.sellAmount,
                order.buyAmount,
                address(this),
                address(this)
            ),
            salt
        );
        IERC20(sellToken).transfer(swapContract, sellAmount);
        MilkBoy(swapContract).initialize();
    }

    function _milkBoyAdapterStorage() internal pure returns (MilkBoyAdapterStorage storage s) {
        bytes32 slot = _MILKBOY_ADAPTER_STORAGE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { TokenSwapAdapter } from "./TokenSwapAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";
import { Errors } from "src/libraries/Errors.sol";
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
        MilkBoyAdapterStorage storage S = _milkBoyAdapterStorage();
        uint256 validTo = block.timestamp + 15 minutes;
        // TODO: emit events for each trade
        for (uint256 i = 0; i < externalTrades.length; i++) {
            bytes32 salt = keccak256(abi.encode(externalTrades[i]));
            GPv2Order.Data memory order = GPv2Order.Data({
                sellToken: IERC20(externalTrades[i].sellToken),
                buyToken: IERC20(externalTrades[i].buyToken),
                receiver: ClonesWithImmutableArgs.addressOfClone3(salt),
                sellAmount: externalTrades[i].sellAmount,
                buyAmount: externalTrades[i].minAmount,
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
                    order.validTo,
                    order.receiver
                ),
                salt
            );
        }
    }

    function isValidSignature(bytes32, bytes calldata) external pure override returns (bytes4) {
        revert ERC1271NotImplemented();
    }

    function _milkBoyAdapterStorage() internal pure returns (MilkBoyAdapterStorage storage S) {
        bytes32 slot = _MILKBOY_ADAPTER_STORAGE;
        assembly {
            S.slot := slot
        }
    }
}

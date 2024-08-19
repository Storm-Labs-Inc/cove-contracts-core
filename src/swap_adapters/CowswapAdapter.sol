// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { TokenSwapAdapter } from "./TokenSwapAdapter.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";
import { ExternalTrade } from "src/types/Trades.sol";

contract CowswapAdapter is TokenSwapAdapter {
    bytes32 internal constant _DOMAIN_SEPARATOR = 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    /// @dev Magic value for ERC1271 signature validation.
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    /// @dev Non-magic value for ERC1271 signature validation.
    bytes4 internal constant _ERC1271_NON_MAGIC_VALUE = 0xffffffff;
    bytes32 internal constant _COWSWAP_ADAPTER_STORAGE =
        bytes32(uint256(keccak256("cove.basketmanager.cowswapadapter.storage")) - 1);

    error OrderDigestMismatch(bytes32 calculatedDigest, bytes32 providedDigest);
    error OrderNotSellKind(bytes32 providedKind);
    error OrderExpirationMismatch(uint32 validTo, uint256 currentTimestamp);
    error OrderNotFillOrKill();
    error OrderSellTokenBalanceNotERC20(bytes32 providedBalance);
    error OrderBuyTokenBalanceNotERC20(bytes32 providedBalance);
    error OrderInvalidBuyAmount(uint256 buyAmount);
    error OrderReceiverNotThis(address providedReceiver);

    struct CowswapAdapterStorage {
        uint32 orderValidTo;
        mapping(bytes32 => bool) isOrderValid;
    }

    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata data
    )
        external
        override
        returns (bytes32[] memory hashes)
    {
        CowswapAdapterStorage storage S = _cowswapAdapterStorage();
        // TODO: emit events for each trade
        // TODO: save hashes of each external trade to verify later
        S.orderValidTo = block.timestamp + 15 minutes;
    }

    function isValidSignature(
        bytes32 orderDigest,
        bytes calldata encodedOrder
    )
        external
        view
        override
        returns (bytes4)
    {
        CowswapAdapterStorage storage S = _cowswapAdapterStorage();
        // TODO: include some sources of our own hash in the encoded order. This could be min amount then reconstruct
        // the hash with _order
        (GPv2Order.Data memory _order, uint256 minAmount) = _decodeOrder(encodedOrder);

        if (_order.hash(_DOMAIN_SEPARATOR) != orderDigest) {
            revert OrderDigestMismatch(_order.hash(_DOMAIN_SEPARATOR), orderDigest);
        }

        if (_order.kind != GPv2Order.KIND_SELL) revert OrderNotSellKind(_order.kind);

        if (_order.validTo != S.orderValidTo) {
            revert OrderExpirationMismatch(_order.validTo, S.orderValidTo);
        }

        if (_order.partiallyFillable) revert OrderNotFillOrKill();

        if (_order.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert OrderSellTokenBalanceNotERC20(_order.sellTokenBalance);
        }

        if (_order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert OrderBuyTokenBalanceNotERC20(_order.buyTokenBalance);
        }

        if (_order.receiver != address(this)) {
            revert OrderReceiverNotThis(_order.receiver);
        }

        if (_order.buyAmount > minAmount) revert OrderInvalidBuyAmount(_order.buyAmount);

        // TODO: check against proposed hash
        bytes32 calculatedSwapHash =
            keccak256(abi.encode(_order.sellToken, _order.buyToken, _order.sellAmount.add(_order.feeAmount), minAmount));

        if (isOrderValid[calculatedSwapHash]) {
            // should be true as long as the keeper isn't submitting bad orders
            return _ERC1271_MAGIC_VALUE;
        } else {
            return _ERC1271_NON_MAGIC_VALUE;
        }
    }

    /// @notice Decodes an order from its encoded form
    /// @param encodedOrder The encoded order
    /// @return order
    /// @return minAmount proposed minAmount that was used to hash the order
    function _decodeOrder(
        bytes calldata encodedOrder
    )
        internal
        pure
        returns (GPv2Order.Data memory order, uint256 minAmount)
    {
        return abi.decode(encodedOrder, (GPv2Order.Data, uint256));
    }

    function _cowswapAdapterStorage() internal pure returns (CowswapAdapterStorage storage S) {
        bytes32 slot = _COWSWAP_ADAPTER_STORAGE;
        assembly {
            S.slot := slot
        }
    }
}

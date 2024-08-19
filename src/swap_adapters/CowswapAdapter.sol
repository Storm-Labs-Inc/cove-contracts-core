// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { TokenSwapAdapter } from "./TokenSwapAdapter.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

contract CowswapAdapter is TokenSwapAdapter {
    function isValidSignature(
        bytes32 orderDigest,
        bytes calldata encodedOrder
    )
        external
        view
        override
        returns (bytes4)
    {
        (GPv2Order.Data memory _order, address _orderCreator, address _priceChecker, bytes memory _priceCheckerData) =
            decodeOrder(encodedOrder);

        require(_order.hash(DOMAIN_SEPARATOR) == orderDigest, "!match");

        require(_order.kind == GPv2Order.KIND_SELL, "!kind_sell");

        require(_order.validTo >= block.timestamp + 5 minutes, "expires_too_soon");

        require(!_order.partiallyFillable, "!fill_or_kill");

        require(_order.sellTokenBalance == GPv2Order.BALANCE_ERC20, "!sell_erc20");

        require(_order.buyTokenBalance == GPv2Order.BALANCE_ERC20, "!buy_erc20");

        // TODO: check against proposed minAmount
        require(_order.buyAmount > 0, "invalid_min_out");

        // TODO: check against proposed hash
        bytes32 _calculatedSwapHash = keccak256(
            abi.encode(
                _orderCreator,
                _order.receiver,
                _order.sellToken,
                _order.buyToken,
                _order.sellAmount.add(_order.feeAmount),
                _priceChecker,
                _priceCheckerData
            )
        );

        if (isOrderValid[_calculatedSwapHash]) {
            // should be true as long as the keeper isn't submitting bad orders
            return _ERC1271_MAGIC_VALUE;
        } else {
            return _ERC1271_NON_MAGIC_VALUE;
        }
    }
}

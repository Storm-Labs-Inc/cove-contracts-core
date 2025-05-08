// SPDX-License-Identifier: BUSL-1.1
// solhint-disable one-contract-per-file
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

/// @title CoWSwapOrderDecoder
/// @notice A simple proof of concept contract for decoding CoWSwap orders
contract CoWSwapOrderDecoder is Test {
    using GPv2Order for GPv2Order.Data;

    /// @dev The domain separator of GPv2Settlement contract used for orderDigest calculation.
    bytes32 internal constant COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    /// @notice Decodes a CoWSwap order and logs its details
    /// @param orderDigest The digest of the order to validate
    /// @param encodedOrder The encoded order data
    function decodeAndLogOrder(bytes32 orderDigest, bytes calldata encodedOrder) external {
        GPv2Order.Data memory order = abi.decode(encodedOrder, (GPv2Order.Data));

        // Log order details
        console.log("Order Details:");
        console.log("-------------");
        console.log("Order Digest:", vm.toString(orderDigest));
        console.log("Computed Digest:", vm.toString(order.hash(COW_SETTLEMENT_DOMAIN_SEPARATOR)));
        console.log("Sell Token:", address(order.sellToken));
        console.log("Buy Token:", address(order.buyToken));
        console.log("Receiver:", order.receiver);
        console.log("Sell Amount:", order.sellAmount);
        console.log("Buy Amount:", order.buyAmount);
        console.log("Valid To:", order.validTo);
        console.log("App Data:", vm.toString(order.appData));
        console.log("Fee Amount:", order.feeAmount);

        // Log order flags
        console.log(
            "Order Kind:",
            order.kind == GPv2Order.KIND_SELL ? "SELL" : order.kind == GPv2Order.KIND_BUY ? "BUY" : "UNKNOWN"
        );
        console.log("Partially Fillable:", order.partiallyFillable);

        // Log token balance types
        string memory sellTokenBalanceType = getBalanceTypeName(order.sellTokenBalance);
        string memory buyTokenBalanceType = getBalanceTypeName(order.buyTokenBalance);
        console.log("Sell Token Balance Type:", sellTokenBalanceType);
        console.log("Buy Token Balance Type:", buyTokenBalanceType);

        // Validate if the provided orderDigest matches the computed one
        bool isValidDigest = orderDigest == order.hash(COW_SETTLEMENT_DOMAIN_SEPARATOR);
        console.log("Is Valid Digest:", isValidDigest);
    }

    /// @notice Helper function to get the human-readable name of a balance type
    /// @param balanceType The balance type bytes32 value
    /// @return The human-readable name of the balance type
    function getBalanceTypeName(bytes32 balanceType) internal pure returns (string memory) {
        if (balanceType == GPv2Order.BALANCE_ERC20) {
            return "ERC20";
        } else if (balanceType == GPv2Order.BALANCE_EXTERNAL) {
            return "EXTERNAL";
        } else if (balanceType == GPv2Order.BALANCE_INTERNAL) {
            return "INTERNAL";
        } else {
            return "UNKNOWN";
        }
    }
}

/// @title CoWSwapOrderDecoderTest
/// @notice Test contract for the CoWSwapOrderDecoder
contract CoWSwapOrderDecoderTest is Test {
    using GPv2Order for GPv2Order.Data;

    CoWSwapOrderDecoder public decoder;

    /// @dev The domain separator of GPv2Settlement contract used for orderDigest calculation.
    bytes32 internal constant COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    function setUp() public {
        decoder = new CoWSwapOrderDecoder();
    }

    function testDecodeOrder() public {
        // Create a sample order
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(address(0x1111111111111111111111111111111111111111)),
            buyToken: IERC20(address(0x2222222222222222222222222222222222222222)),
            receiver: address(0x3333333333333333333333333333333333333333),
            sellAmount: 1_000_000_000_000_000_000, // 1 token with 18 decimals
            buyAmount: 2_000_000_000_000_000_000, // 2 tokens with 18 decimals
            validTo: uint32(block.timestamp + 1 hours),
            appData: bytes32(0),
            feeAmount: 10_000_000_000_000_000, // 0.01 token with 18 decimals
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        // Compute the order digest
        bytes32 orderDigest = order.hash(COW_SETTLEMENT_DOMAIN_SEPARATOR);

        // Encode the order
        bytes memory encodedOrder = abi.encode(order);

        // Decode and log the order
        decoder.decodeAndLogOrder(orderDigest, encodedOrder);
    }

    function testDecodeRealOrder() public {
        // This is an example of a real CoWSwap order
        // You would replace these values with actual values from a real CoWSwap order
        address sellTokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC on mainnet
        address buyTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH on mainnet
        address receiverAddress = address(0); // 0 address means same as owner
        uint256 sellAmount = 1000 * 10 ** 6; // 1000 USDC (6 decimals)
        uint256 buyAmount = 0.5 * 10 ** 18; // 0.5 WETH (18 decimals)
        uint32 validTo = uint32(block.timestamp + 1 hours);
        bytes32 appData = bytes32(0);
        uint256 feeAmount = 1 * 10 ** 6; // 1 USDC fee

        // Create the order
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(sellTokenAddress),
            buyToken: IERC20(buyTokenAddress),
            receiver: receiverAddress,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: appData,
            feeAmount: feeAmount,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        // Compute the order digest
        bytes32 orderDigest = order.hash(COW_SETTLEMENT_DOMAIN_SEPARATOR);

        // Encode the order
        bytes memory encodedOrder = abi.encode(order);

        // Decode and log the order
        decoder.decodeAndLogOrder(orderDigest, encodedOrder);
    }

    function testDecodeFromRawData() public {
        // This function can be used to decode an order from raw calldata
        // You would replace this with actual calldata from a CoWSwap transaction

        // Example: This is a placeholder for actual calldata
        // solhint-disable max-line-length
        bytes memory rawCalldata =
            hex"000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea00000000000000000000000074b30712b0be1f07ed27c0c7c68d14ac35fab3c1000000000000000000000000000000000000000000000000000000000cbfd6d900000000000000000000000000000000000000000000000a12c192df1f8600000000000000000000000000000000000000000000000000000000000067beb23000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee34677500000000000000000000000000000000000000000000000000000000000000005a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc95a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9";

        // Extract the orderDigest from the transaction (this would be different in a real scenario)
        // In a real scenario, you would get this from the transaction or from the CoWSwap API
        bytes32 orderDigest = 0x657e1c269320fbfb81763efb6a7880430b0281239537d17d2edf3254946dd73e;

        // Decode and log the order
        decoder.decodeAndLogOrder(orderDigest, rawCalldata);
    }
}

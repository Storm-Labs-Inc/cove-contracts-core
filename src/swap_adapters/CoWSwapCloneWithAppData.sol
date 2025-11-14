// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Clone } from "clones-with-immutable-args/Clone.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

// slither-disable-start locked-ether
/// @title CoWSwapCloneWithAppData
/// @notice Variant of `CoWSwapClone` that requires a non-zero CoW Protocol appData hash for order validation.
contract CoWSwapCloneWithAppData is IERC1271, Clone {
    using GPv2Order for GPv2Order.Data;
    using SafeERC20 for IERC20;

    /// CONSTANTS ///
    /// @notice The appData hash that is submitted for the orders.
    bytes32 public immutable appDataHash;
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_NON_MAGIC_VALUE = 0xffffffff;

    /// @dev The domain separator of GPv2Settlement contract used for orderDigest calculation.
    bytes32 internal constant _COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    /// @dev Address of the GPv2VaultRelayer.
    /// https://docs.cow.fi/cow-protocol/reference/contracts/core
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    /// EVENTS ///
    event CoWSwapCloneCreated(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo,
        address indexed receiver,
        address operator
    );
    event OrderClaimed(address indexed operator, uint256 claimedSellAmount, uint256 claimedBuyAmount);

    /// ERRORS ///
    error CallerIsNotOperatorOrReceiver();

    constructor(bytes32 appDataHash_) {
        appDataHash = appDataHash_;
    }

    /// @notice Initializes the CoWSwapClone contract by approving the vault relayer to spend the maximum amount of the
    /// sell token.
    /// @dev This function should be called after the clone is deployed to set up the necessary token approvals.
    function initialize() external payable {
        IERC20(sellToken()).forceApprove(_VAULT_RELAYER, type(uint256).max);
        emit CoWSwapCloneCreated(
            sellToken(), buyToken(), sellAmount(), minBuyAmount(), validTo(), receiver(), operator()
        );
    }

    /// @notice Validates the signature of an order. The order is considered valid if the order digest matches the
    /// stored order digest. Second parameter is not used.
    /// @param orderDigest The digest of the order to validate.
    /// @return A magic value if the signature is valid, otherwise a non-magic value.
    // solhint-disable-next-line code-complexity
    function isValidSignature(
        bytes32 orderDigest,
        bytes calldata encodedOrder
    )
        external
        view
        override
        returns (bytes4)
    {
        GPv2Order.Data memory order = abi.decode(encodedOrder, (GPv2Order.Data));

        if (orderDigest != order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR)) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (address(order.sellToken) != sellToken()) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (address(order.buyToken) != buyToken()) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.sellAmount != sellAmount()) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.buyAmount < minBuyAmount()) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.validTo != validTo()) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.appData != appDataHash) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.feeAmount != 0) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.kind != GPv2Order.KIND_SELL) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.partiallyFillable) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        if (order.receiver != address(this)) {
            return _ERC1271_NON_MAGIC_VALUE;
        }

        return _ERC1271_MAGIC_VALUE;
    }

    /// @notice Claims the sell and buy tokens. Calling this function before the trade has settled will cancel the
    /// trade. Only the operator or the receiver can claim the tokens.
    /// @return claimedSellAmount The amount of sell tokens claimed.
    /// @return claimedBuyAmount The amount of buy tokens claimed.
    function claim() external payable returns (uint256 claimedSellAmount, uint256 claimedBuyAmount) {
        if (msg.sender != operator()) {
            if (msg.sender != receiver()) {
                revert CallerIsNotOperatorOrReceiver();
            }
        }
        claimedSellAmount = IERC20(sellToken()).balanceOf(address(this));
        if (claimedSellAmount > 0) {
            IERC20(sellToken()).safeTransfer(receiver(), claimedSellAmount);
        }
        claimedBuyAmount = IERC20(buyToken()).balanceOf(address(this));
        if (claimedBuyAmount > 0) {
            IERC20(buyToken()).safeTransfer(receiver(), claimedBuyAmount);
        }

        emit OrderClaimed(msg.sender, claimedSellAmount, claimedBuyAmount);
    }

    // Immutable fields stored in the contract's bytecode
    // 0: sellToken (address)
    // 20: buyToken (address)
    // 40: sellAmount (uint256)
    // 72: minBuyAmount (uint256)
    // 104: validTo (uint32)
    // 112: receiver (address)
    // 132: operator (address)
    function sellToken() public pure returns (address) {
        return _getArgAddress(0);
    }

    function buyToken() public pure returns (address) {
        return _getArgAddress(20);
    }

    function sellAmount() public pure returns (uint256) {
        return _getArgUint256(40);
    }

    function minBuyAmount() public pure returns (uint256) {
        return _getArgUint256(72);
    }

    function validTo() public pure returns (uint32) {
        return uint32(_getArgUint64(104));
    }

    function receiver() public pure returns (address) {
        return _getArgAddress(112);
    }

    function operator() public pure returns (address) {
        return _getArgAddress(132);
    }
}
// slither-disable-end locked-ether

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Clone } from "clones-with-immutable-args/Clone.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

/// @title CoWSwapClone
/// @dev A contract that implements the ERC1271 interface for signature validation and manages token trades. This
/// contract is designed to be used as a clone with immutable arguments.
contract CoWSwapClone is IERC1271, Clone {
    using GPv2Order for GPv2Order.Data;

    // Constants for ERC1271 signature validation
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_NON_MAGIC_VALUE = 0xffffffff;

    /// @dev The domain separator of GPv2Settlement contract used for orderDigest calculation.
    bytes32 internal constant _COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    /// @dev Address of the GPv2VaultRelayer.
    /// https://docs.cow.fi/cow-protocol/reference/contracts/core
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    error CallerIsNotOperatorOrReceiver();
    error OrderDigestMismatch();

    /// @notice Initializes the CoWSwapClone contract by approving the vault relayer to spend the maximum amount of the
    /// sell token.
    /// @dev This function should be called after the clone is deployed to set up the necessary token approvals.
    function initialize() external payable {
        IERC20(sellToken()).approve(_VAULT_RELAYER, type(uint256).max);
        // TODO: emit events for each trade
    }

    /// @notice Validates the signature of an order. The order is considered valid if the order digest matches the
    /// stored order digest. Second parameter is not used.
    /// @param orderDigest The digest of the order to validate.
    /// @return A magic value if the signature is valid, otherwise a non-magic value.
    function isValidSignature(
        bytes32 orderDigest,
        bytes calldata encodedOrder
    )
        external
        pure
        override
        returns (bytes4)
    {
        if (
            orderDigest == storedOrderDigest()
                && orderDigest == abi.decode(encodedOrder, (GPv2Order.Data)).hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR)
        ) {
            return _ERC1271_MAGIC_VALUE;
        }
        return _ERC1271_NON_MAGIC_VALUE;
    }

    /// @notice Claims the sell and buy tokens. Calling this function before the trade has settled will cancel the
    /// trade. Only the operator or the receiver can claim the tokens.
    /// @return claimedSellAmount The amount of sell tokens claimed.
    /// @return claimedBuyAmount The amount of buy tokens claimed.
    function claim() external returns (uint256 claimedSellAmount, uint256 claimedBuyAmount) {
        if (msg.sender != operator() || msg.sender != receiver()) {
            revert CallerIsNotOperatorOrReceiver();
        }
        claimedSellAmount = IERC20(sellToken()).balanceOf(address(this));
        IERC20(sellToken()).transfer(receiver(), claimedSellAmount);
        claimedBuyAmount = IERC20(buyToken()).balanceOf(address(this));
        IERC20(buyToken()).transfer(receiver(), claimedBuyAmount);
    }

    // Immutable fields stored in the contract's bytecode
    // 0: orderHash (uint256)
    // 32: sellToken (address)
    // 52: buyToken (address)
    // 72: sellAmount (uint256)
    // 104: buyAmount (uint256)
    // 136 receiver (address)
    // 156: operator (address)

    /// @notice Returns the order digest.
    /// @return The order digest.
    function storedOrderDigest() public pure returns (bytes32) {
        return bytes32(_getArgUint256(0));
    }

    /// @notice Returns the address of the sell token.
    /// @return The address of the sell token.
    function sellToken() public pure returns (address) {
        return _getArgAddress(32);
    }

    /// @notice Returns the address of the buy token.
    /// @return The address of the buy token.
    function buyToken() public pure returns (address) {
        return _getArgAddress(52);
    }

    /// @notice Returns the amount of sell tokens.
    /// @return The amount of sell tokens.
    function sellAmount() public pure returns (uint256) {
        return _getArgUint256(72);
    }

    /// @notice Returns the amount of buy tokens.
    /// @return The amount of buy tokens.
    function buyAmount() public pure returns (uint256) {
        return _getArgUint256(104);
    }

    /// @notice Returns the address of the receiver.
    /// @return The address of the receiver.
    function receiver() public pure returns (address) {
        return _getArgAddress(136);
    }

    /// @notice Returns the address of the operator who can claim the tokens after the trade has settled. The operator
    /// can also cancel the trade before it has settled by calling the claim function before the trade has settled.
    /// @return The address of the operator.
    function operator() public pure returns (address) {
        return _getArgAddress(156);
    }
}

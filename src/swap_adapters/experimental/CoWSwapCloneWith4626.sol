// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Clone } from "clones-with-immutable-args/Clone.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

// slither-disable-start locked-ether
/// @title CoWSwapClone
/// @notice A contract that implements the ERC1271 interface for signature validation and manages token trades. This
/// contract is designed to be used as a clone with immutable arguments, leveraging the `ClonesWithImmutableArgs`
/// library.
/// The clone should be initialized with the following packed bytes, in this exact order:
/// - `sellToken` (address): The address of the token to be sold.
/// - `buyToken` (address): The address of the token to be bought.
/// - `sellAmount` (uint256): The amount of the sell token.
/// - `buyAmount` (uint256): The minimum amount of the buy token.
/// - `validTo` (uint64): The timestamp until which the order is valid.
/// - `operator` (address): The address of the operator allowed to manage the trade.
/// - `receiver` (address): The address that will receive the bought tokens.
///
/// To use this contract, deploy it as a clone using the `ClonesWithImmutableArgs` library with the above immutable
/// arguments packed into a single bytes array. After deployment, call `initialize()` to set up the necessary token
/// approvals for the trade.
/// @dev The `isValidSignature` function can be used to validate the signature of an order against the stored order
/// digest.
contract CoWSwapCloneWith4626 is IERC1271, Clone {
    using GPv2Order for GPv2Order.Data;
    using SafeERC20 for IERC20;

    /// CONSTANTS ///
    // Constants for ERC1271 signature validation
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_NON_MAGIC_VALUE = 0xffffffff;

    /// @dev The domain separator of GPv2Settlement contract used for orderDigest calculation.
    bytes32 internal constant _COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    /// @dev Address of the GPv2VaultRelayer.
    /// https://docs.cow.fi/cow-protocol/reference/contracts/core
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    /// EVENTS ///
    /// @notice Emitted when a new order is created.
    /// @param sellToken The address of the token to be sold.
    /// @param buyToken The address of the token to be bought.
    /// @param sellAmount The amount of the sell token.
    /// @param minBuyAmount The minimum amount of the buy token.
    /// @param validTo The timestamp until which the order is valid.
    /// @param receiver The address that will receive the bought tokens.
    /// @param operator The address of the operator allowed to manage the trade.
    event CoWSwapCloneCreated(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo,
        address indexed receiver,
        address operator
    );
    /// @notice Emitted when an order is claimed.
    /// @param operator The address of the operator who claimed the order.
    /// @param claimedSellAmount The amount of sell tokens claimed.
    /// @param claimedBuyAmount The amount of buy tokens claimed.
    event OrderClaimed(address indexed operator, uint256 claimedSellAmount, uint256 claimedBuyAmount);

    /// ERRORS ///
    /// @notice Thrown when the caller is not the operator or receiver of the order.
    error CallerIsNotOperatorOrReceiver();

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

        if (order.appData != bytes32(0)) {
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

        // Handle residual sell side tokens (if any)
        claimedSellAmount = _wrapAndTransfer(sellToken(), outerSellToken(), sellDepth());

        // Handle buy side tokens (main expected path)
        claimedBuyAmount = _wrapAndTransfer(buyToken(), outerBuyToken(), buyDepth());

        emit OrderClaimed(msg.sender, claimedSellAmount, claimedBuyAmount);
    }

    /// @dev Internal helper that optionally wraps `token` up `depth` layers of ERC4626 vaults
    ///      and transfers the resulting (possibly wrapped) tokens to the receiver.
    /// @param underlyingToken The token currently held by this contract.
    /// @param outerToken The original token prior to unwrapping. If `depth` is zero this will be the same as
    ///        `underlyingToken`.
    /// @param depth The number of ERC4626 layers to wrap. 0 means no wrapping.
    /// @return amountTransferred The amount of the final wrapped token transferred to the receiver.
    function _wrapAndTransfer(address underlyingToken, address outerToken, uint8 depth) internal returns (uint256) {
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));

        if (depth == 0) {
            // No wrapping required, underlyingToken equals outerToken.
            if (underlyingBalance > 0) {
                IERC20(underlyingToken).safeTransfer(receiver(), underlyingBalance);
            }
            return underlyingBalance;
        }

        // Build the path array on-the-fly and wrap step-wise.
        address currentUnderlying = underlyingToken;
        uint256 currentAmount = underlyingBalance;

        // Compute token path starting from outerToken downwards to reach `underlyingToken`.
        // To save gas we iterate depth times, assuming correctness of depth & path.
        address shareToken = outerToken;
        // We need to iterate from the deepest layer upwards, hence we first build a stack (fixed-size array).
        address[5] memory stack; // depth is uint8 so practical max expected layers is small (<5). Adjust if needed.
        uint8 stackLen = 0;
        for (uint8 i = 0; i < depth; ++i) {
            stack[stackLen] = shareToken;
            unchecked {
                ++stackLen;
            }
            shareToken = IERC4626(shareToken).asset();
        }

        // shareToken is now expected to equal underlyingToken. No runtime check to save gas.

        // Perform wrapping from deepest layer to outermost.
        for (uint8 i = stackLen; i > 0;) {
            unchecked {
                --i;
            }
            address currentShare = stack[i];
            // Approve underlying for deposit
            if (currentAmount > 0) {
                IERC20(currentUnderlying).forceApprove(currentShare, currentAmount);
                currentAmount = IERC4626(currentShare).deposit(currentAmount, address(this));
            }
            currentUnderlying = currentShare;
        }

        // Check for potential remaining balance of outerToken
        uint256 remainingBalance = IERC20(outerToken).balanceOf(address(this));
        if (remainingBalance > 0) {
            // Return the remaining balance of outerToken
            IERC20(outerToken).safeTransfer(receiver(), remainingBalance);
        }

        // Return the **outerToken** amount moved out of this contract.
        return remainingBalance;
    }

    // Immutable fields stored in the contract's bytecode
    // 0: sellToken (address)
    // 20: buyToken (address)
    // 40: sellAmount (uint256)
    // 72: minBuyAmount (uint256)
    // 104: validTo (uint32)
    // 112: receiver (address)
    // 132: operator (address)
    // 152: outerSellToken (address)
    // 172: outerBuyToken (address)
    // 192: sellDepth (uint8)
    // 193: buyDepth (uint8)

    /// @notice Returns the address of the sell token.
    /// @return The address of the sell token.
    function sellToken() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice Returns the address of the buy token.
    /// @return The address of the buy token.
    function buyToken() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice Returns the amount of sell tokens.
    /// @return The amount of sell tokens.
    function sellAmount() public pure returns (uint256) {
        return _getArgUint256(40);
    }

    /// @notice Returns the amount of buy tokens.
    /// @return The amount of buy tokens.
    function minBuyAmount() public pure returns (uint256) {
        return _getArgUint256(72);
    }

    /// @notice Returns the timestamp until which the order is valid.
    /// @return The timestamp until which the order is valid.
    function validTo() public pure returns (uint32) {
        return uint32(_getArgUint64(104));
    }

    /// @notice Returns the address of the receiver.
    /// @return The address of the receiver.
    function receiver() public pure returns (address) {
        return _getArgAddress(112);
    }

    /// @notice Returns the address of the operator who can claim the tokens after the trade has settled. The operator
    /// can also cancel the trade before it has settled by calling the claim function before the trade has settled.
    /// @return The address of the operator.
    function operator() public pure returns (address) {
        return _getArgAddress(132);
    }

    /// @notice Returns the original (outermost) sell token prior to unwrapping.
    function outerSellToken() public pure returns (address) {
        return _getArgAddress(152);
    }

    /// @notice Returns the original (outermost) buy token prior to unwrapping.
    function outerBuyToken() public pure returns (address) {
        return _getArgAddress(172);
    }

    /// @notice Returns the depth of ERC4626 unwrapping applied to the sell token.
    function sellDepth() public pure returns (uint8) {
        return _getArgUint8(192);
    }

    /// @notice Returns the depth of ERC4626 unwrapping expected on the buy token.
    function buyDepth() public pure returns (uint8) {
        return _getArgUint8(193);
    }
}
// slither-disable-end locked-ether

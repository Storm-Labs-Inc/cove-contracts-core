// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Clone } from "clones-with-immutable-args/Clone.sol";

/**
 * @title MilkBoy
 * @dev A contract that implements the ERC1271 interface for signature validation and manages token trades.
 *      This contract is designed to be used as a clone with immutable arguments.
 */
contract MilkBoy is IERC1271, Clone {
    // Constants for ERC1271 signature validation
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_NON_MAGIC_VALUE = 0xffffffff;

    /**
     * @notice Validates the signature of an order. The order is considered valid if the order digest matches the stored
     * order digest. Second parameter is not used.
     * @param orderDigest The digest of the order to validate.
     * @return A magic value if the signature is valid, otherwise a non-magic value.
     */
    function isValidSignature(bytes32 orderDigest, bytes calldata) external pure override returns (bytes4) {
        if (orderDigest == storedOrderDigest()) {
            return _ERC1271_MAGIC_VALUE;
        }
        return _ERC1271_NON_MAGIC_VALUE;
    }

    /**
     * @notice Checks whether the trade has settled by comparing the current balance of the sell token.
     * @return hasTradeSettled True if the trade has settled, false otherwise.
     */
    function hasTradeSettled() public view returns (bool) {
        return IERC20(sellToken()).balanceOf(address(this)) < sellAmount();
    }

    /**
     * @notice Claims the tokens after the trade has settled.
     * @return claimedSellAmount The amount of sell tokens claimed.
     * @return claimedBuyAmount The amount of buy tokens claimed.
     */
    function claim() external returns (uint256 claimedSellAmount, uint256 claimedBuyAmount) {
        if (!hasTradeSettled()) {
            IERC20(sellToken()).transfer(basketManager(), sellAmount());
            return (sellAmount(), 0);
        }
        // TODO: Support partial fills
        uint256 buyTokenBalance = IERC20(buyToken()).balanceOf(address(this));
        IERC20(buyToken()).transfer(basketManager(), buyTokenBalance);
        return (0, buyTokenBalance);
    }

    // Immutable fields stored in the contract's bytecode
    // 0: orderHash (uint256)
    // 32: sellToken (address)
    // 52: buyToken (address)
    // 72: sellAmount (uint256)
    // 104: buyAmount (uint256)
    // 136: validTo (uint64) - only the lower 32 bits are used
    // 144: basketManager (address)

    /**
     * @notice Returns the order digest.
     * @return The order digest.
     */
    function storedOrderDigest() public pure returns (bytes32) {
        return bytes32(_getArgUint256(0));
    }

    /**
     * @notice Returns the address of the sell token.
     * @return The address of the sell token.
     */
    function sellToken() public pure returns (address) {
        return _getArgAddress(32);
    }

    /**
     * @notice Returns the address of the buy token.
     * @return The address of the buy token.
     */
    function buyToken() public pure returns (address) {
        return _getArgAddress(52);
    }

    /**
     * @notice Returns the amount of sell tokens.
     * @return The amount of sell tokens.
     */
    function sellAmount() public pure returns (uint256) {
        return _getArgUint256(72);
    }

    /**
     * @notice Returns the amount of buy tokens.
     * @return The amount of buy tokens.
     */
    function buyAmount() public pure returns (uint256) {
        return _getArgUint256(104);
    }

    /**
     * @notice Returns the validity timestamp of the order.
     * @return The validity timestamp of the order.
     */
    function validTo() public pure returns (uint32) {
        return uint32(_getArgUint64(136));
    }

    /**
     * @notice Returns the address of the basket manager.
     * @return The address of the basket manager.
     */
    function basketManager() public pure returns (address) {
        return _getArgAddress(144);
    }
}

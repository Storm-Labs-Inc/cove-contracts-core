// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Rescuable
/// @notice Allows the inheriting contract to rescue ERC20 tokens that are sent to it by mistake.
contract Rescuable {
    // Libraries
    using SafeERC20 for IERC20;

    // Errors
    /// @notice Error for when an ETH transfer of zero is attempted.
    error ZeroEthTransfer();
    /// @notice Error for when an ETH transfer fails.
    error EthTransferFailed();
    /// @notice Error for when a token transfer of zero is attempted.
    error ZeroTokenTransfer();

    /// @dev Rescue any ERC20 tokens that are stuck in this contract.
    /// The inheriting contract that calls this function should specify required access controls
    /// @param token address of the ERC20 token to rescue. Use zero address for ETH
    /// @param to address to send the tokens to
    /// @param balance amount of tokens to rescue. Use zero to rescue all
    function _rescue(IERC20 token, address to, uint256 balance) internal {
        if (address(token) == address(0)) {
            // for ether
            uint256 totalBalance = address(this).balance;
            balance = balance != 0 ? Math.min(totalBalance, balance) : totalBalance;
            if (balance != 0) {
                // slither-disable-next-line arbitrary-send
                // slither-disable-next-line low-level-calls
                (bool success,) = to.call{ value: balance }("");
                if (!success) revert EthTransferFailed();
                return;
            }
            revert ZeroEthTransfer();
        } else {
            // for any other erc20
            uint256 totalBalance = token.balanceOf(address(this));
            balance = balance != 0 ? Math.min(totalBalance, balance) : totalBalance;
            if (balance != 0) {
                token.safeTransfer(to, balance);
                return;
            }
            revert ZeroTokenTransfer();
        }
    }
}

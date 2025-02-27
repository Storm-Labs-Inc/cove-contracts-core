// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { BaseAdapter } from "euler-price-oracle/src/adapter/BaseAdapter.sol";
import { ScaleUtils } from "euler-price-oracle/src/lib/ScaleUtils.sol";

/// @title ERC4626Oracle
/// @author Storm Labs (https://storm-labs.xyz/)
/// @notice A price oracle adapter for ERC4626 vault tokens
/// @dev Handles price conversions between ERC4626 vault shares and their underlying assets.
/// When the vault token is used as the base or quote, the oracle automatically converts between share and asset prices
/// using the vault's convertToAssets/convertToShares functions. The oracle follows the behavior of
/// the ERC4626 vault's implementation of its functions, typically ignoring the maximum amount of shares that can be
/// redeemed or minted.
contract ERC4626Oracle is BaseAdapter {
    /// @notice The name of the oracle.
    // solhint-disable-next-line const-name-snakecase
    string public constant override name = "ERC4626Oracle";
    /// @notice The address of the base asset.
    address public immutable base;
    /// @notice The address of the quote asset.
    address public immutable quote;

    /// @notice Constructor for the ERC4626Oracle contract.
    /// @param _vault The ERC4626 vault that should be used as the base asset.
    // nosemgrep: solidity.performance.non-payable-constructor.non-payable-constructor
    constructor(IERC4626 _vault) {
        // Assume the vault is IERC4626 compliant token
        base = address(_vault);
        quote = _vault.asset();
    }

    function _getQuote(
        uint256 inAmount,
        address _base,
        address _quote
    )
        internal
        view
        virtual
        override
        returns (uint256)
    {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);
        if (inAmount == 0) {
            return 0;
        }
        if (!inverse) {
            return IERC4626(_base).convertToAssets(inAmount);
        } else {
            return IERC4626(_quote).convertToShares(inAmount);
        }
    }
}

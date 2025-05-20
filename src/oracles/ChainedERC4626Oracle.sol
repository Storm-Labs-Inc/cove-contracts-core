// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { BaseAdapter } from "euler-price-oracle/src/adapter/BaseAdapter.sol";
import { ScaleUtils } from "euler-price-oracle/src/lib/ScaleUtils.sol";

/// @title ChainedERC4626Oracle
/// @author Storm Labs (https://storm-labs.xyz/)
/// @notice A price oracle adapter for chained ERC4626 vault tokens
/// @dev Handles price conversions between ERC4626 vault shares through multiple levels until reaching
/// the target underlying asset. The oracle automatically converts between share and asset prices
/// through the entire chain using each vault's convertToAssets/convertToShares functions.
///
/// This oracle relies on the convertToAssets/convertToShares functions of the underlying ERC4626 vaults.
/// If the dependent ERC4626 contracts do not implement sufficient protection against donation attacks,
/// sudden price jumps may occur when large amounts of assets are donated to the vaults without a proportional
/// increase in shares. Users should verify the security measures implemented by the underlying vaults.
/// Due to this risk, this oracle should only be used when there is no direct price feed available for the vault tokens.
contract ChainedERC4626Oracle is BaseAdapter {
    /// @notice The name of the oracle
    // solhint-disable-next-line const-name-snakecase
    string public constant override name = "ChainedERC4626Oracle";
    /// @notice The address of the base asset (first vault in chain)
    address public immutable base;
    /// @notice The address of the quote asset (final underlying asset)
    address public immutable quote;
    /// @notice The array of vaults in the chain
    address[] public vaults;

    /// @notice Thrown when a vault in the chain is invalid (zero address)
    error InvalidVaultChain();
    /// @notice Thrown when the vault chain is either empty or exceeds the maximum allowed length
    error ChainTooLong();
    /// @notice Thrown when the chain cannot reach the target asset (e.g., invalid vault sequence)
    error TargetAssetNotReached();

    /// @notice Maximum allowed length for the vault chain
    uint256 private constant _MAX_CHAIN_LENGTH = 10;

    /// @notice Constructor for the ChainedERC4626Oracle contract
    /// @param _initialVault The starting ERC4626 vault in the chain
    /// @param _targetAsset The final underlying asset to reach
    // slither-disable-next-line locked-ether
    constructor(IERC4626 _initialVault, address _targetAsset) payable {
        uint256 chainLength = 0;

        // Start with the initial vault
        address currentVault = address(_initialVault);
        address currentAsset;

        // slither-disable-start calls-loop
        // Build the chain
        while (chainLength < _MAX_CHAIN_LENGTH) {
            if (currentVault == address(0)) revert InvalidVaultChain();
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            vaults.push(currentVault);

            try IERC4626(currentVault).asset() returns (address asset) {
                currentAsset = asset;
                // Safe to use unchecked as chainLength is bounded by _MAX_CHAIN_LENGTH (10)
                unchecked {
                    ++chainLength;
                }

                // Check if we've reached the target asset
                if (currentAsset == _targetAsset) {
                    break;
                }

                // Try to treat the asset as another vault
                currentVault = currentAsset;
            } catch {
                revert TargetAssetNotReached();
            }
        }
        // slither-disable-end calls-loop
        if (chainLength == 0 || chainLength == _MAX_CHAIN_LENGTH) {
            revert ChainTooLong();
        }

        // Set the base and quote for the BaseAdapter
        base = address(_initialVault);
        quote = _targetAsset;
    }

    /// @notice Internal function to get quote through the vault chain
    /// @param inAmount The input amount to convert
    /// @param _base The base asset address
    /// @param _quote The quote asset address
    /// @return The converted amount
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

        if (inAmount == 0) return 0;
        uint256 length = vaults.length;

        if (!inverse) {
            // Convert from vault shares to final asset
            uint256 amount = inAmount;
            for (uint256 i = 0; i < length;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                // slither-disable-next-line calls-loop
                amount = IERC4626(vaults[i]).convertToAssets(amount);
                // Safe to use unchecked as i is bounded by length (which is bounded by _MAX_CHAIN_LENGTH)
                unchecked {
                    ++i;
                }
            }
            return amount;
        } else {
            // Convert from final asset to vault shares
            uint256 amount = inAmount;
            for (uint256 i = length; i > 0;) {
                // Safe to use unchecked as i is always > 0 in the loop condition
                unchecked {
                    --i;
                }
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                // slither-disable-next-line calls-loop
                amount = IERC4626(vaults[i]).convertToShares(amount);
            }
            return amount;
        }
    }
}

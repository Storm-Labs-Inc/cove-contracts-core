// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { BaseAdapter } from "euler-price-oracle/src/adapter/BaseAdapter.sol";
import { ScaleUtils } from "euler-price-oracle/src/lib/ScaleUtils.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";

/// @title AutopoolOracle
/// @author Storm Labs (https://storm-labs.xyz/)
/// @notice A price oracle adapter for Autopool ERC4626 vault tokens that validates debt reporting freshness
/// @dev Handles price conversions between ERC4626 vault shares and their underlying assets.
/// When the vault token is used as the base or quote, the oracle automatically converts between share and asset prices
/// using the vault's convertToAssets/convertToShares functions. The oracle follows the behavior of
/// the ERC4626 vault's implementation of its functions, typically ignoring the maximum amount of shares that can be
/// redeemed or minted.
///
/// This oracle relies on the convertToAssets/convertToShares functions of the underlying ERC4626 vault.
/// If the dependent ERC4626 contract does not implement sufficient protection against donation attacks,
/// sudden price jumps may occur when large amounts of assets are donated to the vault without a proportional
/// increase in shares. Users should verify the security measures implemented by the underlying vault.
/// Due to this risk, this oracle should only be used when there is no direct price feed available for the vault token.
///
/// Additionally, this oracle validates that the Autopool's debt reporting is fresh (within 24 hours).
contract AutopoolOracle is BaseAdapter {
    /// @notice The name of the oracle.
    // solhint-disable-next-line const-name-snakecase
    string public constant override name = "AutopoolOracle";
    /// @notice The address of the base asset.
    address public immutable base;
    /// @notice The address of the quote asset.
    address public immutable quote;
    /// @notice The Autopool contract for debt reporting validation
    IAutopool public immutable autopool;
    /// @notice Maximum allowed age for debt reporting (24 hours in seconds)
    uint256 internal constant _MAX_DEBT_REPORTING_AGE = 24 hours;

    /// @notice Thrown when the Autopool's debt reporting is stale (older than 24 hours)
    error StaleDebtReporting(uint256 oldestTimestamp, uint256 currentTimestamp);

    /// @notice Constructor for the AutopoolOracle contract.
    /// @param _vault The ERC4626 Autopool vault that should be used as the base asset.
    // slither-disable-next-line locked-ether
    constructor(IERC4626 _vault) payable {
        // Assume the vault is IERC4626 compliant token
        base = address(_vault);
        quote = _vault.asset();
        autopool = IAutopool(address(_vault));
        _validateDebtReporting();
    }

    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        _validateDebtReporting();
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

    /// @dev Checks last Autopool debt reporting age is <= 24h, reverts if too old
    function _validateDebtReporting() internal view {
        uint256 oldestDebtTimestamp = autopool.oldestDebtReporting();
        if (oldestDebtTimestamp == 0) return;
        uint256 nowTs = block.timestamp;
        if (nowTs > oldestDebtTimestamp && (nowTs - oldestDebtTimestamp > _MAX_DEBT_REPORTING_AGE)) {
            revert StaleDebtReporting(oldestDebtTimestamp, nowTs);
        }
    }
}

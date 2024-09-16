// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { Errors } from "src/libraries/Errors.sol";

/// @title FeeCollector
/// @notice Contract to collect fees from the BasketManager and distribute them to sponsors and the protocol treasury
// slither-disable-next-line locked-ether
contract FeeCollector is AccessControlEnumerable {
    /// CONSTANTS ///
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    uint16 private constant _FEE_SPLIT_DECIMALS = 1e4;
    uint16 private constant _MAX_FEE = 1e4;

    /// STATE VARIABLES ///
    // slither-disable-start uninitialized-state
    /// @notice The address of the protocol treasury
    address private _protocolTreasury;
    /// @notice The BasketManager contract
    BasketManager immutable _basketManager;
    // slither-disable-end uninitialized-state
    /// @notice Mapping of basket tokens to their sponsor addresses
    mapping(address basketToken => address sponsor) public basketTokenSponsors;
    /// @notice Mapping of basket tokens to their sponsor split percentages
    mapping(address basketToken => uint16 sponsorSplit) public basketTokenSponsorSplits;
    /// @notice Mapping of basket tokens to current claimable treasury fees
    mapping(address basketToken => uint256 claimableFees) public claimableTreasuryFees;
    /// @notice Mapping of basket tokens to the current claimable sponsor fees
    mapping(address basketToken => uint256 claimableFees) public claimableSponsorFees;

    /// ERRORS ///
    error SponsorSplitTooHigh();
    error NoSponsor();
    error Unauthorized();
    error NotBasketToken();
    error NotTreasury();

    /// @notice Constructor to set the admin, basket manager, and protocol treasury
    /// @param admin The address of the admin
    /// @param basketManager The address of the BasketManager
    /// @param treasury The address of the protocol treasury
    constructor(address admin, address basketManager, address treasury) payable {
        if (admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (basketManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _basketManager = BasketManager(basketManager);
        _protocolTreasury = treasury;
    }

    /// @notice Set the protocol treasury address
    /// @param treasury The address of the new protocol treasury
    function setProtocolTreasury(address treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        _protocolTreasury = treasury;
    }

    /// @notice Set the sponsor for a given basket token
    /// @param basketToken The address of the basket token
    /// @param sponsor The address of the sponsor
    function setSponsor(address basketToken, address sponsor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        basketTokenSponsors[basketToken] = sponsor;
    }

    /// @notice Set the split of management fees given to the sponsor for a given basket token
    /// @param basketToken The address of the basket token
    /// @param sponsorSplit The percentage of fees to give to the sponsor denominated in _FEE_SPLIT_DECIMALS
    function setSponsorSplit(address basketToken, uint16 sponsorSplit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        if (sponsorSplit > _MAX_FEE) {
            revert SponsorSplitTooHigh();
        }
        if (basketTokenSponsors[basketToken] == address(0)) {
            revert NoSponsor();
        }
        basketTokenSponsorSplits[basketToken] = sponsorSplit;
    }

    /// @notice Notify the FeeCollector of the fees collected from the basket token
    /// @param shares The amount of shares collected
    function notifyHarvestFee(uint256 shares) external {
        address basketToken = msg.sender;
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        uint16 sponsorFeeSplit = basketTokenSponsorSplits[basketToken];
        if (basketTokenSponsors[basketToken] != address(0)) {
            if (sponsorFeeSplit > 0) {
                uint256 sponsorFee = FixedPointMathLib.mulDiv(shares, sponsorFeeSplit, _FEE_SPLIT_DECIMALS);
                claimableSponsorFees[basketToken] += sponsorFee;
                shares = shares - sponsorFee;
            }
        }
        claimableTreasuryFees[basketToken] += shares;
    }

    /// @notice Claim the sponsor fee for a given basket token, only callable by the sponsor
    /// @param basketToken The address of the basket token
    function claimSponsorFee(address basketToken) external {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        address sponsor = basketTokenSponsors[basketToken];
        if (msg.sender != sponsor) {
            if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
                revert Unauthorized();
            }
        }
        uint256 fee = claimableSponsorFees[basketToken];
        claimableSponsorFees[basketToken] = 0;
        BasketToken(basketToken).proRataRedeem(fee, sponsor, address(this));
    }

    /// @notice Claim the treasury fee for a given basket token, only callable by the protocol treasury or admin
    /// @param basketToken The address of the basket token
    function claimTreasuryFee(address basketToken) external {
        if (msg.sender != _protocolTreasury) {
            if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
                revert Unauthorized();
            }
        }
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        uint256 fee = claimableTreasuryFees[basketToken];
        claimableTreasuryFees[basketToken] = 0;
        BasketToken(basketToken).proRataRedeem(fee, _protocolTreasury, address(this));
    }
}

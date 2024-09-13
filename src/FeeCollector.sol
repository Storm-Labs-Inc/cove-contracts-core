// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { Errors } from "src/libraries/Errors.sol";

/// @title FeeCollector
/// @notice Contract to collect fees from the BasketManager and distribute them to sponsors and the protocol treasury
contract FeeCollector is AccessControlEnumerable {
    /// CONSTANTS ///
    bytes32 private constant _BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes32 private constant _PROTOCOL_TREASURY_ROLE = keccak256("PROTOCOL_TREASURY_ROLE");
    bytes32 private constant _SPONSOR_ROLE = keccak256("SPONSOR_ROLE");
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    uint16 private constant _FEE_SPLIT_DECIMALS = 1e4;
    uint16 private constant _MAX_FEE = 1e4;

    /// STATE VARIABLES ///
    /// @notice The address of the protocol treasury
    address private _protocolTreasury;
    /// @notice The BasketManager contract
    BasketManager private _basketManager;
    /// @notice Mapping of basket tokens to their sponsor addresses
    mapping(address basketToken => address sponsor) public basketTokenSponsers;
    /// @notice Mapping of basket tokens to their sponsor split percentages
    mapping(address basketToken => uint16 sponsorSplit) public basketTokenSponserSplits;
    /// @notice Mapping of basket tokens to current claimable treasury fees
    mapping(address basketToken => uint256 feeCollected) public treasuryFeesCollected;
    /// @notice Mapping of basket tokens to the current claimable sponsor fees
    mapping(address basketToken => uint256 feesCollected) public sponsorFeesCollected;

    /// ERRORS ///
    error SponserSplitTooHigh();
    error NotSponser();
    error NoSponser();
    error NotBasketToken();

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
        _grantRole(_BASKET_MANAGER_ROLE, basketManager);
        _grantRole(_PROTOCOL_TREASURY_ROLE, treasury);
        _basketManager = BasketManager(basketManager);
        _protocolTreasury = treasury;
    }

    /// @notice Set the protocol treasury address
    /// @param treasury The address of the new protocol treasury
    function setProtocolTreasury(address treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        _revokeRole(_PROTOCOL_TREASURY_ROLE, _protocolTreasury);
        _grantRole(_PROTOCOL_TREASURY_ROLE, treasury);
        _protocolTreasury = treasury;
    }

    /// @notice Set the BasketManager address
    /// @param basketManager The address of the new BasketManager
    function setBasketManager(address basketManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basketManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        _revokeRole(_BASKET_MANAGER_ROLE, address(_basketManager));
        _grantRole(_BASKET_MANAGER_ROLE, basketManager);
        _basketManager = BasketManager(basketManager);
    }

    /// @notice Set the sponsor for a given basket token
    /// @param basketToken The address of the basket token
    /// @param sponsor The address of the sponsor
    function setSponser(address basketToken, address sponsor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        if (basketTokenSponsers[basketToken] != address(0)) {
            _revokeRole(_SPONSOR_ROLE, basketTokenSponsers[basketToken]);
        }
        basketTokenSponsers[basketToken] = sponsor;
        _grantRole(_SPONSOR_ROLE, sponsor);
    }

    /// @notice Set the split of management fees given to the sponsor for a given basket token
    /// @param basketToken The address of the basket token
    /// @param sponsorSplit The percentage of fees to give to the sponsor denominated in _FEE_SPLIT_DECIMALS
    function setSponserSplit(address basketToken, uint16 sponsorSplit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        if (sponsorSplit > _MAX_FEE) {
            revert SponserSplitTooHigh();
        }
        if (basketTokenSponsers[basketToken] == address(0)) {
            revert NoSponser();
        }
        basketTokenSponserSplits[basketToken] = sponsorSplit;
    }

    /// @notice Notify the FeeCollector of the fees collected from the basket token
    /// @param shares The amount of shares collected
    function notifyHarvestFee(uint256 shares) external {
        address basketToken = msg.sender;
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        uint16 sponsorFeeSplit = basketTokenSponserSplits[basketToken];
        if (basketTokenSponsers[basketToken] != address(0) && sponsorFeeSplit > 0) {
            uint256 sponsorFee = FixedPointMathLib.mulDiv(shares, sponsorFeeSplit, _FEE_SPLIT_DECIMALS);
            sponsorFeesCollected[basketToken] = sponsorFeesCollected[basketToken] + sponsorFee;
            shares = shares - sponsorFee;
        }
        treasuryFeesCollected[basketToken] = treasuryFeesCollected[basketToken] + shares;
    }

    /// @notice Withdraw the sponsor fee for a given basket token, only callable by the sponsor
    /// @param basketToken The address of the basket token
    function withdrawSponserFee(address basketToken) external onlyRole(_SPONSOR_ROLE) {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        address sponsor = basketTokenSponsers[basketToken];
        if (msg.sender != sponsor) {
            revert NotSponser();
        }
        uint256 fee = sponsorFeesCollected[basketToken];
        sponsorFeesCollected[basketToken] = 0;
        BasketToken(basketToken).proRataRedeem(fee, sponsor, address(this));
    }

    /// @notice Withdraw the treasury fee for a given basket token, only callable by the protocol treasury
    /// @param basketToken The address of the basket token
    function withdrawTreasuryFee(address basketToken) external onlyRole(_PROTOCOL_TREASURY_ROLE) {
        if (!_basketManager.hasRole(_BASKET_TOKEN_ROLE, basketToken)) {
            revert NotBasketToken();
        }
        uint256 fee = treasuryFeesCollected[basketToken];
        treasuryFeesCollected[basketToken] = 0;
        BasketToken(basketToken).proRataRedeem(fee, _protocolTreasury, address(this));
    }
}

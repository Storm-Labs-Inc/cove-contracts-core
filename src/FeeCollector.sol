// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { Errors } from "src/libraries/Errors.sol";

/// @title FeeCollector
/// @notice Contract to collect fees from the BasketManager and distribute them to sponsers and the protocol treasury
contract FeeCollector is AccessControlEnumerable {
    /// CONSTANTS ///
    bytes32 private constant _BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes32 private constant _PROTOCOL_TREASURY_ROLE = keccak256("PROTOCOL_TREASURY_ROLE");
    uint16 private constant _FEE_SPLIT_DECIMALS = 1e4;
    uint16 private constant _MAX_FEE = 1e4;

    /// STATE VARIABLES ///
    /// @notice The address of the protocol treasury
    address private _protocolTreasury;
    /// @notice The BasketManager contract
    BasketManager private _basketManager;
    /// @notice Mapping of basket tokens to their sponser addresses
    mapping(address basketToken => address sponser) public basketTokenSponsers;
    /// @notice Mapping of basket tokens to their sponser split percentages
    mapping(address basketToken => uint16 sponserSplit) public basketTokenSponserSplits;
    /// @notice Mapping of basket tokens to current claimable treasury fees
    mapping(address basketToken => uint256 feeCollected) public treasuryFeesCollected;
    /// @notice Mapping of basket tokens to the current claimable sponser fees
    mapping(address basketToken => uint256 feesCollected) public sponserFeesCollected;

    /// ERRORS ///
    error SponserSplitTooHigh();
    error NotSponser();

    /// @notice Constructor to set the admin, basket manager, and protocol treasury
    /// @param admin The address of the admin
    /// @param basketManager The address of the BasketManager
    /// @param treasury The address of the protocol treasury
    constructor(address admin, address basketManager, address treasury) {
        if (admin == address(0) || basketManager == address(0) || treasury == address(0)) {
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

    /// @notice Set the sponser for a given basket token
    /// @param basketToken The address of the basket token
    /// @param sponser The address of the sponser
    function setSponser(address basketToken, address sponser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (sponser == address(0) || basketToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (basketTokenSponsers[basketToken] != address(0)) {
            _revokeRole(_PROTOCOL_TREASURY_ROLE, basketTokenSponsers[basketToken]);
        }
        basketTokenSponsers[basketToken] = sponser;
    }

    /// @notice Set the split of management fees given to the sponsor for a given basket token
    /// @param basketToken The address of the basket token
    /// @param sponserSplit The percentage of fees to give to the sponser
    function setSponserSplit(address basketToken, uint16 sponserSplit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basketToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (sponserSplit >= _MAX_FEE) {
            revert SponserSplitTooHigh();
        }
        basketTokenSponserSplits[basketToken] = sponserSplit;
    }

    /// @notice Notify the FeeCollector of the fees collected from the basket token
    /// @param shares The amount of shares collected
    /// TODO: how to make sure this is only called by basket token?
    function notifyHarvestFee(uint256 shares) external {
        address basketToken = msg.sender;
        uint16 sponserFeeSplit = basketTokenSponserSplits[basketToken];
        if (basketTokenSponsers[basketToken] != address(0) && sponserFeeSplit > 0) {
            uint256 sponserFee = FixedPointMathLib.mulDiv(shares, sponserFeeSplit, _FEE_SPLIT_DECIMALS);
            sponserFeesCollected[basketToken] = sponserFeesCollected[basketToken] + sponserFee;
            shares = shares - sponserFee;
        }
        treasuryFeesCollected[basketToken] = treasuryFeesCollected[basketToken] + shares;
    }

    /// @notice Withdraw the sponser fee for a given basket token, only callable by the sponser
    /// @param basketToken The address of the basket token
    function withdrawSponserFee(address basketToken) external {
        if (basketToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (msg.sender != basketTokenSponsers[basketToken]) {
            revert NotSponser();
        }
        // TODO: should this be proRateRedeem or asyncRedeem?
        BasketToken(basketToken).proRataRedeem(
            sponserFeesCollected[basketToken], basketTokenSponsers[basketToken], address(this)
        );
        sponserFeesCollected[basketToken] = 0;
    }

    /// @notice Withdraw the treasury fee for a given basket token, only callable by the protocol treasury
    /// @param basketToken The address of the basket token
    function withdrawTreasuryFee(address basketToken) external onlyRole(_PROTOCOL_TREASURY_ROLE) {
        BasketToken(basketToken).proRataRedeem(treasuryFeesCollected[basketToken], _protocolTreasury, address(this));
        treasuryFeesCollected[basketToken] = 0;
    }
}

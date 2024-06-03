// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BasketToken
 */
contract BasketToken is ERC4626Upgradeable {
    /**
     * Errors
     */
    error ZeroAddress();

    /**
     * @notice Disables the ability to call initializers.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param asset_ Address of the asset.
     * @param name_ Name of the token. All names will be prefixed with "CoveBasket-".
     * @param symbol_ Symbol of the token. All symbols will be prefixed with "cb".
     * @param bitFlag  Bitflag representing the selection of assets.
     * @param strategyId Strategy ID.
     */
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag,
        uint256 strategyId
    )
        public
        initializer
    {
        bitFlag;
        strategyId;
        __ERC4626_init(IERC20Upgradeable(address(asset_)));
        __ERC20_init(string.concat("CoveBasket-", name_), string.concat("cb", symbol_));
    }

    /**
     * @notice Returns the total pending deposits from the current epoch.
     * @return Total amount of assets pending deposit.
     */
    function totalPendingDeposits() public view returns (uint256) {
        // TODO: Return currently pending deposits
        return 0;
    }

    /**
     * @notice Returns the total pending redeems from the current epoch.
     * @return Total number of shares pending redemption.
     */
    function totalPendingRedeems() public view returns (uint256) {
        // TODO: Return currently pending redeems
        return 0;
    }

    /**
     * @notice Fulfills the deposit for the given shares.
     * @param shares Number of shares to fulfill.
     * @dev This function should be called by the BasketManager contract.
     */
    function fulfillDeposit(uint256 shares) public {
        // TODO: Fulfill the deposit
    }

    /**
     * @notice Fulfills the redeem for the given assets.
     * @param assets Number of assets to fulfill.
     * @dev This function should be called by the BasketManager contract.
     */
    function fulfillRedeem(uint256 assets) public {
        // TODO: Fulfill the redeem
    }
}

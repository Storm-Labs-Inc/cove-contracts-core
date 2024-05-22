// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

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
        __ERC4626_init(IERC20Upgradeable(address(asset_)));
        __ERC20_init(string.concat("CoveBasket-", name_), string.concat("cb", symbol_));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ERC20DecimalsMock } from "@openzeppelin/contracts/mocks/token/ERC20DecimalsMock.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20DecimalsMockImpl is ERC20DecimalsMock {
    constructor(
        uint8 decimals_,
        string memory name_,
        string memory symbol_
    )
        ERC20DecimalsMock(decimals_)
        ERC20(name_, symbol_)
    { }
}

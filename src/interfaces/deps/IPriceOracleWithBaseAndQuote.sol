// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPriceOracle } from "euler-price-oracle/src/interfaces/IPriceOracle.sol";
interface IPriceOracleWithBaseAndQuote is IPriceOracle {
    function base() external view returns (address);
    function quote() external view returns (address);
}

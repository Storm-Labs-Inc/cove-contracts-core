// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";
import { BasketManagerInvariantTest } from "test/invariant/BasketManager.invariant.t.sol";

contract StagingBasketManagerInvariantTest is BasketManagerInvariantTest {
    function _getForkBlockNumber() internal override returns (uint256) {
        return 22_442_301;
    }

    function _setupBasketManager() internal override returns (BasketManager) {
        return BasketManager(address(0xbeccf8486856476E9Cd8AD6FaD80Fb7c17a15Da1));
    }
}

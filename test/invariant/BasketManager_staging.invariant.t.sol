// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";
import { BasketManager_InvariantTest } from "test/invariant/BasketManager.invariant.t.sol";

contract Staging_BasketManager_InvariantTest is BasketManager_InvariantTest {
    function _getForkBlockNumber() internal override returns (uint256) {
        return 22_231_107;
    }

    function _setupBasketManager() internal override returns (BasketManager) {
        return BasketManager(address(0xb87b81037957f421503565ef3C330423B8804246));
    }
}

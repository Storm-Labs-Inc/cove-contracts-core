// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BasketManager } from "src/BasketManager.sol";
import { BasketManager_InvariantTest } from "test/invariant/BasketManager.invariant.t.sol";

contract Staging_BasketManager_InvariantTest is BasketManager_InvariantTest {
    function _getForkBlockNumber() internal override returns (uint256) {
        return 22_155_634;
    }

    function _setupBasketManager() internal override returns (BasketManager) {
        return BasketManager(address(0xda845ffb8203fd844a55911304F24FCE5CCb62b4));
    }
}

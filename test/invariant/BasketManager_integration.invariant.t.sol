// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Deployments } from "script/Deployments.s.sol";
import { Deployments_Test } from "script/Deployments_Test.s.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketManager_InvariantTest } from "test/invariant/BasketManager.invariant.t.sol";

contract Integration_BasketManager_InvariantTest is BasketManager_InvariantTest {
    Deployments public deployments;

    function _getForkBlockNumber() internal override returns (uint256) {
        return BLOCK_NUMBER_MAINNET_FORK;
    }

    function _setupBasketManager() internal override returns (BasketManager) {
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);

        vm.pauseGasMetering();
        deployments = new Deployments_Test();
        deployments.deploy(false);
        vm.resumeGasMetering();

        return BasketManager(deployments.getAddress(deployments.buildBasketManagerName()));
    }
}

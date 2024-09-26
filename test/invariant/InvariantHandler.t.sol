// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { CommonBase } from "lib/forge-std/src/Base.sol";
import { StdCheats } from "lib/forge-std/src/StdCheats.sol";
import { StdUtils } from "lib/forge-std/src/StdUtils.sol";

contract InvariantHandler is CommonBase, StdCheats, StdUtils {
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }
}

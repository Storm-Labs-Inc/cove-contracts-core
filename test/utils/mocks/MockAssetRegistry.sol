// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract MockAssetRegistry {
    bool public paused;

    constructor() {
        paused = false;
    }

    function isPaused(address) public view returns (bool) {
        return paused;
    }

    function pauseAssets() public {
        paused = true;
    }
}

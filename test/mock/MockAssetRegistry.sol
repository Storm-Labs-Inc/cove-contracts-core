// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockAssetRegistry {
    bool public paused;

    constructor() {
        paused = false;
    }

    function isAssetsPaused(address asset) public view returns (bool) {
        return paused;
    }

    function pauseAssets() public {
        paused = true;
    }
}

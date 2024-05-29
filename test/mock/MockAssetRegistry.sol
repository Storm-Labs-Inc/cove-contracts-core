// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockAssetRegistry {
    constructor() { }

    function isAssetsPaused(address asset) public pure returns (bool) {
        return false;
    }
}

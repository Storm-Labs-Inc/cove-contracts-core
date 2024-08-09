// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

abstract contract TokenSwapAdapter {
    function executeTokenSwap(bytes calldata data) external virtual;
}

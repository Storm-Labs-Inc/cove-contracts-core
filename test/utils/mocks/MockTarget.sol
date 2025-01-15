// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract MockTarget {
    bytes public data;
    uint256 public value;

    fallback() external payable {
        // store calldata
        data = msg.data;
        value = msg.value;
    }

    function fail() external {
        revert("MockTarget: fail");
    }
}

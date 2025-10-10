// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract MockFeeCollector {
    address public protocolTreasury;

    constructor() { }

    function notifyHarvestFee(uint256) external { }

    function setProtocolTreasury(address p) external {
        protocolTreasury = p;
    }
}

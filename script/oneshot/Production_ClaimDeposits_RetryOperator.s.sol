// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { Constants } from "test/utils/Constants.t.sol";

interface IMulticall3 {
    struct Call {
        address target;
        bytes callData;
    }

    function aggregate(Call[] calldata calls)
        external
        payable
        returns (uint256 blockNumber, bytes[] memory returnData);
}

/**
 * @title Production call handleDeposit for all users
 * @notice Script to call handleDeposit for all users
 */
// solhint-disable var-name-mixedcase
contract ProductionClaimDepositsRetryOperator is Script, Constants {
    BasicRetryOperator public constant operator = BasicRetryOperator(0x10Fcf995e7b32Bb0D07bD84abEDdA09bD919345b);
    address public constant basketToken = 0xEeA3Edc017877C603E2F332FC1828a46432cdF96;
    IMulticall3.Call[] public calls;

    function run() public {
        address[] memory users = new address[](5);
        users[0] = 0xbA55BDbF959DF826dA6c35487eB15FaD2164662d;
        users[1] = 0xB93fcCb5a0873FBd1cD39e1310946636A2121E80;
        users[2] = 0x4B0aBA5b8501f215C2c13cC7ce4eF857d5a4F67C;
        users[3] = 0xD14f57283D1487f7bec9A3B4cCfed80930BBc91C;
        users[4] = 0x20a7cD00296933c7765f0187bd1d0763f394732B;
        for (uint256 i = 0; i < users.length; i++) {
            calls.push(
                IMulticall3.Call(
                    address(operator), abi.encodeWithSelector(operator.handleDeposit.selector, users[i], basketToken)
                )
            );
        }
        vm.startBroadcast();
        IMulticall3(MULTICALL3_ADDRESS).aggregate(calls);
    }
}

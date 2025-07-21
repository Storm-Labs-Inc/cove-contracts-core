pragma solidity 0.8.28;

import { ScenarioSimpleMedusa } from "test/invariant/handler/BasketManagerHandlers.medusa.t.sol";
import { UserHandler } from "test/invariant/handler/user/UserHandler.sol";

contract PoC is ScenarioSimpleMedusa {
    function test_run() public {
        uint256 initialBlockNumber = block.number;
        uint256 initialTimestamp = block.timestamp;

        initialBlockNumber += 20_000;
        vm.roll(initialBlockNumber);
        initialTimestamp += 549_645;
        vm.warp(initialTimestamp);
        UserHandler(address(users[0])).requestDeposit(
            5_789_604_463_550_806_437_875_464_237_601_083_835_602_226_150_384_349_728_381_664_980_464_632_123_584,
            7_026_321_498_347_728_795_864_961_600_429_507_962_362_555_567_597_844_054_450_512_944_083_650_990_567
        );

        initialBlockNumber += 32_514;
        vm.roll(initialBlockNumber);
        initialTimestamp += 101_425;
        vm.warp(initialTimestamp);
        rebalancer.proposeRebalancerOnAll();

        initialBlockNumber += 6;
        vm.roll(initialBlockNumber);
        initialTimestamp += 20;
        vm.warp(initialTimestamp);
        tokenSwap.proposeSmartSwap();

        initialBlockNumber += 7278;
        vm.roll(initialBlockNumber);
        initialTimestamp += 184_541;
        vm.warp(initialTimestamp);
        tokenSwap.completeRebalance();

        initialBlockNumber += 2774;
        vm.roll(initialBlockNumber);
        initialTimestamp += 155_894;
        vm.warp(initialTimestamp);
        tokenSwap.completeRebalance();

        initialBlockNumber += 1;
        vm.roll(initialBlockNumber);
        initialTimestamp += 496_758;
        vm.warp(initialTimestamp);
        oracleHandler.changePrice(
            0,
            true,
            57_255_957_001_664_785_445_506_798_303_655_167_941_300_976_719_989_083_528_468_989_618_841_117_758_116
        );

        tokenSwap.completeRebalance();

        initialBlockNumber += 7149;
        vm.roll(initialBlockNumber);
        initialTimestamp += 577_943;
        vm.warp(initialTimestamp);
        tokenSwap.proposeSmartSwap();

        initialBlockNumber += 59_403;
        vm.roll(initialBlockNumber);
        initialTimestamp += 360_464;
        vm.warp(initialTimestamp);
        tokenSwap.executeSwap();

        initialBlockNumber += 12_077;
        vm.roll(initialBlockNumber);
        initialTimestamp += 505_340;
        vm.warp(initialTimestamp);
        tokenSwap.completeRebalance();

        initialBlockNumber += 1;
        vm.roll(initialBlockNumber);
        initialTimestamp += 496_758;
        vm.warp(initialTimestamp);
        // Solve by adding a 1% approximation
        //invariant_ERC4626_totalAssets();
    }
}

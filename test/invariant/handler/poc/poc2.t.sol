pragma solidity 0.8.28;

import { ScenarioSimpleMedusa } from "test/invariant/handler/BasketManagerHandlers.medusa.t.sol";
import { UserHandler } from "test/invariant/handler/user/UserHandler.sol";

contract PoC2 is ScenarioSimpleMedusa {
    function test_run() public {
        uint256 initialBlockNumber = block.number;
        uint256 initialTimestamp = block.timestamp;

        initialBlockNumber += 20_000;
        vm.roll(initialBlockNumber);
        initialTimestamp += 549_645;
        vm.warp(initialTimestamp);
        UserHandler(address(users[0]))
            .requestDeposit(
                106_353_885_307_516_748_597_494_933_395_785_787_225_464_554_443_720_738_821_525_264_358_521_702_559,
                901_078_145_426_252_084_473_032_150_540_373_952_686_542_867_313_600_528_135_541_222_166_228_937_713
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
        initialBlockNumber += 20_286;
        vm.roll(initialBlockNumber);
        initialTimestamp += 140_796;
        vm.warp(initialTimestamp);
        UserHandler(address(users[0]))
            .requestDeposit(
                35_160_675_306_798_445_009_357_630_338_091_656_786_207_101_380_675_700_256_921_703_501_849_901_485_867,
                746_924_138_380_869_513_539_922_375_227_856_424_957_366_800_001_437_824_278_734_471_636_296_019_997
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

        invariant_assetConservation();
    }
}

pragma solidity 0.8.28;

import { ScenarioSimpleMedusa } from "test/invariant/handler/BasketManagerHandlers.medusa.t.sol";
import { UserHandler } from "test/invariant/handler/user/UserHandler.sol";

contract PoC3 is ScenarioSimpleMedusa {
    function test_run() public {
        uint256 initialBlockNumber = block.number;
        uint256 initialTimestamp = block.timestamp;

        initialBlockNumber += 23_885;
        vm.roll(initialBlockNumber);
        initialTimestamp += 513_357;
        vm.warp(initialTimestamp);
        UserHandler(address(users[0])).requestDeposit(
            11_368_215_470_135_573_355_832_369_236_667_639_281_458_567_779_220_673_096_298_536_582_112_867_377_003,
            96_493_407_779_613_724_886_964_575_936_685_175_655_027_449_396_067_739_288_327_967_511_950_820_284_698
        );
        initialBlockNumber += 23_874;
        vm.roll(initialBlockNumber);
        initialTimestamp += 187_924;
        vm.warp(initialTimestamp);

        rebalancer.proposeRebalancerOnAll();
        initialBlockNumber += 52_453;
        vm.roll(initialBlockNumber);
        initialTimestamp += 294_158;
        vm.warp(initialTimestamp);
        tokenSwap.proposeSmartSwap();

        tokenSwap.executeSwap();
        initialBlockNumber += 900;
        vm.roll(initialBlockNumber);
        initialTimestamp += 183_174;
        vm.warp(initialTimestamp);
        UserHandler(address(users[0])).claimFallbackShares(
            28_948_032_875_646_229_028_019_280_973_539_809_927_409_944_353_706_246_978_111_794_765_603_503_238_479
        );

        tokenSwap.completeRebalance();
        initialBlockNumber += 8941;
        vm.roll(initialBlockNumber);
        initialTimestamp += 323_204;
        vm.warp(initialTimestamp);
        tokenSwap.completeRebalance();
        initialBlockNumber += 47_725;
        vm.roll(initialBlockNumber);
        initialTimestamp += 360_405;
        vm.warp(initialTimestamp);
        tokenSwap.completeRebalance();
        initialBlockNumber += 980;
        vm.roll(initialBlockNumber);
        initialTimestamp += 1059;
        vm.warp(initialTimestamp);
        tokenSwap.completeRebalance();

        invariant_assetConservation();
    }
}

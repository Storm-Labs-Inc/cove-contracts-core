// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { BasketManager } from "src/BasketManager.sol";
import { BitFlag } from "src/libraries/BitFlag.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";

contract ManagedWeightStrategyTest is BaseTest {
    ManagedWeightStrategy public customStrategy;
    address public admin;
    address public basketManager;
    uint256 private constant _WEIGHT_PRECISION = 1e18;
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        basketManager = createUser("basketManager");
        vm.prank(admin);
        customStrategy = new ManagedWeightStrategy(admin, basketManager);
        vm.label(address(customStrategy), "ManagedWeightStrategy");
    }

    function testFuzz_constructor(address admin_, address basketManager_) public {
        vm.assume(admin_ != address(0));
        vm.assume(basketManager_ != address(0));
        ManagedWeightStrategy customStrategy_ = new ManagedWeightStrategy(admin_, basketManager_);
        assertTrue(
            customStrategy_.hasRole(customStrategy_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
        assertTrue(customStrategy_.hasRole(_MANAGER_ROLE, admin_), "Admin should have manager role");
    }

    function testFuzz_constructor_revertsWhen_ZeroAddress() public {
        vm.expectRevert(ManagedWeightStrategy.ZeroAddress.selector);
        new ManagedWeightStrategy(address(0), basketManager);
        vm.expectRevert(ManagedWeightStrategy.ZeroAddress.selector);
        new ManagedWeightStrategy(admin, address(0));
    }

    function testFuzz_setTargetWeights(
        uint40 epoch,
        uint256 bitFlag
    )
        public
        returns (uint64[] memory newTargetWeights)
    {
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        uint64[] memory weights = new uint64[](BitFlag.popCount(bitFlag));
        newTargetWeights = new uint64[](weights.length);
        uint256 limit = _WEIGHT_PRECISION;
        for (uint256 i = 0; i < weights.length; i++) {
            if (i < weights.length - 1) {
                limit -= newTargetWeights[i] = weights[i] = uint64(bound(weights[i], 0, limit));
            } else {
                newTargetWeights[i] = weights[i] = uint64(limit);
            }
        }

        vm.mockCall(
            basketManager,
            abi.encodeCall(BasketManager.rebalanceStatus, ()),
            abi.encode(
                RebalanceStatus({
                    basketHash: bytes32(0),
                    basketMask: uint256(0),
                    epoch: epoch,
                    proposalTimestamp: uint40(0),
                    timestamp: uint40(0),
                    retryCount: uint8(0),
                    status: Status.NOT_STARTED
                })
            )
        );

        vm.prank(admin);
        customStrategy.setTargetWeights(bitFlag, newTargetWeights);

        for (uint256 i = 0; i < weights.length; i++) {
            assertEq(
                customStrategy.getTargetWeights(bitFlag)[i],
                newTargetWeights[i],
                string(abi.encodePacked("Weight ", vm.toString(i), " should be set correctly"))
            );
        }
    }

    function testFuzz_setTargetWeights_RebalanceStarted(
        uint40 epoch,
        uint256 bitFlag,
        uint8 status
    )
        public
        returns (uint64[] memory newTargetWeights)
    {
        vm.assume(status <= uint8(type(Status).max));
        vm.assume(Status(status) != Status.NOT_STARTED);
        vm.assume(epoch < type(uint40).max);
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        uint64[] memory weights = new uint64[](BitFlag.popCount(bitFlag));
        newTargetWeights = new uint64[](weights.length);
        uint256 limit = _WEIGHT_PRECISION;
        for (uint256 i = 0; i < weights.length; i++) {
            if (i < weights.length - 1) {
                limit -= newTargetWeights[i] = weights[i] = uint64(bound(weights[i], 0, limit));
            } else {
                newTargetWeights[i] = weights[i] = uint64(limit);
            }
        }

        vm.mockCall(
            basketManager,
            abi.encodeCall(BasketManager.rebalanceStatus, ()),
            abi.encode(
                RebalanceStatus({
                    basketHash: bytes32(0),
                    basketMask: uint256(0),
                    epoch: epoch,
                    proposalTimestamp: uint40(0),
                    timestamp: uint40(0),
                    retryCount: uint8(0),
                    status: Status(status)
                })
            )
        );

        vm.prank(admin);
        customStrategy.setTargetWeights(bitFlag, newTargetWeights);

        for (uint256 i = 0; i < weights.length; i++) {
            assertEq(
                customStrategy.getTargetWeights(bitFlag)[i],
                newTargetWeights[i],
                string(abi.encodePacked("Weight ", vm.toString(i), " should be set correctly"))
            );
        }
    }

    function testFuzz_setTargetWeights_InvalidLength(uint256 bitFlag) public {
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        uint64[] memory weights = new uint64[](BitFlag.popCount(bitFlag) + 1);

        vm.prank(admin);
        vm.expectRevert(ManagedWeightStrategy.InvalidWeightsLength.selector);
        customStrategy.setTargetWeights(bitFlag, weights);
    }

    function testFuzz_setTargetWeights_revertWhen_notManager(address sender, uint256 bitFlag) public {
        vm.assume(!customStrategy.hasRole(_MANAGER_ROLE, sender));
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        uint64[] memory weights = new uint64[](BitFlag.popCount(bitFlag));

        vm.expectRevert(_formatAccessControlError(sender, _MANAGER_ROLE));
        vm.prank(sender);
        customStrategy.setTargetWeights(bitFlag, weights);
    }

    function testFuzz_setTargetWeights_InvalidSum(uint256 bitFlag, uint256 sum) public {
        vm.assume(sum != _WEIGHT_PRECISION);
        vm.assume(BitFlag.popCount(bitFlag) >= 2);

        uint64[] memory weights = new uint64[](BitFlag.popCount(bitFlag));
        for (uint256 i = 0; i < weights.length; i++) {
            if (i < weights.length - 1) {
                sum -= weights[i] = uint64(bound(weights[i], 0, sum));
            } else {
                weights[i] = uint64(sum);
            }
        }

        vm.prank(admin);
        vm.expectRevert(ManagedWeightStrategy.WeightsSumMismatch.selector);
        customStrategy.setTargetWeights(bitFlag, weights);
    }

    function testFuzz_setTargetWeights_UnsupportedBitFlag(uint256 bitFlag) public {
        uint256 assetCount = BitFlag.popCount(bitFlag);
        vm.assume(assetCount < 2);
        vm.expectRevert(ManagedWeightStrategy.UnsupportedBitFlag.selector);
        vm.prank(admin);
        customStrategy.setTargetWeights(bitFlag, new uint64[](assetCount));
    }

    function testFuzz_getTargetWeights(uint40 epoch, uint256 bitFlag) public {
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        uint64[] memory newTargetWeights = testFuzz_setTargetWeights(epoch, bitFlag);
        uint64[] memory retrievedWeights = customStrategy.getTargetWeights(bitFlag);

        // assertEq(retrievedWeights, newTargetWeights, "Retrieved weights should match set weights");
        assertEq(
            retrievedWeights.length,
            newTargetWeights.length,
            "Retrieved weights should have the same length as set weights"
        );
        for (uint256 i = 0; i < newTargetWeights.length; i++) {
            assertEq(
                retrievedWeights[i],
                newTargetWeights[i],
                string(abi.encodePacked("Weight ", vm.toString(i), " should be retrieved correctly"))
            );
        }
    }

    function test_getTargetWeights_UnsupportedBitFlag(uint256 bitFlag) public {
        vm.assume(BitFlag.popCount(bitFlag) < 2);
        vm.expectRevert(ManagedWeightStrategy.UnsupportedBitFlag.selector);
        customStrategy.getTargetWeights(bitFlag);
    }

    function testFuzz_supportsBitFlag_returnsFalse(uint256 bitFlag) public {
        assertFalse(
            customStrategy.supportsBitFlag(bitFlag), "supportsBitFlag should return false if the weights are not set"
        );
    }

    function testFuzz_supportsBitFlag_returnsTrue(uint40 epoch, uint256 bitFlag) public {
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        testFuzz_setTargetWeights(epoch, bitFlag);
        assertTrue(customStrategy.supportsBitFlag(bitFlag), "supportsBitFlag should return true if the weights are set");
    }

    function testFuzz_getTargetWeights_NoTargetWeights(uint256 bitFlag) public {
        vm.assume(BitFlag.popCount(bitFlag) >= 2);
        vm.expectRevert(ManagedWeightStrategy.NoTargetWeights.selector);
        customStrategy.getTargetWeights(bitFlag);
    }

    function testFuzz_setTargetWeightsMulticall(uint40 epoch, uint256 bitFlag0, uint256 bitFlag1) public {
        vm.assume(BitFlag.popCount(bitFlag0) >= 2);
        vm.assume(BitFlag.popCount(bitFlag1) >= 2);
        vm.assume(bitFlag0 != bitFlag1);

        uint64[] memory weights0 = new uint64[](BitFlag.popCount(bitFlag0));
        uint64[] memory weights1 = new uint64[](BitFlag.popCount(bitFlag1));
        uint64[] memory newTargetWeights0 = new uint64[](weights0.length);
        uint256 limit = _WEIGHT_PRECISION;
        for (uint256 i = 0; i < weights0.length; i++) {
            if (i < weights0.length - 1) {
                limit -= newTargetWeights0[i] = weights0[i] = uint64(bound(weights0[i], 0, limit));
            } else {
                newTargetWeights0[i] = weights0[i] = uint64(limit);
            }
        }

        uint64[] memory newTargetWeights1 = new uint64[](weights1.length);
        for (uint256 i = 0; i < weights1.length; i++) {
            if (i < weights1.length - 1) {
                limit -= newTargetWeights1[i] = weights1[i] = uint64(bound(weights1[i], 0, limit));
            } else {
                newTargetWeights1[i] = weights1[i] = uint64(limit);
            }
        }

        vm.mockCall(
            basketManager,
            abi.encodeCall(BasketManager.rebalanceStatus, ()),
            abi.encode(
                RebalanceStatus({
                    basketHash: bytes32(0),
                    basketMask: uint256(0),
                    epoch: epoch,
                    proposalTimestamp: uint40(0),
                    timestamp: uint40(0),
                    retryCount: uint8(0),
                    status: Status.NOT_STARTED
                })
            )
        );

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(ManagedWeightStrategy.setTargetWeights.selector, bitFlag0, newTargetWeights0);
        data[1] = abi.encodeWithSelector(ManagedWeightStrategy.setTargetWeights.selector, bitFlag1, newTargetWeights1);

        vm.prank(admin);
        customStrategy.multicall(data);

        for (uint256 i = 0; i < weights0.length; i++) {
            assertEq(
                customStrategy.getTargetWeights(bitFlag0)[i],
                newTargetWeights0[i],
                string(abi.encodePacked("Weight ", vm.toString(i), " should be set correctly"))
            );
        }
        for (uint256 i = 0; i < weights1.length; i++) {
            assertEq(
                customStrategy.getTargetWeights(bitFlag1)[i],
                newTargetWeights1[i],
                string(abi.encodePacked("Weight ", vm.toString(i), " should be set correctly"))
            );
        }
    }
}

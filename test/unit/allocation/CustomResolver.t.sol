// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { CustomAllocationResolver } from "src/allocation/CustomResolver.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract CustomAllocationResolverTest is BaseTest {
    CustomAllocationResolver public customResolver;
    address public admin;
    uint256 public constant SUPPORTED_BIT_FLAG = 1 << 0 | 1 << 1 | 1 << 2; // b111

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.prank(admin);
        customResolver = new CustomAllocationResolver(admin, SUPPORTED_BIT_FLAG);
        vm.label(address(customResolver), "customResolver");
    }

    function testFuzz_setTargetWeights(uint256[3] memory weights) public {
        uint256[] memory newTargetWeights = new uint256[](3);
        uint256 limit = 1e18;
        for (uint256 i = 0; i < 3; i++) {
            if (i < 2) {
                limit -= newTargetWeights[i] = bound(weights[i], 0, limit);
            } else {
                newTargetWeights[i] = limit;
            }
        }

        vm.prank(admin);
        customResolver.setTargetWeights(newTargetWeights);

        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                customResolver.targetWeights(i),
                newTargetWeights[i],
                string(abi.encodePacked("Weight ", i, " should be set correctly"))
            );
        }
    }

    function testFuzz_setTargetWeights_InvalidLength(uint256 length) public {
        vm.assume(length != 3 && length < type(uint16).max);
        uint256[] memory newTargetWeights = new uint256[](length);

        vm.prank(admin);
        vm.expectRevert(CustomAllocationResolver.InvalidWeightsLength.selector);
        customResolver.setTargetWeights(newTargetWeights);
    }

    function testFuzz_setTargetWeights_InvalidSum(uint256[3] memory weights, uint256 sum) public {
        uint256[] memory newTargetWeights = new uint256[](3);
        vm.assume(sum != 1e18);
        for (uint256 i = 0; i < 3; i++) {
            if (i < 2) {
                weights[i] = bound(weights[i], 0, sum);
                sum -= weights[i];
            } else {
                newTargetWeights[i] = sum;
            }
        }

        vm.prank(admin);
        vm.expectRevert(CustomAllocationResolver.WeightsSumMismatch.selector);
        customResolver.setTargetWeights(newTargetWeights);
    }

    function testFuzz_getTargetWeights(uint256[3] memory weights) public {
        uint256[] memory setWeights = new uint256[](3);
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < 3; i++) {
            weights[i] = bound(weights[i], 1, 1e18);
            totalWeight += weights[i];
        }
        for (uint256 i = 0; i < 2; i++) {
            setWeights[i] = (weights[i] * 1e18) / totalWeight;
        }
        // Ensure the sum is exactly 1e18
        setWeights[2] = 1e18 - setWeights[0] - setWeights[1];

        vm.prank(admin);
        customResolver.setTargetWeights(setWeights);

        uint256[] memory retrievedWeights = customResolver.getTargetWeights(SUPPORTED_BIT_FLAG);

        assertEq(retrievedWeights.length, 3, "Retrieved weights should have length 3");
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                retrievedWeights[i], setWeights[i], string(abi.encodePacked("Weight ", i, " should match set weight"))
            );
        }
    }

    function testFuzz_supportsBitFlag(uint256 bitFlag) public {
        vm.assume(bitFlag <= SUPPORTED_BIT_FLAG);
        assertTrue(customResolver.supportsBitFlag(bitFlag), "Should support the configured bit flag or lower");
    }

    function testFuzz_getTargetWeights_UnsupportedBitFlag(uint256 bitFlag) public {
        vm.assume(bitFlag > SUPPORTED_BIT_FLAG);
        vm.expectRevert(CustomAllocationResolver.UnsupportedBitFlag.selector);
        customResolver.getTargetWeights(bitFlag);
    }
}

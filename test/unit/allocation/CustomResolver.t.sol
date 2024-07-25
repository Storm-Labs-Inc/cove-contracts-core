// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { CustomAllocationResolver } from "src/allocation/CustomResolver.sol";

import { BitFlag } from "src/libraries/BitFlag.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract CustomAllocationResolverTest is BaseTest {
    CustomAllocationResolver public customResolver;
    address public admin;
    uint256 public constant SUPPORTED_BIT_FLAG = 1 << 0 | 1 << 1 | 1 << 2; // b111
    uint256 private constant _WEIGHT_PRECISION = 1e18;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.prank(admin);
        customResolver = new CustomAllocationResolver(admin, SUPPORTED_BIT_FLAG);
        vm.label(address(customResolver), "customResolver");
    }

    function testFuzz_constructor(address admin_, uint256 bitFlag) public {
        CustomAllocationResolver customResolver_ = new CustomAllocationResolver(admin_, bitFlag);
        assertTrue(
            customResolver_.hasRole(customResolver_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
        assertEq(customResolver_.supportedBitFlag(), bitFlag, "Supported bit flag should be set correctly");
    }

    function testFuzz_setTargetWeights(uint256[3] memory weights) public returns (uint256[] memory newTargetWeights) {
        newTargetWeights = new uint256[](3);
        uint256 limit = _WEIGHT_PRECISION;
        for (uint256 i = 0; i < 3; i++) {
            if (i < 2) {
                limit -= newTargetWeights[i] = weights[i] = bound(weights[i], 0, limit);
            } else {
                newTargetWeights[i] = weights[i] = limit;
            }
        }

        vm.prank(admin);
        customResolver.setTargetWeights(newTargetWeights);

        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                customResolver.targetWeights(i),
                newTargetWeights[i],
                string(abi.encodePacked("Weight ", vm.toString(i), " should be set correctly"))
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
        vm.assume(sum != _WEIGHT_PRECISION);
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
        uint256[] memory newTargetWeights = testFuzz_setTargetWeights(weights);
        uint256[] memory retrievedWeights = customResolver.getTargetWeights(SUPPORTED_BIT_FLAG);

        assertEq(retrievedWeights, newTargetWeights, "Retrieved weights should match set weights");
    }

    function testFuzz_getTargetWeights_SubSet(uint256[3] memory weights, uint256 bitFlag) public {
        testFuzz_setTargetWeights(weights);
        bitFlag = bound(bitFlag, 1, SUPPORTED_BIT_FLAG);
        uint256[] memory retrievedWeights = customResolver.getTargetWeights(bitFlag);

        // Verify the sum of the weights equals _WEIGHT_PRECISION
        uint256 sum = 0;
        for (uint256 i = 0; i < retrievedWeights.length; i++) {
            sum += retrievedWeights[i];
        }
        assertEq(sum, _WEIGHT_PRECISION, "Sum of weights should be _WEIGHT_PRECISION");
    }

    function test_getTargetWeights_Zero(uint256[3] memory weights) public {
        testFuzz_setTargetWeights(weights);
        uint256[] memory retrievedWeights = customResolver.getTargetWeights(0);

        // Verify its empty
        assertEq(retrievedWeights.length, 0, "Retrieved weights should be empty");
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

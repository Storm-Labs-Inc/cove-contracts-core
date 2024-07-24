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

    function test_setTargetWeights() public {
        uint256[] memory newTargetWeights = new uint256[](3);
        newTargetWeights[0] = 5e17; // 0.5 in fixed-point
        newTargetWeights[1] = 3e17; // 0.3 in fixed-point
        newTargetWeights[2] = 2e17; // 0.2 in fixed-point

        vm.prank(admin);
        customResolver.setTargetWeights(newTargetWeights);

        assertEq(customResolver.targetWeights(0), 5e17, "First weight should be set to 0.5");
        assertEq(customResolver.targetWeights(1), 3e17, "Second weight should be set to 0.3");
        assertEq(customResolver.targetWeights(2), 2e17, "Third weight should be set to 0.2");
    }

    function test_setTargetWeights_InvalidLength() public {
        uint256[] memory newTargetWeights = new uint256[](2);
        newTargetWeights[0] = 5e17;
        newTargetWeights[1] = 5e17;

        vm.prank(admin);
        vm.expectRevert(CustomAllocationResolver.InvalidWeightsLength.selector);
        customResolver.setTargetWeights(newTargetWeights);
    }

    function test_setTargetWeights_InvalidSum() public {
        uint256[] memory newTargetWeights = new uint256[](3);
        newTargetWeights[0] = 6e17;
        newTargetWeights[1] = 3e17;
        newTargetWeights[2] = 2e17;

        vm.prank(admin);
        vm.expectRevert(CustomAllocationResolver.WeightsSumMismatch.selector);
        customResolver.setTargetWeights(newTargetWeights);
    }

    function test_getTargetWeights() public {
        uint256[] memory setWeights = new uint256[](3);
        setWeights[0] = 5e17;
        setWeights[1] = 3e17;
        setWeights[2] = 2e17;

        vm.prank(admin);
        customResolver.setTargetWeights(setWeights);

        uint256[] memory retrievedWeights = customResolver.getTargetWeights(SUPPORTED_BIT_FLAG);

        assertEq(retrievedWeights.length, 3, "Retrieved weights should have length 3");
        assertEq(retrievedWeights[0], 5e17, "First weight should be 0.5");
        assertEq(retrievedWeights[1], 3e17, "Second weight should be 0.3");
        assertEq(retrievedWeights[2], 2e17, "Third weight should be 0.2");
    }

    function testFuzz_supportsBitFlag(uint256 bitFlag) public {
        vm.assume(bitFlag <= SUPPORTED_BIT_FLAG);
        assertTrue(customResolver.supportsBitFlag(bitFlag), "Should support the configured bit flag or lower");
    }

    function test_getTargetWeights_UnsupportedBitFlag(uint256 bitFlag) public {
        vm.assume(bitFlag > SUPPORTED_BIT_FLAG);
        vm.expectRevert(CustomAllocationResolver.UnsupportedBitFlag.selector);
        customResolver.getTargetWeights(bitFlag);
    }
}

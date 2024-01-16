// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { OracleRegistry } from "src/OracleRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";

contract OracleRegistry_Test is BaseTest {
    OracleRegistry public oracleRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    function setUp() public override {
        super.setUp();
        createUser("admin");
        createUser("alice");
        vm.startPrank(users["admin"]);
        oracleRegistry = new OracleRegistry(users["admin"]);
        adminRole = oracleRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = keccak256("MANAGER_ROLE");
    }

    function test_init() public view {
        assert(oracleRegistry.hasRole(adminRole, users["admin"]));
        assert(oracleRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_addOracle_revertWhen_CalledWithEmptyString(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        oracleRegistry.addOracle("", addr);
    }

    function test_addOracle_revertWhen_CalledWithEmptyAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        oracleRegistry.addOracle(name, address(0));
    }

    function test_addOracle_revertWhen_CalledWithDuplicateAddress(bytes32 name, bytes32 name2, address addr) public {
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        oracleRegistry.addOracle(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateOracleAddress.selector, addr));
        oracleRegistry.addOracle(name2, addr);
    }

    function test_addOracle_revertWhen_CalledWithDuplicateName(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));

        oracleRegistry.addOracle(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleNameFound.selector, name));
        oracleRegistry.addOracle(name, addr2);
    }

    function testFuzz_updateOracle_revertWhen_CalledWithEmptyString(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        oracleRegistry.updateOracle("", addr);
    }

    function testFuzz_updateOracle_revertWhen_CalledWithEmptyAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        oracleRegistry.updateOracle(name, address(0));
    }

    function testFuzz_updateOracle_revertWhen_CalledWithDuplicateAddress(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2
    )
        public
    {
        vm.assume(addr != addr2);
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        oracleRegistry.addOracle(name, addr);
        oracleRegistry.addOracle(name2, addr2);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateOracleAddress.selector, addr2));
        oracleRegistry.updateOracle(name, addr2);
    }

    function test_updateOracle_revertWhen_NameNotFound(bytes32 name, address addr) public {
        vm.assume(addr != address(0));
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleNameNotFound.selector, name));
        oracleRegistry.updateOracle(name, addr);
    }

    function testFuzz_addOracle(bytes32 name, address addr) public {
        vm.assume(addr != address(0));
        vm.assume(name != bytes32(0));
        oracleRegistry.addOracle(name, addr);
        assertEq(oracleRegistry.resolveNameToLatestAddress(name), addr);
    }

    function testFuzz_updateOracle(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(name != bytes32(0));
        vm.assume(addr != addr2);
        oracleRegistry.addOracle(name, addr);
        oracleRegistry.updateOracle(name, addr2);
        assertEq(oracleRegistry.resolveNameToLatestAddress(name), addr2);
    }

    function testFuzz_resolveNameToLatestAddress_revertWhen_NameNotFound(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleNameNotFound.selector, name));
        oracleRegistry.resolveNameToLatestAddress(name);
    }

    function testFuzz_resolveNameToAllAddresses(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        oracleRegistry.addOracle(name, addr);
        oracleRegistry.updateOracle(name, addr2);
        address[] memory res = oracleRegistry.resolveNameToAllAddresses(name);
        assertEq(res[0], addr);
        assertEq(res[1], addr2);
    }

    function testFuzz_resolveNameToAllAddresses_revertWhen_NamNotFound(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleNameNotFound.selector, name));
        oracleRegistry.resolveNameToAllAddresses(name);
    }

    function testFuzz_resolveNameAndVersionToAddress_revertWhen_NameAndVersionNotFound(
        bytes32 name,
        address addr
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleNameVersionNotFound.selector, name, 0));
        oracleRegistry.resolveNameAndVersionToAddress(name, 0);
        oracleRegistry.addOracle(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleNameVersionNotFound.selector, name, 1));
        oracleRegistry.resolveNameAndVersionToAddress(name, 1);
    }

    function testFuzz_resolveNameAndVersionToAddress(bytes32 name, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        oracleRegistry.addOracle(name, addr);
        oracleRegistry.updateOracle(name, addr2);
        assertEq(oracleRegistry.resolveNameAndVersionToAddress(name, 0), addr);
        assertEq(oracleRegistry.resolveNameAndVersionToAddress(name, 1), addr2);
    }

    function testFuzz_resolveAddressToOracleData_revertWhen_OracleAddressNotFound(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleAddressNotFound.selector, addr));
        oracleRegistry.resolveAddressToOracleData(addr);
    }

    function testFuzz_resolveAddressToOracleData(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address addr3
    )
        public
    {
        // Assume non-zero
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr3 != address(0));
        // Assume not equal
        vm.assume(name != name2);
        vm.assume(addr != addr2);
        vm.assume(addr2 != addr3);
        vm.assume(addr != addr3);
        oracleRegistry.addOracle(name, addr);
        oracleRegistry.updateOracle(name, addr2);
        oracleRegistry.addOracle(name2, addr3);
        (bytes32 resloveName, uint256 version, bool isLatest) = oracleRegistry.resolveAddressToOracleData(addr);
        assertEq(resloveName, name);
        assertEq(version, 0);
        assertEq(isLatest, false);
        (resloveName, version, isLatest) = oracleRegistry.resolveAddressToOracleData(addr2);
        assertEq(resloveName, name);
        assertEq(version, 1);
        assertEq(isLatest, true);
        (resloveName, version, isLatest) = oracleRegistry.resolveAddressToOracleData(addr3);
        assertEq(resloveName, name2);
        assertEq(version, 0);
        assertEq(isLatest, true);
    }

    function test_getRoleAdmin_managerRole() public {
        assertEq(oracleRegistry.getRoleAdmin(managerRole), bytes32(0));
    }

    function testFuzz_addOracle_revertWhen_CalledByNonManager(bytes32 name, address addr) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // TODO: fix issue with format of access control error
        // vm.expectRevert(_formatAccessControlError(users["alice"], managerRole));
        vm.expectRevert();
        oracleRegistry.addOracle(name, addr);
    }

    function testFuzz_updateOracle_revertWhen_CalledByNonManager(bytes32 name, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        oracleRegistry.addOracle(name, addr);
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // TODO: fix issue with format of access control error
        // vm.expectRevert(_formatAccessControlError(users["alice"], managerRole));
        vm.expectRevert();
        oracleRegistry.updateOracle(name, addr2);
    }

    // Try granting manager role from an account without admin role
    function test_grantRole_revertWhen_CalledByNonAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        // TODO: fix issue with format of access control error
        // vm.expectRevert(_formatAccessControlError(users["alice"], adminRole));
        vm.expectRevert();
        oracleRegistry.grantRole(managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function test_grantRole_managerRole() public {
        // Check the user does not have the manager role
        assert(!oracleRegistry.hasRole(managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        oracleRegistry.grantRole(managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(oracleRegistry.hasRole(managerRole, users["alice"]));
    }

    function test_grantRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!oracleRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        oracleRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(oracleRegistry.hasRole(adminRole, users["alice"]));

        // Verify the user can grant the manager role
        vm.stopPrank();
        vm.prank(users["alice"]);
        oracleRegistry.grantRole(managerRole, users["bob"]);
    }

    function test_revokeRole_managerRole_revertWhen_RevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        // TODO: fix issue with format of access control error
        // vm.expectRevert(_formatAccessControlError(users["alice"], adminRole));
        vm.expectRevert();
        oracleRegistry.revokeRole(managerRole, users["admin"]);
        vm.stopPrank();
    }

    function test_revokeRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!oracleRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        oracleRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(oracleRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        oracleRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!oracleRegistry.hasRole(adminRole, users["alice"]));
    }

    function test_revokeRoleF_adminRole() public {
        // Check the user does not have the admin role
        assert(!oracleRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner

        oracleRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(oracleRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        vm.stopPrank();
        vm.prank(users["alice"]);
        oracleRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!oracleRegistry.hasRole(adminRole, users["alice"]));
    }

    function test_renouceRole_managerRole() public {
        // Check the admin has the manager role
        assert(oracleRegistry.hasRole(managerRole, users["admin"]));

        // Renouce the manager role from the admin
        oracleRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!oracleRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_renouceRole_adminRole() public {
        // Check the user has the admin role
        assert(oracleRegistry.hasRole(adminRole, users["admin"]));

        // Renouce the admin role from the admin
        oracleRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!oracleRegistry.hasRole(adminRole, users["admin"]));
    }

    function testFuzz_multicall_addOracle(bytes32 name, bytes32 name2, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(name != name2);
        vm.assume(addr != addr2);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(oracleRegistry.addOracle.selector, name, addr);
        calls[1] = abi.encodeWithSelector(oracleRegistry.addOracle.selector, name2, addr2);
        oracleRegistry.multicall(calls);
        assertEq(oracleRegistry.resolveNameToLatestAddress(name), addr);
        assertEq(oracleRegistry.resolveNameToLatestAddress(name2), addr2);
    }

    function testFuzz_multicall_updateOracle(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address addr3,
        address addr4
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr3 != address(0));
        vm.assume(addr4 != address(0));
        vm.assume(name != name2);
        vm.assume(addr != addr2);
        vm.assume(addr != addr3);
        vm.assume(addr != addr4);
        vm.assume(addr2 != addr3);
        vm.assume(addr2 != addr4);
        vm.assume(addr3 != addr4);
        oracleRegistry.addOracle(name, addr);
        oracleRegistry.addOracle(name2, addr2);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(oracleRegistry.updateOracle.selector, name, addr3);
        calls[1] = abi.encodeWithSelector(oracleRegistry.updateOracle.selector, name2, addr4);
        oracleRegistry.multicall(calls);
        assertEq(oracleRegistry.resolveNameAndVersionToAddress(name, 0), addr);
        assertEq(oracleRegistry.resolveNameAndVersionToAddress(name2, 0), addr2);
        assertEq(oracleRegistry.resolveNameToLatestAddress(name), addr3);
        assertEq(oracleRegistry.resolveNameToLatestAddress(name2), addr4);
    }
}

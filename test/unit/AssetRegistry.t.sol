// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { AssetRegistry } from "src/AssetRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract AssetRegistry_Test is BaseTest {
    AssetRegistry public assetRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    function setUp() public override {
        super.setUp();
        createUser("admin");
        createUser("alice");
        vm.startPrank(users["admin"]);
        assetRegistry = new AssetRegistry(users["admin"]);
        adminRole = assetRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = keccak256("MANAGER_ROLE");
    }

    function test_init() public view {
        assert(assetRegistry.hasRole(adminRole, users["admin"]));
        assert(assetRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_constructor_revertWhen_zeroAddressAdmin() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        assetRegistry = new AssetRegistry(address(0));
    }

    // Try granting manager role from an account without admin role
    function test_grantRole_revertWhen_CalledByNonAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        // TODO: fix issue with format of access control error
        // vm.expectRevert(_formatAccessControlError(users["alice"], adminRole));
        vm.expectRevert();
        assetRegistry.grantRole(managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function test_grantRole_managerRole() public {
        // Check the user does not have the manager role
        assert(!assetRegistry.hasRole(managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        assetRegistry.grantRole(managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(assetRegistry.hasRole(managerRole, users["alice"]));
    }

    function test_grantRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!assetRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        assetRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(assetRegistry.hasRole(adminRole, users["alice"]));

        // Verify the user can grant the manager role
        vm.stopPrank();
        vm.prank(users["alice"]);
        assetRegistry.grantRole(managerRole, users["bob"]);
    }

    function test_revokeRole_managerRole_revertWhen_RevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        // TODO: fix issue with format of access control error
        // vm.expectRevert(_formatAccessControlError(users["alice"], adminRole));
        vm.expectRevert();
        assetRegistry.revokeRole(managerRole, users["admin"]);
        vm.stopPrank();
    }

    function test_revokeRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!assetRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        assetRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(assetRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        assetRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!assetRegistry.hasRole(adminRole, users["alice"]));
    }

    function test_revokeRoleF_adminRole() public {
        // Check the user does not have the admin role
        assert(!assetRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner

        assetRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(assetRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        vm.stopPrank();
        vm.prank(users["alice"]);
        assetRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!assetRegistry.hasRole(adminRole, users["alice"]));
    }

    function test_renounceRole_managerRole() public {
        // Check the admin has the manager role
        assert(assetRegistry.hasRole(managerRole, users["admin"]));

        // Renounce the manager role from the admin
        assetRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!assetRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_renounceRole_adminRole() public {
        // Check the user has the admin role
        assert(assetRegistry.hasRole(adminRole, users["admin"]));

        // Renounce the admin role from the admin
        assetRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!assetRegistry.hasRole(adminRole, users["admin"]));
    }

    function test_addAsset_revertWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        assetRegistry.addAsset(address(0));
    }

    function testFuzz_addAsset_revertWhen_alreadyEnabled(address asset) public {
        vm.assume(asset != address(0));

        vm.expectEmit();
        emit AssetRegistry.AddAsset(asset);
        assetRegistry.addAsset(asset);

        vm.expectRevert(AssetRegistry.AssetAlreadyEnabled.selector);
        assetRegistry.addAsset(asset);
    }

    function testFuzz_addAsset(address asset) public {
        vm.assume(asset != address(0));

        vm.expectEmit();
        emit AssetRegistry.AddAsset(asset);
        assetRegistry.addAsset(asset);

        _assertAssetStatus(asset, AssetRegistry.AssetState.ENABLED);
    }

    function test_setAssetState_revertWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        assetRegistry.setAssetState(address(0), AssetRegistry.AssetState.PAUSED);
    }

    function testFuzz_setAssetState_revertWhen_notEnabled(address asset) public {
        vm.assume(asset != address(0));

        vm.expectRevert(AssetRegistry.AssetNotEnabled.selector);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.PAUSED);
    }

    function testFuzz_setAssetState_pause(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);

        vm.expectEmit();
        emit AssetRegistry.SetAssetState(asset, AssetRegistry.AssetState.PAUSED);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.PAUSED);

        _assertAssetStatus(asset, AssetRegistry.AssetState.PAUSED);
    }

    function testFuzz_setAssetState_unpause(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.PAUSED);

        vm.expectEmit();
        emit AssetRegistry.SetAssetState(asset, AssetRegistry.AssetState.ENABLED);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.ENABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetState.ENABLED);
    }

    function testFuzz_setAssetState_revertWhen_noStateChange(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);

        // Attempt to set state to ENABLED when it's already ENABLED
        vm.expectRevert(AssetRegistry.AssetInvalidStateUpdate.selector);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.ENABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetState.ENABLED);

        // Pause the asset
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.PAUSED);

        // Attempt to set state to PAUSED when it's already PAUSED
        vm.expectRevert(AssetRegistry.AssetInvalidStateUpdate.selector);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.PAUSED);

        _assertAssetStatus(asset, AssetRegistry.AssetState.PAUSED);
    }

    function testFuzz_setAssetState_revertWhen_settingToDisabled(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);

        vm.expectRevert(AssetRegistry.AssetInvalidStateUpdate.selector);
        assetRegistry.setAssetState(asset, AssetRegistry.AssetState.DISABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetState.ENABLED);
    }

    function _assertAssetStatus(address asset, AssetRegistry.AssetState expectedState) internal view {
        AssetRegistry.AssetStatus memory status = assetRegistry.getAssetStatus(asset);
        assertEq(uint256(status.state), uint256(expectedState));
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { AssetRegistry } from "src/AssetRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract AssetRegistry_Test is BaseTest {
    AssetRegistry public assetRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    uint256 public constant MAX_ASSETS = 255;

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

    function test_addAsset_revertWhen_maxAssetsReached() public {
        for (uint256 i = 0; i < MAX_ASSETS; i++) {
            assetRegistry.addAsset(address(uint160(i + 1)));
        }

        vm.expectRevert(AssetRegistry.MaxAssetsReached.selector);
        assetRegistry.addAsset(address(uint160(MAX_ASSETS + 1)));
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

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
    }

    function test_setAssetStatus_revertWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        assetRegistry.setAssetStatus(address(0), AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_revertWhen_notEnabled(address asset) public {
        vm.assume(asset != address(0));

        vm.expectRevert(AssetRegistry.AssetNotEnabled.selector);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_pause(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);

        vm.expectEmit();
        emit AssetRegistry.SetAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_unpause(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        vm.expectEmit();
        emit AssetRegistry.SetAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
    }

    function testFuzz_setAssetStatus_revertWhen_noStatusChange(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);

        // Attempt to set status to ENABLED when it's already ENABLED
        vm.expectRevert(AssetRegistry.AssetInvalidStatusUpdate.selector);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);

        // Pause the asset
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        // Attempt to set status to PAUSED when it's already PAUSED
        vm.expectRevert(AssetRegistry.AssetInvalidStatusUpdate.selector);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_revertWhen_settingToDisabled(address asset) public {
        vm.assume(asset != address(0));

        assetRegistry.addAsset(asset);

        vm.expectRevert(AssetRegistry.AssetInvalidStatusUpdate.selector);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.DISABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
    }

    function _assertAssetStatus(address asset, AssetRegistry.AssetStatus expectedStatus) internal view {
        assertEq(uint256(assetRegistry.getAssetStatus(asset)), uint256(expectedStatus));
    }

    function _setupAssets(uint256 assetCount) internal returns (address[] memory) {
        address[] memory testAssets = new address[](assetCount);
        for (uint256 i = 0; i < assetCount; i++) {
            testAssets[i] = address(uint160(i + 1));
            assetRegistry.addAsset(testAssets[i]);
        }
        return testAssets;
    }

    function testFuzz_getAllAssets(uint256 assetCount) public {
        vm.assume(assetCount <= MAX_ASSETS);
        address[] memory testAssets = _setupAssets(assetCount);

        // Get all assets
        address[] memory returnedAssets = assetRegistry.getAllAssets();

        // Verify all assets are returned
        assertEq(returnedAssets, testAssets);
    }

    function testFuzz_getAssets(uint256 assetCount, uint256 bitFlag) public {
        vm.assume(assetCount <= MAX_ASSETS);
        address[] memory testAssets = _setupAssets(assetCount);

        // Get assets based on the fuzzed bitFlag
        address[] memory returnedAssets = assetRegistry.getAssets(bitFlag);

        // Verify the returned assets
        uint256 expectedCount = 0;
        for (uint256 i = 0; i < assetCount; i++) {
            if ((bitFlag & (1 << i)) != 0) {
                expectedCount++;
                assertEq(returnedAssets[expectedCount - 1], testAssets[i]);
            }
        }

        // Verify the length of the returned array
        assertEq(returnedAssets.length, expectedCount);
    }

    function testFuzz_getAssets_emptyBitFlag(uint256 assetCount) public {
        vm.assume(assetCount <= MAX_ASSETS);
        _setupAssets(assetCount);

        // Get assets with empty bitFlag
        address[] memory returnedAssets = assetRegistry.getAssets(0);

        // Verify that an empty array is returned
        assertEq(returnedAssets.length, 0);
    }

    function testFuzz_getAssets_allBitsSet(uint256 numAssets) public {
        vm.assume(numAssets > 0 && numAssets <= MAX_ASSETS);
        address[] memory testAssets = _setupAssets(numAssets);

        // Get all assets
        uint256 bitFlag = type(uint256).max;
        address[] memory returnedAssets = assetRegistry.getAssets(bitFlag);

        // Verify all assets are returned
        assertEq(returnedAssets, testAssets);
    }
}

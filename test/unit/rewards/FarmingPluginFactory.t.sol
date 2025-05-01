// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";

import { IERC20Plugins } from "@1inch/token-plugins/contracts/interfaces/IERC20Plugins.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vm } from "forge-std/Vm.sol";
import { FarmingPluginFactory } from "src/rewards/FarmingPluginFactory.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract FarmingPluginFactoryTest is BaseTest {
    FarmingPluginFactory public factory;
    address public admin = address(0x1);
    address public manager = address(0x2);
    address public defaultOwner = address(0x3);

    event FarmingPluginCreated(
        address indexed stakingToken, address indexed rewardsToken, address indexed plugin, address pluginOwner
    );
    event DefaultPluginOwnerSet(address indexed previousOwner, address indexed newOwner);

    function setUp() public override {
        super.setUp();
        factory = new FarmingPluginFactory(admin, manager, defaultOwner);
    }

    // Constructor

    function test_constructor_setsRolesAndOwner() public {
        assertTrue(factory.hasRole(DEFAULT_ADMIN_ROLE, admin), "Admin role not granted");
        assertTrue(factory.hasRole(MANAGER_ROLE, manager), "Manager role not granted");
        assertFalse(factory.hasRole(MANAGER_ROLE, admin), "Admin should not have manager role initially");
        assertEq(factory.defaultPluginOwner(), defaultOwner, "Default owner mismatch");
    }

    function test_constructor_revertWhen_ZeroAdmin() public {
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        new FarmingPluginFactory(address(0), manager, defaultOwner);
    }

    function test_constructor_revertWhen_ZeroManager() public {
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        new FarmingPluginFactory(admin, address(0), defaultOwner);
    }

    function test_constructor_revertWhen_ZeroDefaultOwner() public {
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        new FarmingPluginFactory(admin, manager, address(0));
    }

    // setDefaultPluginOwner

    function test_setDefaultPluginOwner(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit DefaultPluginOwnerSet(defaultOwner, newOwner);
        factory.setDefaultPluginOwner(newOwner);
        assertEq(factory.defaultPluginOwner(), newOwner, "New owner mismatch");
    }

    function test_setDefaultPluginOwner_revertWhen_NotAdmin(address caller, address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != admin);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN_ROLE)
        );
        factory.setDefaultPluginOwner(newOwner);
    }

    function test_setDefaultPluginOwner_revertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        factory.setDefaultPluginOwner(address(0));
    }

    // deployFarmingPlugin & deployFarmingPluginWithDefaultOwner

    function test_deployFarmingPlugin(address stakingToken, address rewardsToken, address newOwner) public {
        vm.assume(stakingToken != address(0));
        vm.assume(rewardsToken != address(0));
        vm.assume(newOwner != address(0));

        vm.startPrank(manager);

        // Record logs for manual verification
        vm.recordLogs();

        address plugin = factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(rewardsToken), newOwner);

        // Get recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Expect 1 log entry for FarmingPluginCreated
        // Note: FarmingPlugin constructor also emits OwnershipTransferred and FarmCreated
        // We need to find the FarmingPluginCreated event specifically
        bool foundEvent = false;
        bytes32 expectedSig = keccak256("FarmingPluginCreated(address,address,address,address)");
        bytes32 expectedStakingToken = bytes32(uint256(uint160(address(stakingToken))));
        bytes32 expectedRewardsToken = bytes32(uint256(uint160(address(rewardsToken))));
        bytes memory expectedOwnerData = abi.encode(newOwner);

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                assertEq(entries[i].topics.length, 4, "Incorrect topic count");
                assertEq(entries[i].topics[1], expectedStakingToken, "Staking token mismatch");
                assertEq(entries[i].topics[2], expectedRewardsToken, "Rewards token mismatch");
                // Topic 3 is the plugin address, skip check
                assertEq(entries[i].data, expectedOwnerData, "Owner data mismatch");
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "FarmingPluginCreated event not found or mismatch");

        vm.stopPrank();

        assertTrue(plugin != address(0), "Plugin address is zero");

        // Check storage updates
        address[] memory pluginsForToken = factory.plugins(address(stakingToken));
        assertEq(pluginsForToken.length, 1, "Plugins length mismatch");
        assertEq(pluginsForToken[0], plugin, "Plugins content mismatch");

        address[] memory allPlugins = factory.allPlugins();
        assertEq(allPlugins.length, 1, "All plugins length mismatch");
        assertEq(allPlugins[0], plugin, "All plugins content mismatch");

        // Check deployed plugin state
        FarmingPlugin deployedPlugin = FarmingPlugin(plugin);
        assertEq(address(deployedPlugin.TOKEN()), address(stakingToken), "Deployed staking token mismatch");
        assertEq(address(deployedPlugin.REWARDS_TOKEN()), address(rewardsToken), "Deployed rewards token mismatch");
        assertEq(deployedPlugin.owner(), newOwner, "Deployed owner mismatch");
    }

    function test_deployFarmingPluginWithDefaultOwner(address stakingToken, address rewardsToken) public {
        vm.assume(stakingToken != address(0));
        vm.assume(rewardsToken != address(0));

        vm.startPrank(manager);

        // Record logs for manual verification
        vm.recordLogs();

        address plugin = factory.deployFarmingPluginWithDefaultOwner(IERC20Plugins(stakingToken), IERC20(rewardsToken));

        // Get recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        bytes32 expectedSig = keccak256("FarmingPluginCreated(address,address,address,address)");
        bytes32 expectedStakingToken = bytes32(uint256(uint160(address(stakingToken))));
        bytes32 expectedRewardsToken = bytes32(uint256(uint160(address(rewardsToken))));
        bytes memory expectedOwnerData = abi.encode(defaultOwner);

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                assertEq(entries[i].topics.length, 4, "Incorrect topic count (DefaultOwner)");
                assertEq(entries[i].topics[1], expectedStakingToken, "Staking token mismatch (DefaultOwner)");
                assertEq(entries[i].topics[2], expectedRewardsToken, "Rewards token mismatch (DefaultOwner)");
                // Topic 3 is the plugin address, skip check
                assertEq(entries[i].data, expectedOwnerData, "Owner data mismatch (DefaultOwner)");
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "FarmingPluginCreated event not found or mismatch (DefaultOwner)");

        vm.stopPrank();

        assertTrue(plugin != address(0), "Plugin address is zero");

        // Check storage updates
        address[] memory pluginsForToken = factory.plugins(address(stakingToken));
        assertEq(pluginsForToken.length, 1, "Plugins length mismatch");
        assertEq(pluginsForToken[0], plugin, "Plugins content mismatch");

        address[] memory allPlugins = factory.allPlugins();
        assertEq(allPlugins.length, 1, "All plugins length mismatch");
        assertEq(allPlugins[0], plugin, "All plugins content mismatch");

        // Check deployed plugin state
        FarmingPlugin deployedPlugin = FarmingPlugin(plugin);
        assertEq(address(deployedPlugin.TOKEN()), address(stakingToken), "Deployed staking token mismatch");
        assertEq(address(deployedPlugin.REWARDS_TOKEN()), address(rewardsToken), "Deployed rewards token mismatch");
        assertEq(deployedPlugin.owner(), defaultOwner, "Deployed owner mismatch (default)");
    }

    function test_deployFarmingPlugin_revertWhen_NotManager(
        address caller,
        address stakingToken,
        address rewardsToken,
        address newOwner
    )
        public
    {
        vm.assume(stakingToken != address(0));
        vm.assume(rewardsToken != address(0));
        vm.assume(newOwner != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != manager);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, MANAGER_ROLE)
        );
        factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(rewardsToken), newOwner);
    }

    function test_deployFarmingPluginWithDefaultOwner_revertWhen_NotManager(
        address caller,
        address stakingToken,
        address rewardsToken
    )
        public
    {
        vm.assume(stakingToken != address(0));
        vm.assume(rewardsToken != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != manager);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, MANAGER_ROLE)
        );
        factory.deployFarmingPluginWithDefaultOwner(IERC20Plugins(stakingToken), IERC20(rewardsToken));
    }

    function test_deployFarmingPlugin_revertWhen_ZeroStakingToken(address rewardsToken, address newOwner) public {
        vm.prank(manager);
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        factory.deployFarmingPlugin(IERC20Plugins(address(0)), IERC20(rewardsToken), newOwner);
    }

    function test_deployFarmingPluginWithDefaultOwner_revertWhen_ZeroStakingToken(address rewardsToken) public {
        vm.prank(manager);
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        factory.deployFarmingPluginWithDefaultOwner(IERC20Plugins(address(0)), IERC20(rewardsToken));
    }

    function test_deployFarmingPlugin_revertWhen_ZeroRewardsToken(address stakingToken, address newOwner) public {
        vm.prank(manager);
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(address(0)), newOwner);
    }

    function test_deployFarmingPluginWithDefaultOwner_revertWhen_ZeroRewardsToken(address stakingToken) public {
        vm.prank(manager);
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        factory.deployFarmingPluginWithDefaultOwner(IERC20Plugins(stakingToken), IERC20(address(0)));
    }

    function test_deployFarmingPlugin_revertWhen_ZeroOwner(address stakingToken, address rewardsToken) public {
        vm.prank(manager);
        vm.expectRevert(FarmingPluginFactory.ZeroAddress.selector);
        factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(rewardsToken), address(0));
    }

    function test_deployFarmingPlugin_revertWhen_DuplicatePlugin(
        address stakingToken,
        address rewardsToken,
        address newOwner
    )
        public
    {
        vm.assume(stakingToken != address(0));
        vm.assume(rewardsToken != address(0));
        vm.assume(newOwner != address(0));

        vm.startPrank(manager);
        factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(rewardsToken), newOwner);
        vm.expectRevert(); // expect it to revert with no data due to EvmError: CreateCollision
        factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(rewardsToken), newOwner);
        vm.stopPrank();
    }

    function test_deployMultiplePlugins(
        address stakingToken,
        address rewardsToken,
        address newOwner,
        address nonExistentToken
    )
        public
    {
        vm.assume(stakingToken != address(0));
        vm.assume(rewardsToken != address(0));
        vm.assume(newOwner != address(0));

        address stakingToken2 = address(uint160(uint256(keccak256(abi.encodePacked(stakingToken)))));
        address rewardsToken2 = address(uint160(uint256(keccak256(abi.encodePacked(rewardsToken)))));
        address owner2 = address(uint160(uint256(keccak256(abi.encodePacked(newOwner)))));

        vm.startPrank(manager);
        address plugin1 = factory.deployFarmingPlugin(IERC20Plugins(stakingToken), IERC20(rewardsToken), newOwner);
        address plugin2 =
            factory.deployFarmingPluginWithDefaultOwner(IERC20Plugins(stakingToken), IERC20(rewardsToken2)); // Same
            // staking, diff reward
        address plugin3 = factory.deployFarmingPlugin(IERC20Plugins(stakingToken2), IERC20(rewardsToken), owner2); // Diff
            // staking
        vm.stopPrank();

        // Check allPlugins
        address[] memory allPlugins = factory.allPlugins();
        assertEq(allPlugins.length, 3, "All plugins length mismatch (multiple)");
        assertEq(allPlugins[0], plugin1, "All plugins[0] mismatch (multiple)");
        assertEq(allPlugins[1], plugin2, "All plugins[1] mismatch (multiple)");
        assertEq(allPlugins[2], plugin3, "All plugins[2] mismatch (multiple)");

        // Check plugins for stakingToken
        address[] memory pluginsForToken1 = factory.plugins(address(stakingToken));
        assertEq(pluginsForToken1.length, 2, "Reward plugins (token1) length mismatch (multiple)");
        assertEq(pluginsForToken1[0], plugin1, "Reward plugins (token1)[0] mismatch (multiple)");
        assertEq(pluginsForToken1[1], plugin2, "Reward plugins (token1)[1] mismatch (multiple)");

        // Check plugins for stakingToken2
        address[] memory pluginsForToken2 = factory.plugins(address(stakingToken2));
        assertEq(pluginsForToken2.length, 1, "Reward plugins (token2) length mismatch (multiple)");
        assertEq(pluginsForToken2[0], plugin3, "Reward plugins (token2)[0] mismatch (multiple)");

        // Check plugins for non-existent token
        vm.assume(nonExistentToken != stakingToken);
        vm.assume(nonExistentToken != stakingToken2);
        address[] memory pluginsForToken3 = factory.plugins(nonExistentToken);
        assertEq(pluginsForToken3.length, 0, "Reward plugins (token3) length mismatch (multiple)");
    }
}

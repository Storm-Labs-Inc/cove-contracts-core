// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20Plugins } from "@1inch/token-plugins/contracts/interfaces/IERC20Plugins.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";

/**
 * @title FarmingPluginFactory
 * @notice Deploys new `FarmingPlugin`s and acts as a registry.
 *
 * Roles
 * -----
 * - DEFAULT_ADMIN_ROLE — can grant/revoke all roles and set default plugin owner
 * - MANAGER_ROLE       — allowed to deploy new farming plugins
 *
 * @dev This factory uses CREATE2 to deploy the farming plugin, therefore there cannot be two plugins with the same
 * staking token and rewards token.
 */
contract FarmingPluginFactory is AccessControlEnumerable {
    /// @notice Role for managing the factory.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Default plugin owner.
    address public defaultPluginOwner;

    /// @dev CREATE3Factory address
    CREATE3Factory private constant _CREATE3_FACTORY = CREATE3Factory(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1);
    /// @dev staking token => list of all farming plugins created for that token
    mapping(address => address[]) private _plugins;
    /// @dev flat list of every plugin ever deployed (useful for iteration off-chain)
    address[] private _allPlugins;

    /// @notice Emitted when a new farming plugin is created.
    /// @param stakingToken  ERC-20 token users deposit (must support plugins).
    /// @param rewardsToken  ERC-20 token distributed as rewards.
    /// @param plugin        Address of the new farming plugin.
    /// @param pluginOwner   Address that will own the plugin (controls start/stop farming & rescue).
    event FarmingPluginCreated(
        address indexed stakingToken, address indexed rewardsToken, address indexed plugin, address pluginOwner
    );
    /// @notice Emitted when the default plugin owner is set.
    /// @param previousOwner Address that was the previous default plugin owner.
    /// @param newOwner      Address that will be the new default plugin owner.
    event DefaultPluginOwnerSet(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when a zero address is used.
    error ZeroAddress();

    /// @notice Constructor.
    /// @param admin  Address that receives DEFAULT_ADMIN_ROLE.
    /// @param manager  Address that receives MANAGER_ROLE.
    /// @param _defaultPluginOwner  Address that will be the default plugin owner.
    // slither-disable-next-line locked-ether
    constructor(address admin, address manager, address _defaultPluginOwner) payable {
        if (admin == address(0) || manager == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _setDefaultPluginOwner(_defaultPluginOwner);
    }

    /*═════════════════════════════════════
    VIEW FUNCTIONS
    ═════════════════════════════════════*/

    /// @notice All plugins ever created.
    /// @return allPlugins Array of all farming plugins.
    function allPlugins() external view returns (address[] memory) {
        return _allPlugins;
    }

    /// @notice Plugins for a given staking token.
    /// @param stakingToken Address of the staking token.
    /// @return plugins Array of farming plugins for the given staking token.
    function plugins(address stakingToken) external view returns (address[] memory) {
        return _plugins[stakingToken];
    }

    /// @notice Compute the address of a plugin for a given staking token and rewards token.
    /// @dev The corresponding contract may not have been deployed yet, so the address may be empty.
    /// For existence, either check for the code size or compare against the allPlugins array.
    /// @param stakingToken Address of the staking token.
    /// @param rewardsToken Address of the rewards token.
    /// @return plugin Address of the plugin.
    function computePluginAddress(IERC20Plugins stakingToken, IERC20 rewardsToken) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(stakingToken, rewardsToken));
        return _CREATE3_FACTORY.getDeployed(address(this), salt);
    }

    /*════════════════════════════════  ADMIN FUNCTIONS
    ════════════════════════════════*/

    /// @notice Set the default plugin owner.
    /// @param pluginOwner Address that will own the plugin (controls start/stop farming & rescue).
    function setDefaultPluginOwner(address pluginOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultPluginOwner(pluginOwner);
    }

    /*══════════════════════════════════  DEPLOYMENT
    FUNCTION
    ═══════════════════════════════════*/

    /// @notice Deploy a new farming plugin with the default plugin owner.
    /// @param stakingToken  ERC-20 token users deposit (must support plugins).
    /// @param rewardsToken  ERC-20 token distributed as rewards.
    /// @dev Access: only accounts with MANAGER_ROLE. Default plugin owner must be set.
    function deployFarmingPluginWithDefaultOwner(
        IERC20Plugins stakingToken,
        IERC20 rewardsToken
    )
        external
        onlyRole(MANAGER_ROLE)
        returns (address plugin)
    {
        return _deployFarmingPlugin(stakingToken, rewardsToken, defaultPluginOwner);
    }

    /// @notice Deploy a new farming plugin.
    /// @param stakingToken  ERC-20 token users deposit (must support plugins).
    /// @param rewardsToken  ERC-20 token distributed as rewards.
    /// @param pluginOwner   Address that will own the plugin (controls start/stop farming & rescue).
    /// @dev Access: only accounts with MANAGER_ROLE.
    function deployFarmingPlugin(
        IERC20Plugins stakingToken,
        IERC20 rewardsToken,
        address pluginOwner
    )
        external
        onlyRole(MANAGER_ROLE)
        returns (address plugin)
    {
        return _deployFarmingPlugin(stakingToken, rewardsToken, pluginOwner);
    }

    /*════════════════════════════════════
    INTERNAL FUNCTIONS
    ════════════════════════════════════*/

    /// @notice Set the default plugin owner.
    /// @param pluginOwner Address that will own the plugin (controls start/stop farming & rescue).
    function _setDefaultPluginOwner(address pluginOwner) internal {
        if (pluginOwner == address(0)) revert ZeroAddress();
        address previousOwner = defaultPluginOwner;
        defaultPluginOwner = pluginOwner;
        emit DefaultPluginOwnerSet(previousOwner, pluginOwner);
    }

    /// @notice Deploy a new farming plugin with a unique salt to avoid collisions.
    /// @param stakingToken  ERC-20 token users deposit (must support plugins).
    /// @param rewardsToken  ERC-20 token distributed as rewards.
    /// @param pluginOwner   Address that will own the plugin (controls start/stop farming & rescue).
    function _deployFarmingPlugin(
        IERC20Plugins stakingToken,
        IERC20 rewardsToken,
        address pluginOwner
    )
        internal
        returns (address plugin)
    {
        if (pluginOwner == address(0) || address(stakingToken) == address(0) || address(rewardsToken) == address(0)) {
            revert ZeroAddress();
        }
        bytes32 salt = keccak256(abi.encodePacked(stakingToken, rewardsToken));
        // slither-disable-next-line too-many-digits,reentrancy-benign
        plugin = _CREATE3_FACTORY.deploy(
            salt,
            abi.encodePacked(type(FarmingPlugin).creationCode, abi.encode(stakingToken, rewardsToken, pluginOwner))
        );

        _plugins[address(stakingToken)].push(plugin);
        _allPlugins.push(plugin);

        // slither-disable-next-line reentrancy-events
        emit FarmingPluginCreated(address(stakingToken), address(rewardsToken), plugin, pluginOwner);
    }
}

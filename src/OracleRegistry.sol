// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { IOracleRegistry } from "./interfaces/IOracleRegistry.sol";
import { Errors } from "./libraries/Errors.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";

/**
 * @title OracleRegistry
 * @notice This contract holds list of oracles and its historical versions.
 */
contract OracleRegistry is IOracleRegistry, AccessControl, Multicall {
    /// @notice Role responsible for adding registries.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    //slither-disable-next-line uninitialized-state
    mapping(bytes32 => address[]) private _oracleMap;
    //slither-disable-next-line uninitialized-state
    mapping(address => ReverseRegistryData) private _reverseRegistry;
    mapping(address => bytes32) public tokenToPythPriceId;
    mapping(address => address) public tokenToChainlinkPriceFeed;

    /**
     * @notice Add a new oracle entry to the master list.
     * @param name address of the added pool
     * @param oracleAddress address of the oracle
     * @param version version of the oracle
     */
    event AddOracle(bytes32 indexed name, address oracleAddress, uint256 version);
    /**
     * @notice Update a current oracle entry to the master list.
     * @param name address of the added pool
     * @param oracleAddress address of the oracle
     * @param version version of the oracle
     */
    event UpdateOracle(bytes32 indexed name, address oracleAddress, uint256 version);

    event AddPythPriceId(address indexed token, bytes32 indexed priceId);
    event UpdatePythPriceId(address indexed token, bytes32 indexed priceId);
    event AddChainlinkPriceFeed(address indexed token, address indexed priceFeed);
    event UpdateChainlinkPriceFeed(address indexed token, address indexed priceFeed);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_MANAGER_ROLE, msg.sender);
    }

    /// @inheritdoc IOracleRegistry
    function addOracle(bytes32 oracleName, address oracleAddress) external onlyRole(_MANAGER_ROLE) {
        // Check for empty values.
        if (oracleName == 0) revert Errors.NameEmpty();
        if (oracleAddress == address(0)) revert Errors.AddressEmpty();

        // Check that the oracle name is not already in use.
        address[] storage oracle = _oracleMap[oracleName];
        uint256 version = oracle.length;
        if (version > 0) revert Errors.OracleNameFound(oracleName);
        if (_reverseRegistry[oracleAddress].oracleName != 0) {
            revert Errors.DuplicateOracleAddress(oracleAddress);
        }
        // Create an entry in the registry
        oracle.push(oracleAddress);
        _reverseRegistry[oracleAddress] = ReverseRegistryData(oracleName, version);

        emit AddOracle(oracleName, oracleAddress, version);
    }

    /// @inheritdoc IOracleRegistry
    function updateOracle(bytes32 oracleName, address oracleAddress) external onlyRole(_MANAGER_ROLE) {
        // Check for empty values.
        if (oracleName == 0) revert Errors.NameEmpty();
        if (oracleAddress == address(0)) revert Errors.AddressEmpty();

        // Check that the registry name already exists in the registry.
        address[] storage registry = _oracleMap[oracleName];
        uint256 version = registry.length;
        if (version == 0) revert Errors.OracleNameNotFound(oracleName);
        if (_reverseRegistry[oracleAddress].oracleName != 0) {
            revert Errors.DuplicateOracleAddress(oracleAddress);
        }

        // Update the entry in the registry
        registry.push(oracleAddress);
        _reverseRegistry[oracleAddress] = ReverseRegistryData(oracleName, version);

        emit UpdateOracle(oracleName, oracleAddress, version);
    }

    function addPythPriceId(address token, bytes32 priceId) external onlyRole(_MANAGER_ROLE) {
        tokenToPythPriceId[token] = priceId;
        emit AddPythPriceId(token, priceId);
    }

    function updatePythPriceId(address token, bytes32 priceId) external onlyRole(_MANAGER_ROLE) {
        tokenToPythPriceId[token] = priceId;
        emit UpdatePythPriceId(token, priceId);
    }

    function addChainlinkPriceFeed(address token, address priceFeed) external onlyRole(_MANAGER_ROLE) {
        tokenToChainlinkPriceFeed[token] = priceFeed;
        emit AddChainlinkPriceFeed(token, priceFeed);
    }

    function updateChainlinkPriceFeed(address token, address priceFeed) external onlyRole(_MANAGER_ROLE) {
        tokenToChainlinkPriceFeed[token] = priceFeed;
        emit UpdateChainlinkPriceFeed(token, priceFeed);
    }

    /// @inheritdoc IOracleRegistry
    function resolveNameToLatestAddress(bytes32 oracleName) external view returns (address) {
        address[] storage registry = _oracleMap[oracleName];
        uint256 length = registry.length;
        if (length == 0) revert Errors.OracleNameNotFound(oracleName);
        return registry[length - 1];
    }

    /// @inheritdoc IOracleRegistry
    function resolveNameAndVersionToAddress(bytes32 oracleName, uint256 version) external view returns (address) {
        address[] storage registry = _oracleMap[oracleName];
        if (version >= registry.length) revert Errors.OracleNameVersionNotFound(oracleName, version);
        return registry[version];
    }

    /// @inheritdoc IOracleRegistry
    function resolveNameToAllAddresses(bytes32 oracleName) external view returns (address[] memory) {
        address[] storage registry = _oracleMap[oracleName];
        if (registry.length == 0) revert Errors.OracleNameNotFound(oracleName);
        return registry;
    }

    /// @inheritdoc IOracleRegistry
    function resolveAddressToOracleData(address oracleAddress)
        external
        view
        returns (bytes32 oracleName, uint256 version, bool isLatest)
    {
        ReverseRegistryData memory data = _reverseRegistry[oracleAddress];
        if (data.oracleName == 0) revert Errors.OracleAddressNotFound(oracleAddress);
        oracleName = data.oracleName;
        version = data.version;
        uint256 length = _oracleMap[oracleName].length;
        isLatest = version == length - 1;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOracleRegistry {
    /* Structs */

    struct ReverseRegistryData {
        bytes32 oracleName;
        uint256 version;
    }

    /* Functions */

    /**
     * @notice Add a new oracle entry to the master list. Reverts if an entry is already found with the given name.
     * @param oracleName name for the oracle
     * @param registryAddress address of the new oracle
     */
    function addOracle(bytes32 oracleName, address registryAddress) external;

    /**
     * @notice Update an existing registry entry to the master list. Reverts if no match is found.
     * @param registryName name for the registry
     * @param registryAddress address of the new registry
     */
    function updateOracle(bytes32 registryName, address registryAddress) external;

    /**
     * @notice Resolves a name to the latest oracle address. Reverts if no match is found.
     * @param oracleName name for the registry
     * @return address address of the latest oracle with the matching name
     */
    function resolveNameToLatestAddress(bytes32 oracleName) external view returns (address);

    /**
     * @notice Resolves a name and version to an address. Reverts if there is no registry with given name and version.
     * @param oracleName address of the oracle you want to resolve to
     * @param version version of the oracle you want to resolve to
     */
    function resolveNameAndVersionToAddress(bytes32 oracleName, uint256 version) external view returns (address);

    /**
     * @notice Resolves a name to an array of all addresses. Reverts if no match is found.
     * @param oracleName name for the registry
     * @return address address of the latest registry with the matching name
     */
    function resolveNameToAllAddresses(bytes32 oracleName) external view returns (address[] memory);

    /**
     * @notice Resolves an address to oracle registry entry data.
     * @param oracleAddress address of a oracle you want to resolve
     * @return oracleName name of the resolved oracle
     * @return version version of the resolved oracle
     * @return isLatest boolean flag of whether the given address is the latest version of the given oracle with
     * matching name
     */
    function resolveAddressToOracleData(address oracleAddress)
        external
        view
        returns (bytes32 oracleName, uint256 version, bool isLatest);
}

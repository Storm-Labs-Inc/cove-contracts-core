// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

/// @title Errors
/// @notice Library containing all custom errors the protocol may revert with.
library Errors {
    // solhint-disable var-name-mixedcase
    //// Oracle REGISTRY ////
    /// @notice Thrown when the Oracle name given is empty.
    error NameEmpty();

    /// @notice Thrown when the Oracle address given is empty.
    error AddressEmpty();

    /// @notice Thrown when the Oracle name is found when calling addOracle().
    error OracleNameFound(bytes32 name);

    /// @notice Thrown when the Oracle name is not found but is expected to be.
    error OracleNameNotFound(bytes32 name);

    /// @notice Thrown when the Oracle address is not found but is expected to be.
    error OracleAddressNotFound(address OracleAddress);

    /// @notice Thrown when the Oracle name and version is not found but is expected to be.
    error OracleNameVersionNotFound(bytes32 name, uint256 version);

    /// @notice Thrown when the caller is not the protocol manager.
    error CallerNotProtocolManager(address caller);

    /// @notice Thrown when a duplicate Oracle address is found.
    error DuplicateOracleAddress(address OracleAddress);

    /// BASKET TOKEN ///
    error ZeroAddress();
    error ZeroAmount();
    error ZeroPendingDeposits();
    error ZeroPendingRedeems();
    error AssetPaused();
    error NotOwner();
    error MustClaimOutstandingDeposit();
    error MustClaimOutstandingRedeem();
    error MustClaimFullAmount();
    error NotBasketManager();

    /// TESTING ///

    error TakeAwayNotEnoughBalance();
}

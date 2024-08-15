// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity 0.8.23;

// // TokenizedStrategy interface used for internal view delegateCalls.
// import { IRebalancingUtils } from "src/interfaces/IRebalancingUtils.sol";

// contract BaseManager {
//     /**
//      * @dev Used on TokenizedStrategy callback functions to make sure it is post
//      * a delegateCall from this address to the TokenizedStrategy.
//      */
//     modifier onlySelf() {
//         _onlySelf();
//         _;
//     }

//     /**
//      * @dev This variable is set to address(this) during initialization of each strategy.
//      *
//      * This can be used to retrieve storage data within the strategy
//      * contract as if it were a linked library.
//      *
//      *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
//      *
//      * Using address(this) will mean any calls using this variable will lead
//      * to a call to itself. Which will hit the fallback function and
//      * delegateCall that to the actual TokenizedStrategy.
//      */
//     IRebalancingUtils internal immutable RebalancingUtils;
//     address public asset;
//     // NOTE: This is a holder address based on expected deterministic location for testing
//     address internal rebalancingUtilsAddress;

//     /**
//      * @dev Require that the msg.sender is this address.
//      */
//     function _onlySelf() internal view {
//         require(msg.sender == address(this), "!self");
//     }

//     /**
//      * @notice Used to initialize the strategy on deployment.
//      *
//      * This will set the `TokenizedStrategy` variable for easy
//      * internal view calls to the implementation. As well as
//      * initializing the default storage variables based on the
//      * parameters and using the deployer for the permissioned roles.
//      *
//      * @param _asset Address of the underlying asset.
//      */
//     constructor(address _asset, address implementation) {
//         asset = _asset;
//         rebalancingUtilsAddress = implementation;
//         // Set instance of the implementation for internal use.
//         RebalancingUtils = IRebalancingUtils(address(this));

//         // Initialize the strategy's storage variables.
//         _delegateCall(abi.encodeCall(IRebalancingUtils.initialize, (_asset)));

//         // Store the tokenizedStrategyAddress at the standard implementation
//         // address storage slot so etherscan picks up the interface. This gets
//         // stored on initialization and never updated.
//         assembly {
//             sstore(
//                 // keccak256('eip1967.proxy.implementation' - 1)
//                 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
//                 rebalancingUtilsAddress
//             )
//         }
//     }

//     /**
//      * @dev Function used to delegate call the TokenizedStrategy with
//      * certain `_calldata` and return any return values.
//      *
//      * This is used to setup the initial storage of the strategy, and
//      * can be used by strategist to forward any other call to the
//      * TokenizedStrategy implementation.
//      *
//      * @param _calldata The abi encoded calldata to use in delegatecall.
//      * @return . The return value if the call was successful in bytes.
//      */
//     function _delegateCall(bytes memory _calldata) internal returns (bytes memory) {
//         // Delegate call the tokenized strategy with provided calldata.
//         (bool success, bytes memory result) = rebalancingUtilsAddress.delegatecall(_calldata);

//         // If the call reverted. Return the error.
//         if (!success) {
//             assembly {
//                 let ptr := mload(0x40)
//                 let size := returndatasize()
//                 returndatacopy(ptr, 0, size)
//                 revert(ptr, size)
//             }
//         }

//         // Return the result.
//         return result;
//     }

//     /**
//      * @dev Execute a function on the TokenizedStrategy and return any value.
//      *
//      * This fallback function will be executed when any of the standard functions
//      * defined in the TokenizedStrategy are called since they wont be defined in
//      * this contract.
//      *
//      * It will delegatecall the TokenizedStrategy implementation with the exact
//      * calldata and return any relevant values.
//      *
//      */
//     fallback() external {
//         // load our target address
//         address _rebalancingUtilsAddress = rebalancingUtilsAddress;
//         // Execute external function using delegatecall and return any value.
//         assembly {
//             // Copy function selector and any arguments.
//             calldatacopy(0, 0, calldatasize())
//             // Execute function delegatecall.
//             let result := delegatecall(gas(), _rebalancingUtilsAddress, 0, calldatasize(), 0, 0)
//             // Get any return value
//             returndatacopy(0, 0, returndatasize())
//             // Return any return value or error back to the caller
//             switch result
//             case 0 { revert(0, returndatasize()) }
//             default { return(0, returndatasize()) }
//         }
//     }
// }

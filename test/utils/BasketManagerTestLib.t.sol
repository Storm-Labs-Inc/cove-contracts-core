// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPyth } from "euler-price-oracle/lib/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "euler-price-oracle/lib/pyth-sdk-solidity/PythStructs.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { Vm } from "forge-std/Vm.sol";

import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { BasketManager } from "src/BasketManager.sol";

import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { ERC4626Oracle } from "src/oracles/ERC4626Oracle.sol";

/// @title BasketManagerTestLib
/// @author Cove
/// @notice Library for testing the BasketManager contract. Other test contracts should import
/// this library and use it for BasketManager addresses.
library BasketManagerTestLib {
    /// @notice Error thrown when an oracle is not configured for an asset
    error OracleNotConfigured(address asset);
    /// @notice Error thrown when an oracle is not an anchored oracle
    error NotAnchoredOracle(address asset);
    /// @notice Error thrown when an oracle path does not use both Pyth and Chainlink
    error InvalidOraclePath(address asset);
    /// @notice Error thrown when primary oracle is not using Pyth
    error PrimaryNotPyth(address asset);
    /// @notice Error thrown when anchor oracle is not using Chainlink
    error AnchorNotChainlink(address asset);
    /// @notice Error thrown when AnchoredOracle is given when expecting an oracle with a linear path to USD
    error OracleIsNotLinear(address asset);
    /// @notice Error thrown when an invalid oracle is given
    error InvalidOracle(address oracle);

    /// @notice USD address constant (using ISO 4217 currency code)
    address internal constant USD = address(840);
    address internal constant PYTH = address(0x4305FB66699C3B2702D4d05CF36551390A4c69C6);
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    // solhint-disable-next-line const-name-snakecase
    Vm internal constant vm = Vm(VM_ADDRESS);

    /// @notice Validates that all assets in the basket have properly configured oracles
    /// @param basketManager The BasketManager contract to validate
    function validateConfiguredOracles(BasketManager basketManager) public view {
        // Get the EulerRouter from the BasketManager
        EulerRouter eulerRouter = EulerRouter(basketManager.eulerRouter());

        // Get all basket tokens
        address[] memory baskets = basketManager.basketTokens();

        // Iterate through each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            // Get all assets in the basket
            address[] memory assets = basketManager.basketAssets(baskets[i]);

            // Iterate through each asset
            for (uint256 j = 0; j < assets.length; j++) {
                address asset = assets[j];
                _validateOraclePath(eulerRouter, asset);
            }
        }
    }

    function updateOracleTimestamps(BasketManager basketManager) internal {
        // Get the EulerRouter from the BasketManager
        EulerRouter eulerRouter = EulerRouter(basketManager.eulerRouter());

        // Get all basket tokens
        address[] memory baskets = basketManager.basketTokens();

        // Iterate through each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            // Get all assets in the basket
            address[] memory assets = basketManager.basketAssets(baskets[i]);

            // Iterate through each asset
            for (uint256 j = 0; j < assets.length; j++) {
                address asset = assets[j];
                address oracle = eulerRouter.getConfiguredOracle(asset, USD);
                _updateOracleTimestamp(eulerRouter, oracle);
            }
        }
    }

    function _updateOracleTimestamp(EulerRouter eulerRouter, address oracle) private {
        // Update the oracle timestamp
        if (_isAnchoredOracle(oracle)) {
            _updateOracleTimestamp(eulerRouter, AnchoredOracle(oracle).primaryOracle());
            _updateOracleTimestamp(eulerRouter, AnchoredOracle(oracle).anchorOracle());
        } else if (_isCrossAdapter(oracle)) {
            _updateOracleTimestamp(eulerRouter, CrossAdapter(oracle).oracleBaseCross());
            _updateOracleTimestamp(eulerRouter, CrossAdapter(oracle).oracleCrossQuote());
        } else if (_isERC4626Oracle(oracle)) {
            // Do nothing
        } else if (_isPythOracle(oracle)) {
            _updatePythOracleTimeStamp(PythOracle(oracle).feedId());
        } else if (_isChainlinkOracle(oracle)) {
            _updateChainLinkOracleTimeStamp(ChainlinkOracle(oracle).feed());
        } else {
            revert InvalidOracle(oracle);
        }
    }

    // Updates the timestamp of a Pyth oracle response to the current block timestamp
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        vm.record();
        IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        (bytes32[] memory readSlots,) = vm.accesses(PYTH);
        // Second read slot contains the timestamp in the last 32 bits
        // key   "0x28b01e5f9379f2a22698d286ce7faa0c31f6e4041ee32933d99cfe45a4a8ced5":
        // value "0x0000000000000000071021bc0000003f435df940fffffff80000000067a59cb0",
        // Where timestamp is 0x67a59cb0
        // overwrite this by using vm.store(readSlots[1], modified state)
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData =
            bytes32((uint256(vm.load(PYTH, readSlots[1])) & ~uint256(0xFFFFFFFF)) | newPublishTime);
        vm.store(PYTH, readSlots[1], modifiedStorageData);

        // Verify the storage was updated.
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        require(res.publishTime == newPublishTime, "PythOracle timestamp was not updated correctly");
    }

    // Updates the timestamp of a ChainLink oracle response to the current block timestamp
    function _updateChainLinkOracleTimeStamp(address chainlinkOracle) internal {
        address aggregator = IChainlinkAggregatorV3Interface(chainlinkOracle).aggregator();
        vm.record();
        IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        (bytes32[] memory readSlots,) = vm.accesses(aggregator);
        // The third slot of the aggregator reads contains the timestamp in the first 32 bits
        // Format: 0x67a4876b67a48757000000000000000000000000000000000f806f93b728efc0
        // Where 0x67a4876b is the timestamp
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData = bytes32(
            (uint256(vm.load(aggregator, readSlots[2])) & ~uint256(0xFFFFFFFF << 224)) | (newPublishTime << 224)
        );
        vm.store(aggregator, readSlots[2], modifiedStorageData);

        // Verify the storage was updated
        (,,, uint256 updatedTimestamp,) = IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        require(updatedTimestamp == newPublishTime, "ChainLink timestamp was not updated correctly");
    }

    /// @notice Helper function to validate that an oracle path uses both Pyth and Chainlink
    /// @param eulerRouter The EulerRouter contract
    /// @param asset The asset to validate
    function _validateOraclePath(EulerRouter eulerRouter, address asset) private view {
        // Get the configured oracle for this asset pair
        address oracle = eulerRouter.getConfiguredOracle(asset, USD);
        if (oracle == address(0)) {
            revert OracleNotConfigured(asset);
        }

        bool isAnchoredOracle = _isAnchoredOracle(oracle);
        if (!isAnchoredOracle) {
            revert NotAnchoredOracle(asset);
        }

        // For AnchoredOracle, we need to verify that one path uses Pyth and the other uses Chainlink
        address primaryOracleAddr = AnchoredOracle(oracle).primaryOracle();
        address anchorOracleAddr = AnchoredOracle(oracle).anchorOracle();

        // Validate the primary and anchor oracle paths
        bool primaryHasPyth = _isOraclePathPyth(primaryOracleAddr);
        bool primaryHasChainlink = _isOraclePathChainlink(primaryOracleAddr);
        bool anchorHasPyth = _isOraclePathPyth(anchorOracleAddr);
        bool anchorHasChainlink = _isOraclePathChainlink(anchorOracleAddr);

        // We require that one path uses Pyth and the other uses Chainlink
        // Typical configurations:
        // Primary = Pyth, Anchor = Chainlink
        if (!(primaryHasPyth && anchorHasChainlink && !primaryHasChainlink && !anchorHasPyth)) {
            revert InvalidOraclePath(asset);
        }
    }

    /// @notice Validates a CrossAdapter oracle by checking its paths
    /// @param oracleAddr The CrossAdapter oracle address
    function validateCrossAdapterPath(address oracleAddr) private view {
        // Get the CrossAdapter's oracles
        address oracleBaseCross = CrossAdapter(oracleAddr).oracleBaseCross();
        address oracleCrossQuote = CrossAdapter(oracleAddr).oracleCrossQuote();

        // We need to check both chain paths to ensure one uses Pyth and one uses Chainlink
        bool baseCrossPyth = _isOraclePathPyth(oracleBaseCross);
        bool baseCrossChainlink = _isOraclePathChainlink(oracleBaseCross);
        bool crossQuotePyth = _isOraclePathPyth(oracleCrossQuote);
        bool crossQuoteChainlink = _isOraclePathChainlink(oracleCrossQuote);

        // Ensure we have at least one Pyth and one Chainlink oracle in the paths
        // Valid configurations:
        // 1. BaseCross = Pyth, CrossQuote = Chainlink
        // 2. BaseCross = Chainlink, CrossQuote = Pyth
        // 3. Both have mixed paths but together they ensure Pyth and Chainlink are used
        bool hasPyth = baseCrossPyth || crossQuotePyth;
        bool hasChainlink = baseCrossChainlink || crossQuoteChainlink;

        if (!(hasPyth && hasChainlink)) {
            revert InvalidOraclePath(CrossAdapter(oracleAddr).base());
        }
    }

    /// @notice Checks if an oracle path includes Pyth at any point
    /// @param oracle The oracle to check
    /// @return True if the oracle path includes Pyth
    function _isOraclePathPyth(address oracle) private view returns (bool) {
        // Direct check
        if (_isPythOracle(oracle)) {
            return true;
        }

        // Check if it's an AnchoredOracle with Pyth
        if (_isAnchoredOracle(oracle)) {
            revert OracleIsNotLinear(oracle);
        }

        // Check if it's a CrossAdapter with Pyth
        if (_isCrossAdapter(oracle)) {
            address oracleBaseCross = CrossAdapter(oracle).oracleBaseCross();
            address oracleCrossQuote = CrossAdapter(oracle).oracleCrossQuote();
            return (_isOraclePathPyth(oracleBaseCross) || _isOraclePathPyth(oracleCrossQuote))
                && (!_isOraclePathChainlink(oracleBaseCross) && !_isOraclePathChainlink(oracleCrossQuote));
        }

        return false;
    }

    /// @notice Checks if an oracle path includes Chainlink at any point
    /// @param oracle The oracle to check
    /// @return True if the oracle path includes Chainlink
    function _isOraclePathChainlink(address oracle) private view returns (bool) {
        // Direct check
        if (_isChainlinkOracle(oracle)) {
            return true;
        }

        // Check if it's an AnchoredOracle with Chainlink
        if (_isAnchoredOracle(oracle)) {
            revert AnchorNotChainlink(oracle);
        }

        // Check if it's a CrossAdapter with Chainlink
        if (_isCrossAdapter(oracle)) {
            address oracleBaseCross = CrossAdapter(oracle).oracleBaseCross();
            address oracleCrossQuote = CrossAdapter(oracle).oracleCrossQuote();
            return (_isOraclePathChainlink(oracleBaseCross) || _isOraclePathChainlink(oracleCrossQuote))
                && (!_isOraclePathPyth(oracleBaseCross) && !_isOraclePathPyth(oracleCrossQuote));
        }

        return false;
    }

    /// @notice Helper function to check if an oracle is an AnchoredOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is an AnchoredOracle
    function _isAnchoredOracle(address oracle) private view returns (bool) {
        try AnchoredOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("AnchoredOracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a CrossAdapter
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a CrossAdapter
    function _isCrossAdapter(address oracle) private view returns (bool) {
        try CrossAdapter(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("CrossAdapter"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is an ERC4626Oracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is an ERC4626Oracle
    function _isERC4626Oracle(address oracle) private view returns (bool) {
        try ERC4626Oracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("ERC4626Oracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a PythOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a PythOracle
    function _isPythOracle(address oracle) private view returns (bool) {
        try PythOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("PythOracle"));
        } catch {
            return false;
        }
    }

    /// @notice Helper function to check if an oracle is a ChainlinkOracle
    /// @param oracle The oracle address to check
    /// @return True if the oracle is a ChainlinkOracle
    function _isChainlinkOracle(address oracle) private view returns (bool) {
        try ChainlinkOracle(oracle).name() returns (string memory name) {
            return keccak256(bytes(name)) == keccak256(bytes("ChainlinkOracle"));
        } catch {
            return false;
        }
    }
}

pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

import { console } from "forge-std/console.sol";

import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

import { Constants } from "test/utils/Constants.t.sol";

import { GlobalState } from "test/invariant/handler/GlobalState.sol";

/**
 * @title OracleHandler
 * @notice Handler for manipulating price oracle data during fuzzing
 * @dev Updates prices and coordinates with GlobalState for invariant testing
 */
contract OracleHandler is Constants, Test {
    BasketManager public basketManager;
    GlobalState public globalState;

    MockPriceOracle oracle;

    /**
     * @notice Initializes the oracle handler
     * @param basketManagerParameter The BasketManager contract
     * @param oracleParameter The mock price oracle to manipulate
     * @param globalStateParameter Global state for coordination
     */
    constructor(
        BasketManager basketManagerParameter,
        MockPriceOracle oracleParameter,
        GlobalState globalStateParameter
    ) {
        require(address(basketManagerParameter) != address(0));
        basketManager = basketManagerParameter;

        require(address(oracleParameter) != address(0));
        oracle = oracleParameter;

        require(address(globalStateParameter) != address(0));
        globalState = globalStateParameter;
    }

    /**
     * @notice Changes price of an asset by a percentage (max 90% change)
     * @param percent Percentage change (1-89%)
     * @param increase Whether to increase or decrease the price
     * @param assetId Asset index (modulo'd to valid range)
     */
    function changePrice(uint8 percent, bool increase, uint256 assetId) public {
        address[] memory assets = oracle.all_assets();
        assetId = assetId % assets.length;
        address assetToUpdate = assets[assetId];

        address[] memory base_assets = _get_base_assets();

        // Max 90% change
        percent = 1 + percent % 89;

        _update_price(assetToUpdate, USD, percent, increase);
        _update_price(USD, assetToUpdate, percent, increase);

        // Update the price of the asset with respect to all the asset used as base tokens
        for (uint256 i = 0; i < base_assets.length; i++) {
            if (base_assets[i] == assetToUpdate) {
                continue;
            }

            _update_price(assetToUpdate, base_assets[i], percent, increase);
        }

        globalState.price_updated();
    }

    /**
     * @notice Updates price for a specific asset pair
     */
    function _update_price(address assetToUpdate, address baseAsset, uint8 percent, bool increase) internal {
        uint256 priceold = oracle.getPrice(assetToUpdate, baseAsset);
        uint256 price = _new_price(priceold, percent, increase);
        console.log("#### Update price: ", baseAsset, assetToUpdate);
        console.log("#### Update price: ", priceold, price);
        oracle.setPrice(assetToUpdate, baseAsset, price);
    }

    /**
     * @notice Calculates new price based on percentage change
     */
    function _new_price(uint256 price, uint8 percent, bool increase) internal pure returns (uint256) {
        if (increase) {
            unchecked {
                if (price > price + price * percent / 100) {
                    return price; // dont change the price if overflow
                }
            }

            price = price + price * percent / 100;
        } else {
            if (price < price * percent / 100) {
                return price; // dont change the price if underflow
            }
            unchecked {
                price -= price * percent / 100;
            }
        }
        return price;
    }

    /**
     * @notice Gets base assets from all basket tokens
     */
    function _get_base_assets() internal view returns (address[] memory) {
        address[] memory candidates = basketManager.basketTokens();

        // candidates might have dupp, but it's
        for (uint256 i = 0; i < candidates.length; i++) {
            candidates[i] = BasketToken(candidates[i]).asset();
        }

        return candidates;
    }
}

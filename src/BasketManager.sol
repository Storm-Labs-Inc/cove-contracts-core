// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AllocationResolver } from "src/AllocationResolver.sol";
import { BasketToken } from "src/BasketToken.sol";

/**
 * @title BasketManager
 * @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
 * here.
 */
contract BasketManager {
    /**
     * Libraries
     */
    using SafeERC20 for IERC20;

    /**
     * Constants
     */
    /// @notice Maximum number of basket tokens allowed to be created.
    uint256 public constant MAX_NUM_OF_BASKET_TOKENS = 256;
    /// @notice Address of the root asset to be used for the baskets.
    address public immutable ROOT_ASSET;

    /**
     * State variables
     */
    /// @notice Array of all basket tokens
    address[] public basketTokens;
    /// @notice Mapping of basketId to basket address
    mapping(bytes32 basketId => address basketToken) public basketIdToAddress;
    /// @notice Mapping of basket token to index plus one. 0 means the basket token does not exist.
    mapping(address basketToken => uint256 indexPlusOne) private _basketTokenToIndexPlusOne;

    /// @notice Address of the BasketToken implementation
    address public basketTokenImplementation;
    /// @notice Address of the OracleRegistry contract used to fetch oracle values for assets
    address public oracleRegistry;
    /// @notice Address of the AllocationResolver contract used to resolve allocations
    AllocationResolver public allocationResolver;

    /**
     * Events
     */

    /**
     * Errors
     */
    error ZeroAddress();
    error BasketTokenNotFound();
    error BasketTokenAlreadyExists();
    error BasketTokenMaxExceeded();
    error AllocationResolverDoesNotSupportStrategy();

    /**
     * Structs
     */

    /**
     * @notice Initializes the contract with the given parameters.
     * @param rootAsset_ Address of the root asset to be used for the baskets.
     * @param _basketTokenImplementation Address of the basket token implementation.
     * @param _oracleRegistry Address of the oracle registry.
     * @param _allocationResolver Address of the allocation resolver.
     */
    constructor(
        address rootAsset_,
        address _basketTokenImplementation,
        address _oracleRegistry,
        address _allocationResolver
    ) {
        // Checks
        if (rootAsset_ == address(0)) revert ZeroAddress();
        if (_basketTokenImplementation == address(0)) revert ZeroAddress();
        if (_oracleRegistry == address(0)) revert ZeroAddress();
        if (_allocationResolver == address(0)) revert ZeroAddress();

        // Effects
        ROOT_ASSET = rootAsset_;
        basketTokenImplementation = _basketTokenImplementation;
        oracleRegistry = _oracleRegistry;
        allocationResolver = AllocationResolver(_allocationResolver);
    }

    /**
     * Public functions
     */

    /**
     * @notice Creates a new basket token with the given parameters.
     * @param basketName Name of the basket.
     * @param symbol Symbol of the basket.
     * @param bitFlag Asset selection bitFlag for the basket.
     * @param strategyId Strategy id for the basket.
     */
    function createNewBasket(
        string memory basketName,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId
    )
        public
        payable
        returns (address basket)
    {
        // Checks
        uint256 basketTokensLength = basketTokens.length;
        if (basketTokensLength >= MAX_NUM_OF_BASKET_TOKENS) {
            revert BasketTokenMaxExceeded();
        }
        bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategyId));
        if (basketIdToAddress[basketId] != address(0)) {
            revert BasketTokenAlreadyExists();
        }
        if (!allocationResolver.supportsStrategy(bitFlag, strategyId)) {
            revert AllocationResolverDoesNotSupportStrategy();
        }
        // Effects
        basket = Clones.clone(basketTokenImplementation);
        basketTokens.push(basket);
        basketIdToAddress[basketId] = basket;
        unchecked {
            // Overflow not possible: basketTokensLength is less than the constant MAX_NUM_OF_BASKET_TOKENS
            _basketTokenToIndexPlusOne[basket] = basketTokensLength + 1;
        }
        // Interactions
        BasketToken(basket).initialize(IERC20(ROOT_ASSET), basketName, symbol, bitFlag, strategyId);
    }

    /**
     * @notice Returns the index of the basket token in the basketTokens array.
     * @dev Reverts if the basket token does not exist.
     * @param basketToken Address of the basket token.
     * @return index Index of the basket token.
     */
    function basketTokenToIndex(address basketToken) public view returns (uint256 index) {
        index = _basketTokenToIndexPlusOne[basketToken];
        if (index == 0) {
            revert BasketTokenNotFound();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /**
     * @notice Returns the number of basket tokens.
     * @return Number of basket tokens.
     */
    function numOfBasketTokens() public view returns (uint256) {
        return basketTokens.length;
    }
}

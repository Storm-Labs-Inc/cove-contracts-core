// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AllocationResolver } from "src/AllocationResolver.sol";
import { BasketToken } from "src/BasketToken.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";

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
     * Structs
     */
    /**
     * @notice Enum representing the status of a rebalance.
     */
    enum Status {
        NOT_STARTED,
        REBALANCE_PROPOSED,
        TOKEN_SWAP_PROPOSED,
        TOKEN_SWAP_EXECUTED
    }

    struct RebalanceStatus {
        uint40 timestamp;
        Status status;
    }

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
    /// @notice Mapping of basket token to asset to balance
    mapping(address basketToken => mapping(address asset => uint256 balance)) public basketBalanceOf;
    /// @notice Mapping of basketId to basket address
    mapping(bytes32 basketId => address basketToken) public basketIdToAddress;
    /// @notice Mapping of basket token to assets
    mapping(address basketToken => address[] basketAssets) public basketAssets;
    /// @notice Mapping of basket token to index plus one. 0 means the basket token does not exist.
    mapping(address basketToken => uint256 indexPlusOne) private _basketTokenToIndexPlusOne;
    mapping(address basketToken => uint256 pendingWithdraw) public pendingWithdraw;

    /// @notice Address of the BasketToken implementation
    address public basketTokenImplementation;
    /// @notice Address of the OracleRegistry contract used to fetch oracle values for assets
    address public oracleRegistry;
    /// @notice Address of the AllocationResolver contract used to resolve allocations
    AllocationResolver public allocationResolver;
    /// @notice Rebalance status
    RebalanceStatus public rebalanceStatus;

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
    error RebalanceNotNeeded();
    error MustWaitForRebalance();

    /**
     * @notice Initializes the contract with the given parameters.
     * @param rootAsset_ Address of the root asset to be used for the baskets.
     * @param basketTokenImplementation_ Address of the basket token implementation.
     * @param oracleRegistry_ Address of the oracle registry.
     * @param allocationResolver_ Address of the allocation resolver.
     */
    constructor(
        address rootAsset_,
        address basketTokenImplementation_,
        address oracleRegistry_,
        address allocationResolver_
    ) {
        // Checks
        if (rootAsset_ == address(0)) revert ZeroAddress();
        if (basketTokenImplementation_ == address(0)) revert ZeroAddress();
        if (oracleRegistry_ == address(0)) revert ZeroAddress();
        if (allocationResolver_ == address(0)) revert ZeroAddress();

        // Effects
        ROOT_ASSET = rootAsset_;
        basketTokenImplementation = basketTokenImplementation_;
        oracleRegistry = oracleRegistry_;
        allocationResolver = AllocationResolver(allocationResolver_);
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
        basketAssets[basket] = allocationResolver.getAssets(bitFlag);
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

    /**
     * @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
     * target weight and the proposed target weight is more than 1% or the worth of the difference is more than 10000
     * USD.
     * @param basketsToRebalance Array of basket addresses to rebalance.
     */
    function proposeRebalance(address[] calldata basketsToRebalance) external {
        bool shouldRebalance = false;
        for (uint256 i = 0; i < basketsToRebalance.length;) {
            address basket = basketsToRebalance[i];
            address[] memory assets = basketAssets[basket];
            if (assets.length == 0) {
                revert BasketTokenNotFound();
            }
            uint256[] memory balances = new uint256[](assets.length);
            uint256[] memory targetBalances = new uint256[](assets.length);
            uint256[] memory targetWeights = new uint256[](assets.length);
            uint256[] memory proposedTargetWeights = allocationResolver.getTargetWeight(basket);
            uint256[] memory priceOfAssets = new uint256[](assets.length);
            uint256 basketValue = 0;
            uint256 pendingDeposit = BasketToken(basket).totalPendingDeposit();

            // Calculate current basketValue
            for (uint256 j = 0; j < assets.length;) {
                balances[j] = basketBalanceOf[basket][assets[j]];
                priceOfAssets[j] = 0; // oracleRegistry.getPrice(assets[j]);
                basketValue += balances[j] * priceOfAssets[j];
                unchecked {
                    ++j;
                }
            }

            // Process pending deposit
            balances[0] += pendingDeposit;
            uint256 totalSupply = BasketToken(basket).totalSupply();
            uint256 pendingDepositValue = pendingDeposit * priceOfAssets[0];
            uint256 requiredDepositShares = pendingDepositValue * totalSupply / basketValue;
            totalSupply += requiredDepositShares;
            basketValue += pendingDepositValue;
            BasketToken(basket).fulfillDeposit(requiredDepositShares);

            // Calculate targetBalances
            {
                uint256 requiredWithdrawValue =
                    basketValue * BasketToken(basket).totalPendingRedeem() / (totalSupply + requiredDepositShares);
                if (requiredWithdrawValue > basketValue) {
                    requiredWithdrawValue = basketValue;
                }
                unchecked {
                    // Overflow not possible: requiredWithdrawValue is less than or equal to basketValue
                    basketValue -= requiredWithdrawValue;
                }
                for (uint256 j = 0; j < assets.length;) {
                    targetBalances[j] = proposedTargetWeights[j] * basketValue / priceOfAssets[j];
                    unchecked {
                        ++j;
                    }
                }
                targetBalances[0] += requiredWithdrawValue / priceOfAssets[0];
            }

            // Calculate targetWeights
            for (uint256 j = 0; j < assets.length;) {
                targetWeights[j] = targetBalances[j] * priceOfAssets[j] / basketValue;
                // Check if the target weight is within the bounds compared to the proposed target weight
                uint256 diff = MathUtils.diff(targetWeights[j], proposedTargetWeights[j]);
                // If the difference is more than 1%, propose a token swap
                if (diff > 1e16) {
                    shouldRebalance = true;
                    break;
                }
                // If the worth is more than 10000 USD, proceed.
                if (diff * priceOfAssets[j] > 10_000 ether) {
                    shouldRebalance = true;
                    break;
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (!shouldRebalance) {
            revert RebalanceNotNeeded();
        }
        rebalanceStatus.timestamp = uint40(block.timestamp);
        rebalanceStatus.status = Status.REBALANCE_PROPOSED;
    }

    function proposeTokenSwap() external { }

    function executeTokenSwap() external { }

    function completeRebalance() external {
        if (block.timestamp - rebalanceStatus.timestamp < 15 minutes) {
            revert MustWaitForRebalance();
        }
        rebalanceStatus.status = Status.NOT_STARTED;
        rebalanceStatus.timestamp = uint40(block.timestamp);
        // TODO: fulfill redeems for baskets that have pending redeems
    }
}

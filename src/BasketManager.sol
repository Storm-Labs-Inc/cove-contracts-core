// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { AllocationResolver } from "src/AllocationResolver.sol";
import { BasketToken } from "src/BasketToken.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";

import { console2 as console } from "forge-std/console2.sol";

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
     *   - NOT_STARTED: Rebalance has not started.
     *   - REBALANCE_PROPOSED: Rebalance has been proposed.
     *   - TOKEN_SWAP_PROPOSED: Token swap has been proposed.
     *   - TOKEN_SWAP_EXECUTED: Token swap has been executed.
     */
    enum Status {
        NOT_STARTED,
        REBALANCE_PROPOSED,
        TOKEN_SWAP_PROPOSED,
        TOKEN_SWAP_EXECUTED
    }

    /**
     * @notice Struct representing the rebalance status.
     *   - basketHash: Hash of the baskets proposed for rebalance.
     *   - timestamp: Timestamp of the last action.
     *   - status: Status of the rebalance.
     */
    struct RebalanceStatus {
        bytes32 basketHash;
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
    /// @notice Array of all basket tokens.
    address[] public basketTokens;
    /// @notice Mapping of basket token to asset to balance.
    mapping(address basketToken => mapping(address asset => uint256 balance)) public basketBalanceOf;
    /// @notice Mapping of basketId to basket address.
    mapping(bytes32 basketId => address basketToken) public basketIdToAddress;
    /// @notice Mapping of basket token to assets.
    mapping(address basketToken => address[] basketAssets) public basketAssets;
    /// @notice Mapping of basket token to index plus one. 0 means the basket token does not exist.
    mapping(address basketToken => uint256 indexPlusOne) private _basketTokenToIndexPlusOne;
    /// @notice Mapping of basket token to pending redeeming shares.
    mapping(address basketToken => uint256 pendingRedeems) public pendingRedeems;

    /// @notice Address of the BasketToken implementation.
    address public basketTokenImplementation;
    /// @notice Address of the OracleRegistry contract used to fetch oracle values for assets.
    address public oracleRegistry;
    /// @notice Address of the AllocationResolver contract used to resolve allocations.
    AllocationResolver public allocationResolver;
    /// @notice Rebalance status.
    RebalanceStatus private _rebalanceStatus;

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
    error BasketsMismatch();
    error MustWaitForRebalance();
    error NoRebalanceInProgress();
    error TooEarlyToCompleteRebalance();
    error RebalanceNotRequired();

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
        // TODO: Add role-based access control for this function
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
     * @notice Returns the current rebalance status.
     * @return Rebalance status struct with the following fields:
     *   - basketHash: Hash of the baskets proposed for rebalance.
     *   - timestamp: Timestamp of the last action.
     *   - status: Status enum of the rebalance.
     */
    function rebalanceStatus() external view returns (RebalanceStatus memory) {
        return _rebalanceStatus;
    }

    /**
     * @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
     * target balance and the current balance of any asset in the basket is more than 500 USD.
     * @param basketsToRebalance Array of basket addresses to rebalance.
     */
    function proposeRebalance(address[] calldata basketsToRebalance) external {
        // TODO: Add role-based access control for this function
        // Checks
        // Revert if a rebalance is already in progress
        if (_rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalance();
        }
        bool shouldRebalance = false;
        for (uint256 i = 0; i < basketsToRebalance.length;) {
            address basket = basketsToRebalance[i];
            address[] memory assets = basketAssets[basket];
            if (assets.length == 0) {
                revert BasketTokenNotFound();
            }
            uint256[] memory balances = new uint256[](assets.length);
            uint256[] memory targetBalances = new uint256[](assets.length);
            uint256[] memory priceOfAssets = new uint256[](assets.length);
            uint256 basketValue = 0;

            // Calculate current basket value
            for (uint256 j = 0; j < assets.length;) {
                balances[j] = basketBalanceOf[basket][assets[j]];
                // TODO: Replace with an oracle call once the oracle is implemented
                // uint256 usdPrice = oracleRegistry.getPrice(assets[j]);
                // if (usdPrice == 0) {
                //     revert PriceOutOfSafeBounds();
                // }
                // priceOfAssets[j] = usdPrice;
                priceOfAssets[j] = 1e18;
                // Rounding direction: down
                basketValue += balances[j] * priceOfAssets[j] / 1e18;
                unchecked {
                    // Overflow not possible: j is less than assets.length
                    ++j;
                }
            }

            // Process pending deposits and fulfill them
            uint256 totalSupply = BasketToken(basket).totalSupply();
            {
                uint256 pendingDeposit = BasketToken(basket).totalPendingDeposits();
                if (pendingDeposit > 0) {
                    // Round direction: down
                    uint256 pendingDepositValue = pendingDeposit * priceOfAssets[0] / 1e18;
                    // Rounding direction: down
                    // Division-by-zero is not possible: basketValue is greater than 0
                    uint256 requiredDepositShares =
                        basketValue > 0 ? pendingDepositValue * totalSupply / basketValue : pendingDeposit;
                    totalSupply += requiredDepositShares;
                    basketValue += pendingDepositValue;
                    basketBalanceOf[basket][assets[0]] = balances[0] = balances[0] + pendingDeposit;
                    BasketToken(basket).fulfillDeposit(requiredDepositShares);
                }
            }

            // Pre-process redeems and calculate target balances
            uint256[] memory proposedTargetWeights = allocationResolver.getTargetWeight(basket);
            {
                uint256 pendingRedeems_ = BasketToken(basket).totalPendingRedeems();
                uint256 requiredWithdrawValue;

                // If there are pending redeems, calculate the required withdraw value
                // and store it in pendingWithdraw
                if (pendingRedeems_ > 0) {
                    shouldRebalance = true;
                    if (totalSupply > 0) {
                        // Rounding direction: down
                        // Division-by-zero is not possible: totalSupply is greater than 0
                        requiredWithdrawValue = basketValue * pendingRedeems_ / totalSupply;
                        if (requiredWithdrawValue > basketValue) {
                            requiredWithdrawValue = basketValue;
                        }
                        unchecked {
                            // Overflow not possible: requiredWithdrawValue is less than or equal to basketValue
                            basketValue -= requiredWithdrawValue;
                        }
                    }
                    pendingRedeems[basket] = pendingRedeems_;
                }

                // Update the target balances
                // Rounding direction: down
                // Division-by-zero is not possible: priceOfAssets[j] is greater than 0
                targetBalances[0] =
                    (proposedTargetWeights[0] * basketValue + requiredWithdrawValue * 1e18) / priceOfAssets[0];
                for (uint256 j = 1; j < assets.length;) {
                    targetBalances[j] = proposedTargetWeights[j] * basketValue / priceOfAssets[j];
                    unchecked {
                        // Overflow not possible: j is less than assets.length
                        ++j;
                    }
                }
            }

            // Check if rebalance is needed
            for (uint256 j = 0; j < assets.length;) {
                // Check if the target balance is different by more than 500 USD
                // NOTE: This implies it requires only one asset to be different by more than 500 USD
                //       to trigger a rebalance. This is placeholder logic and should be updated.
                // TODO: Update the logic to trigger a rebalance
                console.log("balances[%s]: %s", j, balances[j]);
                console.log("targetBalances[%s]: %s", j, targetBalances[j]);
                if (MathUtils.diff(balances[j], targetBalances[j]) * priceOfAssets[j] / 1e18 > 500) {
                    shouldRebalance = true;
                    break;
                }
                unchecked {
                    // Overflow not possible: j is less than assets.length
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is less than basketsToRebalance.length
                ++i;
            }
        }
        if (!shouldRebalance) {
            revert RebalanceNotRequired();
        }
        _rebalanceStatus.basketHash = keccak256(abi.encodePacked(basketsToRebalance));
        _rebalanceStatus.timestamp = uint40(block.timestamp);
        _rebalanceStatus.status = Status.REBALANCE_PROPOSED;
    }

    /**
     * @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
     * If the proposed token swap results are not close to the target balances, this function will revert.
     * @dev This function can only be called after proposeRebalance.
     */
    function proposeTokenSwap() external {
        // TODO: Implement the logic to propose token swap
    }

    /**
     * @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
     * @dev This function can only be called after proposeTokenSwap.
     */
    function executeTokenSwap() external {
        // TODO: Implement the logic to execute token swap
    }

    /**
     * @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than 15
     * minutes since the last action.
     * @param basketsToRebalance Array of basket addresses proposed for rebalance.
     */
    function completeRebalance(address[] calldata basketsToRebalance) external {
        // Check if there is any rebalance in progress
        if (_rebalanceStatus.status == Status.NOT_STARTED) {
            revert NoRebalanceInProgress();
        }
        // Check if the given baskets are the same as the ones proposed
        if (keccak256(abi.encodePacked(basketsToRebalance)) != _rebalanceStatus.basketHash) {
            revert BasketsMismatch();
        }
        // Check if the rebalance was proposed more than 15 minutes ago
        if (block.timestamp - _rebalanceStatus.timestamp < 15 minutes) {
            revert TooEarlyToCompleteRebalance();
        }
        // TODO: Add more checks for completion at different stages

        // Reset the rebalance status
        _rebalanceStatus.basketHash = bytes32(0);
        _rebalanceStatus.timestamp = uint40(block.timestamp);
        _rebalanceStatus.status = Status.NOT_STARTED;

        // Process the redeems for the given baskets
        for (uint256 i = 0; i < basketsToRebalance.length;) {
            // TODO: Make this more efficient by using calldata or by moving the logic to zk proof chain
            address basket = basketsToRebalance[i];
            address[] memory assets = basketAssets[basket];
            uint256[] memory balances = new uint256[](assets.length);
            uint256[] memory priceOfAssets = new uint256[](assets.length);
            uint256 basketValue;

            // Calculate current basket value
            for (uint256 j = 0; j < assets.length;) {
                balances[j] = basketBalanceOf[basket][assets[j]];
                // TODO: Replace with an oracle call once the oracle is implemented
                // uint256 usdPrice = oracleRegistry.getPrice(assets[j]);
                // if (usdPrice == 0) {
                //     revert PriceOutOfSafeBounds();
                // }
                // priceOfAssets[j] = usdPrice;
                priceOfAssets[j] = 1e18;
                // Rounding direction: down
                basketValue += balances[j] * priceOfAssets[j] / 1e18;
                unchecked {
                    // Overflow not possible: j is less than assets.length
                    ++j;
                }
            }

            // If there are pending redeems, process them
            uint256 pendingRedeems_ = pendingRedeems[basket];
            if (pendingRedeems_ > 0) {
                delete pendingRedeems[basket];
                uint256 withdrawValue = pendingRedeems_ * basketValue / BasketToken(basket).totalSupply();
                // Assume the first asset is always the root asset
                // Rounding direction: down
                // Division-by-zero is not possible: priceOfAssets[0] is greater than 0
                uint256 withdrawAmount = withdrawValue * 1e18 / priceOfAssets[0];
                if (withdrawAmount <= balances[0]) {
                    unchecked {
                        // Overflow not possible: withdrawAmount is less than or equal to balances[0]
                        basketBalanceOf[basket][ROOT_ASSET] = balances[0] - withdrawAmount;
                    }
                    IERC20(ROOT_ASSET).safeApprove(basket, withdrawAmount);
                    BasketToken(basket).fulfillRedeem(withdrawAmount);
                } else {
                    // TODO: Let the BasketToken contract handle failed redeems
                    // BasketToken(basket).failRedeem();
                }
            }
            unchecked {
                // Overflow not possible: i is less than basketsToRebalance.length
                ++i;
            }
        }
    }
}

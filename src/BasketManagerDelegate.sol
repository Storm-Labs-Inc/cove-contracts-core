// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity 0.8.23;

// import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

// import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import { RebalancingUtils } from "src/libraries/RebalancingUtils.sol";

// import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

// import { BasketToken } from "src/BasketToken.sol";

// import { EulerRouter } from "src/deps/euler-price-oracle/EulerRouter.sol";
// import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

// import { MathUtils } from "src/libraries/MathUtils.sol";

// import { console } from "forge-std/console.sol";

// /// @title BasketManager
// /// @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
// /// here.
// contract BasketManagerDelegate is ReentrancyGuard, AccessControlEnumerable {
//     /// LIBRARIES ///
//     using SafeERC20 for IERC20;

//     /// STRUCTS ///
//     /// @notice Enum representing the status of a rebalance.
//     enum Status {
//         // Rebalance has not started.
//         NOT_STARTED,
//         // Rebalance has been proposed.
//         REBALANCE_PROPOSED,
//         // Token swap has been proposed.
//         TOKEN_SWAP_PROPOSED,
//         // Token swap has been executed.
//         TOKEN_SWAP_EXECUTED
//     }

//     /// @notice Struct representing the rebalance status.
//     struct RebalanceStatus {
//         // Hash of the baskets proposed for rebalance.
//         bytes32 basketHash;
//         // Timestamp of the last action.
//         uint40 timestamp;
//         // Status of the rebalance.
//         Status status;
//     }

//     /// @notice Struct representing a baskets ownership of an external trade.
//     struct BasketTradeOwnership {
//         // Address of the basket.
//         address basket;
//         // Ownership of the trade with a base of 1e18. An ownershipe of 1e18 means the basket owns the entire trade.
//         uint96 tradeOwnership;
//     }

//     /// @notice Struct containing data for an internal trade.
//     struct InternalTrade {
//         // Address of the basket that is selling.
//         address fromBasket;
//         // Address of the token to sell.
//         address sellToken;
//         // Address of the token to buy.
//         address buyToken;
//         // Address of the basket that is buying.
//         address toBasket;
//         // Amount of the token to sell.
//         uint256 sellAmount;
//         // Minimum amount of the buy token that the trade results in. Used to check that the proposers oracle prices
//         // are correct.
//         uint256 minAmount;
//         // Maximum amount of the buy token that the trade can result in.
//         uint256 maxAmount;
//     }

//     /// @notice Struct containing data for an external trade.
//     struct ExternalTrade {
//         // Address of the token to sell.
//         address sellToken;
//         // Address of the token to buy.
//         address buyToken;
//         // Amount of the token to sell.
//         uint256 sellAmount;
//         // Minimum amount of the buy token that the trade results in.
//         uint256 minAmount;
//         // Array of basket trade ownerships.
//         BasketTradeOwnership[] basketTradeOwnership;
//     }

//     /// @notice Struct containing data for an internal trade.
//     struct InternalTradeInfo {
//         // Index of the basket that is selling.
//         uint256 fromBasketIndex;
//         // Index of the basket that is buying.
//         uint256 toBasketIndex;
//         // Index of the token to sell.
//         uint256 sellTokenAssetIndex;
//         // Index of the token to buy.
//         uint256 buyTokenAssetIndex;
//         // Index of the buy token in the buying basket.
//         uint256 toBasketBuyTokenIndex;
//         // Index of the sell token in the buying basket.
//         uint256 toBasketSellTokenIndex;
//         // Amount of the buy token.
//         uint256 buyAmount;
//     }

//     /// @notice Struct containing data for an external trade.
//     struct ExternalTradeInfo {
//         // Price of the sell token.
//         uint256 sellTokenPrice;
//         // Price of the buy token.
//         uint256 buyTokenPrice;
//         // Value of the sell token.
//         uint256 sellValue;
//         // Minimum amount of the buy token that the trade results in.
//         uint256 internalMinAmount;
//         // Difference between the internalMinAmount and the minAmount.
//         uint256 diff;
//     }

//     /// @notice Struct containing data for basket ownership of an external trade.
//     struct BasketOwnershipInfo {
//         // Index of the basket.
//         uint256 basketIndex;
//         // Index of the buy token asset.
//         uint256 buyTokenAssetIndex;
//         // Index of the sell token asset.
//         uint256 sellTokenAssetIndex;
//     }

//     /// CONSTANTS ///
//     /// @notice ISO 4217 numeric code for USD, used as a constant address representation
//     address private constant _USD_ISO_4217_CODE = address(840);
//     /// @notice Maximum number of basket tokens allowed to be created.
//     uint256 private constant _MAX_NUM_OF_BASKET_TOKENS = 256;
//     /// @notice Maximum slippage allowed for token swaps.
//     uint256 private constant _MAX_SLIPPAGE_BPS = 0.05e18; // .05%
//     /// @notice Maximum deviation from target weights allowed for token swaps.
//     uint256 private constant _MAX_WEIGHT_DEVIATION_BPS = 0.05e18; // .05%
//     /// @notice Precision used for weight calculations.
//     uint256 private constant _WEIGHT_PRECISION = 1e18;
//     /// @notice Manager role. Managers can create new baskets.
//     bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
//     /// @notice Pauser role.
//     bytes32 private constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
//     /// @notice Rebalancer role. Rebalancers can propose rebalance, propose token swap, and execute token swap.
//     bytes32 private constant _REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
//     /// @notice Basket token role. Given to the basket token contracts when they are created.
//     bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");

//     // /// IMMUTABLES ///
//     // /// @notice Address of the StrategyRegistry contract used to resolve and verify basket target weights.
//     // StrategyRegistry public immutable strategyRegistry;
//     // /// @notice Address of the EulerRouter contract used to fetch oracle quotes for swaps.
//     // EulerRouter public immutable eulerRouter;
//     // /// @notice Address of the BasketToken implementation.
//     // address private immutable _basketTokenImplementation;
//     address public rebalancingUtilsAddress;

//     // /// STATE VARIABLES ///
//     // /// @notice Array of all basket tokens.
//     // address[] public basketTokens;
//     // /// @notice Mapping of basket token to asset to balance.
//     // mapping(address basketToken => mapping(address asset => uint256 balance)) public basketBalanceOf;
//     // /// @notice Mapping of basketId to basket address.
//     // mapping(bytes32 basketId => address basketToken) public basketIdToAddress;
//     // /// @notice Mapping of basket token to assets.
//     // mapping(address basketToken => address[] basketAssets) public basketAssets;
//     // /// @notice Mapping of basket token to basket asset to index plus one. 0 means the basket asset does not
// exist.
//     // mapping(address basketToken => mapping(address basketAsset => uint256 indexPlusOne)) private
//     //     _basketAssetToIndexPlusOne;
//     // /// @notice Mapping of basket token to index plus one. 0 means the basket token does not exist.
//     // mapping(address basketToken => uint256 indexPlusOne) private _basketTokenToIndexPlusOne;
//     // /// @notice Mapping of basket token to pending redeeming shares.
//     // mapping(address basketToken => uint256 pendingRedeems) public pendingRedeems;
//     // /// @notice Rebalance status.
//     // RebalanceStatus private _rebalanceStatus;
//     // /// @notice A hash of the latest external trades stored during proposeTokenSwap
//     // bytes32 private _externalTradesHash;

//     /// EVENTS ///
//     /// @notice Emitted when an internal trade is settled.
//     /// @param internalTrade Internal trade that was settled.
//     /// @param buyAmount Amount of the the from token that is traded.
//     event InternalTradeSettled(InternalTrade internalTrade, uint256 buyAmount);
//     /// @notice Emitted when an external trade is settled.
//     /// @param externalTrade External trade that was settled.
//     /// @param minAmount Minimum amount of the buy token that the trade results in.
//     event ExternalTradeValidated(ExternalTrade externalTrade, uint256 minAmount);

//     /// ERRORS ///
//     error ZeroAddress();
//     error ZeroTotalSupply();
//     error ZeroBurnedShares();
//     error CannotBurnMoreSharesThanTotalSupply();
//     error BasketTokenNotFound();
//     error AssetNotFoundInBasket();
//     error BasketTokenAlreadyExists();
//     error BasketTokenMaxExceeded();
//     error ElementIndexNotFound();
//     error StrategyRegistryDoesNotSupportStrategy();
//     error BasketsMismatch();
//     error BaseAssetMismatch();
//     error AssetListEmpty();
//     error MustWaitForRebalanceToComplete();
//     error NoRebalanceInProgress();
//     error TooEarlyToCompleteRebalance();
//     error RebalanceNotRequired();
//     error ExternalTradeSlippage();
//     error TargetWeightsNotMet();
//     error InternalTradeMinMaxAmountNotReached();
//     error PriceOutOfSafeBounds();
//     error IncorrectTradeTokenAmount();

//     /// @notice Initializes the contract with the given parameters.
//     /// @param basketTokenImplementation Address of the basket token implementation.
//     /// @param eulerRouter_ Address of the oracle registry.
//     /// @param strategyRegistry_ Address of the strategy registry.
//     constructor(
//         address basketTokenImplementation,
//         address eulerRouter_,
//         address strategyRegistry_,
//         address rebalancingUtilsAddress_,
//         address admin
//     )
//         payable
//     {
//         // Effects
//         _grantRole(DEFAULT_ADMIN_ROLE, admin);
//         rebalancingUtilsAddress = rebalancingUtilsAddress_;

//         _delegateCall(
//             abi.encodeCall(
//                 RebalancingUtils.initialize,
//                 (basketTokenImplementation, eulerRouter_, strategyRegistry_, rebalancingUtilsAddress)
//             )
//         );
//     }

//     function setRebalanceUtilsImplementation(address _rebalancingUtilsAddress) external {
//         if (_rebalancingUtilsAddress == address(0)) {
//             revert ZeroAddress();
//         }
//         rebalancingUtilsAddress = _rebalancingUtilsAddress;
//     }

//     function getBasketTokenImplementation() external returns (address) {
//         return abi.decode(_delegateCall(abi.encodeCall(RebalancingUtils.getBasketTokenImplementation, ())),
// (address));
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
// }

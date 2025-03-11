// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { MulticallUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import { ERC165Upgradeable } from "@openzeppelin-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { ERC20PluginsUpgradeable } from "token-plugins-upgradeable/contracts/ERC20PluginsUpgradeable.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { Permit2Lib } from "src/deps/permit2/Permit2Lib.sol";
import { IERC7540Deposit, IERC7540Operator, IERC7540Redeem } from "src/interfaces/IERC7540.sol";
import { Errors } from "src/libraries/Errors.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

/// @title BasketToken
/// @notice Manages user deposits and redemptions, which are processed asynchronously by the Basket Manager.
/// @dev Considerations for Integrators:
///
/// When users call `requestDeposit` or `requestRedeem`, the system ensures that the controller does not have any
/// pending or claimable deposits or redeems from the controller's `lastDepositRequestId`.
///
/// This behavior allows for a potential griefing attack: an attacker can call `requestDeposit` or `requestRedeem` with
/// a minimal dust amount and specify the target controller address. As a result, the target controller would then be
/// unable to make legitimate `requestDeposit` or `requestRedeem` requests until they first claim the pending request.
///
/// RECOMMENDATION FOR INTEGRATORS: When integrating `BasketToken` into other contracts, always check for any pending or
/// claimable tokens before requesting a deposit or redeem. This ensures that any pending deposits or redeems are
/// resolved, preventing such griefing attacks.
// slither-disable-next-line missing-inheritance
contract BasketToken is
    ERC20PluginsUpgradeable,
    ERC4626Upgradeable,
    ERC165Upgradeable,
    IERC7540Operator,
    IERC7540Deposit,
    IERC7540Redeem,
    MulticallUpgradeable,
    ERC20PermitUpgradeable
{
    /// LIBRARIES ///
    using SafeERC20 for IERC20;

    /// CONSTANTS ///
    /// @notice ISO 4217 numeric code for USD, used as a constant address representation
    address private constant _USD_ISO_4217_CODE = address(840);
    uint16 private constant _MANAGEMENT_FEE_DECIMALS = 1e4;
    /// @notice Maximum management fee (30%) in BPS denominated in 1e4.
    uint16 private constant _MAX_MANAGEMENT_FEE = 3000;
    string private constant _NAME_PREFIX = "CoveBasket ";
    string private constant _SYMBOL_PREFIX = "cvt";

    /// @notice Struct representing a deposit request.
    struct DepositRequestStruct {
        // Mapping of controller addresses to their deposited asset amounts.
        mapping(address controller => uint256 assets) depositAssets;
        // Total amount of assets deposited in this request.
        uint256 totalDepositAssets;
        // Number of shares fulfilled for this deposit request.
        uint256 fulfilledShares;
    }

    /// @notice Typed tuple for externally viewing DepositRequestStruct without the mapping.
    struct DepositRequestView {
        // Total amount of assets deposited in this request.
        uint256 totalDepositAssets;
        // Number of shares fulfilled for this deposit request.
        uint256 fulfilledShares;
    }

    /// @notice Struct representing a redeem request.
    struct RedeemRequestStruct {
        // Mapping of controller addresses to their shares to be redeemed.
        mapping(address controller => uint256 shares) redeemShares;
        // Total number of shares to be redeemed in this request.
        uint256 totalRedeemShares;
        // Amount of assets fulfilled for this redeem request.
        uint256 fulfilledAssets;
        // Flag indicating if the fallback redemption process has been triggered.
        bool fallbackTriggered;
    }

    /// @notice Typed tuple for externally viewing RedeemRequestStruct without the mapping.
    struct RedeemRequestView {
        // Total number of shares to be redeemed in this request.
        uint256 totalRedeemShares;
        // Amount of assets fulfilled for this redeem request.
        uint256 fulfilledAssets;
        // Flag indicating if the fallback redemption process has been triggered.
        bool fallbackTriggered;
    }

    /// STATE VARIABLES ///
    /// @notice Operator approval status per controller.
    mapping(address controller => mapping(address operator => bool)) public isOperator;
    /// @notice Last deposit request ID per controller.
    mapping(address controller => uint256 requestId) public lastDepositRequestId;
    /// @notice Last redemption request ID per controller.
    mapping(address controller => uint256 requestId) public lastRedeemRequestId;
    /// @dev Deposit requests mapped by request ID. Even IDs are for deposits.
    mapping(uint256 requestId => DepositRequestStruct) internal _depositRequests;
    /// @dev Redemption requests mapped by request ID. Odd IDs are for redemptions.
    mapping(uint256 requestId => RedeemRequestStruct) internal _redeemRequests;
    /// @notice Address of the BasketManager contract handling deposits and redemptions.
    address public basketManager;
    /// @notice Upcoming deposit request ID.
    uint256 public nextDepositRequestId;
    /// @notice Upcoming redemption request ID.
    uint256 public nextRedeemRequestId;
    /// @notice Address of the AssetRegistry contract for asset status checks.
    address public assetRegistry;
    /// @notice Bitflag representing selected assets.
    uint256 public bitFlag;
    /// @notice Strategy contract address associated with this basket.
    address public strategy;
    /// @notice Timestamp of the last management fee harvest.
    uint40 public lastManagementFeeHarvestTimestamp;

    /// EVENTS ///
    /// @notice Emitted when the management fee is harvested.
    /// @param fee The amount of the management fee harvested.
    event ManagementFeeHarvested(uint256 fee);
    /// @notice Emitted when a deposit request is fulfilled and assets are transferred to the user.
    /// @param requestId The unique identifier of the deposit request.
    /// @param assets The amount of assets that were deposited.
    /// @param shares The number of shares minted for the deposit.
    event DepositFulfilled(uint256 indexed requestId, uint256 assets, uint256 shares);
    /// @notice Emitted when a redemption request is fulfilled and shares are burned.
    /// @param requestId The unique identifier of the redemption request.
    /// @param shares The number of shares redeemed.
    /// @param assets The amount of assets returned to the user.
    event RedeemFulfilled(uint256 indexed requestId, uint256 shares, uint256 assets);
    /// @notice Emitted when the bitflag is updated to a new value.
    /// @param oldBitFlag The previous bitflag value.
    /// @param newBitFlag The new bitflag value.
    event BitFlagUpdated(uint256 oldBitFlag, uint256 newBitFlag);
    /// @notice Emitted when a deposit request is queued and awaiting fulfillment.
    /// @param depositRequestId The unique identifier of the deposit request.
    /// @param pendingDeposits The total amount of assets pending deposit.
    event DepositRequestQueued(uint256 depositRequestId, uint256 pendingDeposits);
    /// @notice Emitted when a redeem request is queued and awaiting fulfillment.
    /// @param redeemRequestId The unique identifier of the redeem request.
    /// @param pendingShares The total amount of shares pending redemption.
    event RedeemRequestQueued(uint256 redeemRequestId, uint256 pendingShares);

    /// ERRORS ///
    /// @notice Thrown when there are no pending deposits to fulfill.
    error ZeroPendingDeposits();
    /// @notice Thrown when there are no pending redeems to fulfill.
    error ZeroPendingRedeems();
    /// @notice Thrown when attempting to request a deposit or redeem while one or more of the basket's assets are
    /// paused in the AssetRegistry.
    error AssetPaused();
    /// @notice Thrown when attempting to request a new deposit while the user has an outstanding claimable deposit from
    /// a previous request. The user must first claim the outstanding deposit.
    error MustClaimOutstandingDeposit();
    /// @notice Thrown when attempting to request a new redeem while the user has an outstanding claimable redeem from a
    /// previous request. The user must first claim the outstanding redeem.
    error MustClaimOutstandingRedeem();
    /// @notice Thrown when attempting to claim a partial amount of an outstanding deposit or redeem. The user must
    /// claim the full claimable amount.
    error MustClaimFullAmount();
    /// @notice Thrown when the basket manager attempts to fulfill a deposit request with zero shares.
    error CannotFulfillWithZeroShares();
    /// @notice Thrown when the basket manager attempts to fulfill a redeem request with zero assets.
    error CannotFulfillWithZeroAssets();
    /// @notice Thrown when attempting to claim fallback shares when none are available.
    error ZeroClaimableFallbackShares();
    /// @notice Thrown when a non-authorized address attempts to request a deposit or redeem on behalf of another user
    /// who has not approved them as an operator.
    error NotAuthorizedOperator();
    /// @notice Thrown when an address other than the basket manager attempts to call a basket manager only function.
    error NotBasketManager();
    /// @notice Thrown when an address other than the feeCollector attempts to harvest management fees.
    error NotFeeCollector();
    /// @notice Thrown when attempting to set an invalid management fee percentage greater than the maximum allowed.
    error InvalidManagementFee();
    /// @notice Thrown when the basket manager attempts to fulfill a deposit request that has already been fulfilled.
    error DepositRequestAlreadyFulfilled();
    /// @notice Thrown when the basket manager attempts to fulfill a redeem request that has already been fulfilled.
    error RedeemRequestAlreadyFulfilled();
    /// @notice Thrown when the basket manager attempts to trigger the fallback for a redeem request that has already
    /// been put in fallback state.
    error RedeemRequestAlreadyFallbacked();
    /// @notice Thrown when attempting to prepare for a new rebalance before the previous epoch's deposit request has
    /// been fulfilled.
    error PreviousDepositRequestNotFulfilled();
    /// @notice Thrown when attempting to prepare for a new rebalance before the previous epoch's redeem request has
    /// been fulfilled or put in fallback state.
    error PreviousRedeemRequestNotFulfilled();

    /// @notice Disables initializer functions.
    constructor() payable {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @param asset_ Address of the underlying asset.
    /// @param name_ Name of the token, prefixed with "CoveBasket-".
    /// @param symbol_ Symbol of the token, prefixed with "cb".
    /// @param bitFlag_ Bitflag representing selected assets.
    /// @param strategy_ Strategy contract address.
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        address strategy_,
        address assetRegistry_
    )
        public
        initializer
    {
        if (strategy_ == address(0) || assetRegistry_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        basketManager = msg.sender;
        bitFlag = bitFlag_;
        strategy = strategy_;
        assetRegistry = assetRegistry_;
        nextDepositRequestId = 2;
        nextRedeemRequestId = 3;
        __ERC4626_init(asset_);
        string memory tokenName = string.concat(_NAME_PREFIX, name_);
        __ERC20_init(tokenName, string.concat(_SYMBOL_PREFIX, symbol_));
        __ERC20Permit_init(tokenName);
        __ERC20Plugins_init(8, 2_000_000);
    }

    /// @notice Returns the value of the basket in assets. This will be an estimate as it does not account for other
    /// factors that may affect the swap rates.
    /// @return The total value of the basket in assets.
    function totalAssets() public view override returns (uint256) {
        address[] memory assets = getAssets();
        uint256 usdAmount;
        uint256 assetsLength = assets.length;

        BasketManager bm = BasketManager(basketManager);
        EulerRouter eulerRouter = EulerRouter(bm.eulerRouter());

        for (uint256 i = 0; i < assetsLength;) {
            // slither-disable-start calls-loop
            uint256 assetBalance = bm.basketBalanceOf(address(this), assets[i]);
            // Rounding direction: down
            usdAmount += eulerRouter.getQuote(assetBalance, assets[i], _USD_ISO_4217_CODE);
            // slither-disable-end calls-loop

            unchecked {
                // Overflow not possible: i is less than assetsLength
                ++i;
            }
        }

        return eulerRouter.getQuote(usdAmount, _USD_ISO_4217_CODE, asset());
    }

    /// @notice Returns the target weights for the given epoch.
    /// @return The target weights for the basket.
    function getTargetWeights() public view returns (uint64[] memory) {
        return WeightStrategy(strategy).getTargetWeights(bitFlag);
    }

    /// @notice Returns all assets that are eligible to be included in this basket based on the bitFlag
    /// @dev This returns the complete list of eligible assets from the AssetRegistry, filtered by this basket's
    /// bitFlag.
    ///      The list includes all assets that could potentially be part of the basket, regardless of:
    ///      - Their current balance in the basket
    ///      - Their current target weight
    ///      - Whether they are paused
    /// @return Array of asset token addresses that are eligible for this basket
    function getAssets() public view returns (address[] memory) {
        return AssetRegistry(assetRegistry).getAssets(bitFlag);
    }

    /// ERC7540 LOGIC ///

    /// @notice Transfers assets from owner and submits a request for an asynchronous deposit.
    /// @param assets The amount of assets to deposit.
    /// @param controller The address of the controller of the position being created.
    /// @param owner The address of the owner of the assets being deposited.
    /// @dev Reverts on 0 assets or if the caller is not the owner or operator of the assets being deposited.
    function requestDeposit(uint256 assets, address controller, address owner) public returns (uint256 requestId) {
        // Checks
        if (msg.sender != owner) {
            if (!isOperator[owner][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        requestId = nextDepositRequestId;
        uint256 userLastDepositRequestId = lastDepositRequestId[controller];
        // If the user has a pending deposit request in the past, they must wait for it to be fulfilled before making a
        // new one
        if (userLastDepositRequestId != requestId) {
            if (pendingDepositRequest(userLastDepositRequestId, controller) > 0) {
                revert MustClaimOutstandingDeposit();
            }
        }
        // If the user has a claimable deposit request, they must claim it before making a new one
        if (claimableDepositRequest(userLastDepositRequestId, controller) > 0) {
            revert MustClaimOutstandingDeposit();
        }
        if (AssetRegistry(assetRegistry).hasPausedAssets(bitFlag)) {
            revert AssetPaused();
        }
        // Effects
        DepositRequestStruct storage depositRequest = _depositRequests[requestId];
        // update controllers balance of assets pending deposit
        depositRequest.depositAssets[controller] += assets;
        // update total pending deposits for the current requestId
        depositRequest.totalDepositAssets += assets;
        // update controllers latest deposit request id
        lastDepositRequestId[controller] = requestId;
        emit DepositRequest(controller, owner, requestId, msg.sender, assets);
        // Interactions
        // Assets are immediately transferred to here to await the basketManager to pull them
        // slither-disable-next-line arbitrary-send-erc20
        Permit2Lib.transferFrom2(IERC20(asset()), owner, address(this), assets);
    }

    /// @notice Returns the pending deposit request amount for a controller.
    /// @dev If the epoch has been advanced then the request has been fulfilled and is no longer pending.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller of the deposit request.
    /// @return assets The amount of assets pending deposit.
    function pendingDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        DepositRequestStruct storage depositRequest = _depositRequests[requestId];
        assets = depositRequest.fulfilledShares == 0 ? depositRequest.depositAssets[controller] : 0;
    }

    /// @notice Returns the amount of requested assets in Claimable state for the controller with the given requestId.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller.
    function claimableDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        DepositRequestStruct storage depositRequest = _depositRequests[requestId];
        assets = _claimableDepositRequest(depositRequest.fulfilledShares, depositRequest.depositAssets[controller]);
    }

    function _claimableDepositRequest(
        uint256 fulfilledShares,
        uint256 depositAssets
    )
        internal
        pure
        returns (uint256 assets)
    {
        return fulfilledShares != 0 ? depositAssets : 0;
    }

    /// @notice Requests a redemption of shares from the basket.
    /// @param shares The amount of shares to redeem.
    /// @param controller The address of the controller of the redeemed shares.
    /// @param owner The address of the request owner.
    function requestRedeem(uint256 shares, address controller, address owner) public returns (uint256 requestId) {
        // Checks
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        requestId = nextRedeemRequestId;
        // If the user has a pending redeem request in the past, they must wait for it to be fulfilled before making a
        // new one
        uint256 userLastRedeemRequestId = lastRedeemRequestId[controller];
        if (userLastRedeemRequestId != requestId) {
            if (pendingRedeemRequest(userLastRedeemRequestId, controller) > 0) {
                revert MustClaimOutstandingRedeem();
            }
        }
        // If the user has a claimable redeem request, they must claim it before making a new one
        if (claimableRedeemRequest(userLastRedeemRequestId, controller) > 0 || claimableFallbackShares(controller) > 0)
        {
            revert MustClaimOutstandingRedeem();
        }
        if (msg.sender != owner) {
            if (!isOperator[owner][msg.sender]) {
                _spendAllowance(owner, msg.sender, shares);
            }
        }
        if (AssetRegistry(assetRegistry).hasPausedAssets(bitFlag)) {
            revert AssetPaused();
        }

        // Effects
        RedeemRequestStruct storage redeemRequest = _redeemRequests[requestId];
        // update total pending redemptions for the current requestId
        redeemRequest.totalRedeemShares += shares;
        // update controllers latest redeem request id
        lastRedeemRequestId[controller] = requestId;
        // update controllers balance of assets pending deposit
        redeemRequest.redeemShares[controller] += shares;
        _transfer(owner, address(this), shares);
        emit RedeemRequest(controller, owner, requestId, msg.sender, shares);
    }

    /// @notice Returns the pending redeem request amount for a user.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller of the redemption request.
    /// @return shares The amount of shares pending redemption.
    function pendingRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        RedeemRequestStruct storage redeemRequest = _redeemRequests[requestId];
        shares = redeemRequest.fulfilledAssets == 0 && !redeemRequest.fallbackTriggered
            ? redeemRequest.redeemShares[controller]
            : 0;
    }

    /// @notice Returns the amount of requested shares in Claimable state for the controller with the given requestId.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller of the redemption request.
    /// @return shares The amount of shares claimable.
    // solhint-disable-next-line no-unused-vars
    function claimableRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        RedeemRequestStruct storage redeemRequest = _redeemRequests[requestId];
        shares = _claimableRedeemRequest(redeemRequest.fulfilledAssets, redeemRequest.redeemShares[controller]);
    }

    function _claimableRedeemRequest(
        uint256 fulfilledAssets,
        uint256 redeemShares
    )
        internal
        pure
        returns (uint256 shares)
    {
        return fulfilledAssets != 0 ? redeemShares : 0;
    }

    /// @notice Fulfills all pending deposit requests. Only callable by the basket manager. Assets are held by the
    /// basket manager. Locks in the rate at which users can claim their shares for deposited assets.
    /// @param shares The amount of shares the deposit was fulfilled with.
    function fulfillDeposit(uint256 shares) public {
        // Checks
        _onlyBasketManager();
        // currentRequestId was advanced by 2 to prepare for rebalance
        uint256 currentRequestId = nextDepositRequestId - 2;
        DepositRequestStruct storage depositRequest = _depositRequests[currentRequestId];
        uint256 assets = depositRequest.totalDepositAssets;
        if (assets == 0) {
            revert ZeroPendingDeposits();
        }
        if (shares == 0) {
            revert CannotFulfillWithZeroShares();
        }
        if (depositRequest.fulfilledShares > 0) {
            revert DepositRequestAlreadyFulfilled();
        }
        // Effects
        depositRequest.fulfilledShares = shares;
        emit DepositFulfilled(currentRequestId, assets, shares);
        _mint(address(this), shares);
        // Interactions
        // transfer the assets to the basket manager
        IERC20(asset()).safeTransfer(msg.sender, assets);
    }

    /// @notice Sets the new bitflag for the basket.
    /// @dev This can only be called by the Basket Manager therefore we assume that the new bitflag is valid.
    /// @param bitFlag_ The new bitflag.
    function setBitFlag(uint256 bitFlag_) public {
        _onlyBasketManager();
        uint256 oldBitFlag = bitFlag;
        bitFlag = bitFlag_;
        emit BitFlagUpdated(oldBitFlag, bitFlag_);
    }

    /// @notice Prepares the basket token for rebalancing by processing pending deposits and redemptions.
    /// @dev This function:
    /// - Verifies previous deposit/redeem requests were fulfilled
    /// - Advances deposit/redeem epochs if there are pending requests
    /// - Harvests management fees
    /// - Can only be called by the basket manager
    /// - Called at the start of rebalancing regardless of pending requests
    /// - Does not advance epochs if there are no pending requests
    /// @param feeBps The management fee in basis points to be harvested.
    /// @param feeCollector The address that will receive the harvested management fee.
    /// @return pendingDeposits The total amount of base assets pending deposit.
    /// @return pendingShares The total amount of shares pending redemption.
    function prepareForRebalance(
        uint16 feeBps,
        address feeCollector
    )
        external
        returns (uint256 pendingDeposits, uint256 pendingShares)
    {
        _onlyBasketManager();
        uint256 nextDepositRequestId_ = nextDepositRequestId;
        uint256 nextRedeemRequestId_ = nextRedeemRequestId;

        // Check if previous deposit request has been fulfilled
        DepositRequestStruct storage previousDepositRequest = _depositRequests[nextDepositRequestId_ - 2];
        if (previousDepositRequest.totalDepositAssets > 0) {
            if (previousDepositRequest.fulfilledShares == 0) {
                revert PreviousDepositRequestNotFulfilled();
            }
        }

        // Check if previous redeem request has been fulfilled or fallbacked
        RedeemRequestStruct storage previousRedeemRequest = _redeemRequests[nextRedeemRequestId_ - 2];
        if (previousRedeemRequest.totalRedeemShares > 0) {
            if (previousRedeemRequest.fulfilledAssets == 0) {
                if (!previousRedeemRequest.fallbackTriggered) {
                    revert PreviousRedeemRequestNotFulfilled();
                }
            }
        }

        // Get current pending deposits
        pendingDeposits = _depositRequests[nextDepositRequestId_].totalDepositAssets;
        if (pendingDeposits > 0) {
            emit DepositRequestQueued(nextDepositRequestId_, pendingDeposits);
            nextDepositRequestId = nextDepositRequestId_ + 2;
        }

        pendingShares = _redeemRequests[nextRedeemRequestId_].totalRedeemShares;
        if (pendingShares > 0) {
            emit RedeemRequestQueued(nextRedeemRequestId_, pendingShares);
            nextRedeemRequestId = nextRedeemRequestId_ + 2;
        }

        _harvestManagementFee(feeBps, feeCollector);
    }

    /// @notice Fulfills all pending redeem requests. Only callable by the basket manager. Burns the shares which are
    /// pending redemption. Locks in the rate at which users can claim their assets for redeemed shares.
    /// @dev prepareForRebalance must be called before this function.
    /// @param assets The amount of assets the redemption was fulfilled with.
    function fulfillRedeem(uint256 assets) public {
        // Checks
        _onlyBasketManager();
        uint256 currentRequestId = nextRedeemRequestId - 2;
        RedeemRequestStruct storage redeemRequest = _redeemRequests[currentRequestId];
        uint256 sharesPendingRedemption = redeemRequest.totalRedeemShares;
        if (sharesPendingRedemption == 0) {
            revert ZeroPendingRedeems();
        }
        if (assets == 0) {
            revert CannotFulfillWithZeroAssets();
        }
        if (redeemRequest.fulfilledAssets > 0) {
            revert RedeemRequestAlreadyFulfilled();
        }
        // Effects
        redeemRequest.fulfilledAssets = assets;
        emit RedeemFulfilled(currentRequestId, sharesPendingRedemption, assets);
        _burn(address(this), sharesPendingRedemption);
        // Interactions
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @notice Retrieves the total amount of assets currently pending deposit.
    /// @dev Once a rebalance is proposed, any pending deposits are processed and this function will return the pending
    /// deposits of the next epoch.
    /// @return The total pending deposit amount.
    function totalPendingDeposits() public view returns (uint256) {
        return _depositRequests[nextDepositRequestId].totalDepositAssets;
    }

    /// @notice Returns the total number of shares pending redemption.
    /// @dev Once a rebalance is proposed, any pending redemptions are processed and this function will return the
    /// pending redemptions of the next epoch.
    /// @return The total pending redeem amount.
    function totalPendingRedemptions() public view returns (uint256) {
        return _redeemRequests[nextRedeemRequestId].totalRedeemShares;
    }

    /// @notice Cancels a pending deposit request.
    function cancelDepositRequest() public {
        // Checks
        uint256 nextDepositRequestId_ = nextDepositRequestId;
        uint256 pendingDeposit = pendingDepositRequest(nextDepositRequestId_, msg.sender);
        if (pendingDeposit == 0) {
            revert ZeroPendingDeposits();
        }
        // Effects
        DepositRequestStruct storage depositRequest = _depositRequests[nextDepositRequestId_];
        depositRequest.depositAssets[msg.sender] = 0;
        depositRequest.totalDepositAssets -= pendingDeposit;
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, pendingDeposit);
    }

    /// @notice Cancels a pending redeem request.
    function cancelRedeemRequest() public {
        // Checks
        uint256 nextRedeemRequestId_ = nextRedeemRequestId;
        uint256 pendingRedeem = pendingRedeemRequest(nextRedeemRequestId_, msg.sender);
        if (pendingRedeem == 0) {
            revert ZeroPendingRedeems();
        }
        // Effects
        RedeemRequestStruct storage redeemRequest = _redeemRequests[nextRedeemRequestId_];
        redeemRequest.redeemShares[msg.sender] = 0;
        redeemRequest.totalRedeemShares -= pendingRedeem;
        _transfer(address(this), msg.sender, pendingRedeem);
    }

    /// @notice Sets a status for an operator's ability to act on behalf of a controller.
    /// @param operator The address of the operator.
    /// @param approved The status of the operator.
    /// @return success True if the operator status was set, false otherwise.
    function setOperator(address operator, bool approved) public returns (bool success) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /// @dev Reverts if the controller is not the caller or the operator of the caller.
    function _onlySelfOrOperator(address controller) internal view {
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
    }

    /// @dev Reverts if the caller is not the Basket Manager.
    function _onlyBasketManager() internal view {
        if (basketManager != msg.sender) {
            revert NotBasketManager();
        }
    }

    /// @notice Returns the address of the share token as per ERC-7575.
    /// @return shareTokenAddress The address of the share token.
    /// @dev For non-multi asset vaults this should always return address(this).
    function share() public view returns (address shareTokenAddress) {
        shareTokenAddress = address(this);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice In the event of a failed redemption fulfillment this function is called by the basket manager. Allows
    /// users to claim their shares back for a redemption in the future and advances the redemption epoch.
    function fallbackRedeemTrigger() public {
        _onlyBasketManager();
        // Check if the redeem is going on. If not, revert
        uint256 currentRedeemRequestId = nextRedeemRequestId - 2;
        RedeemRequestStruct storage redeemRequest = _redeemRequests[currentRedeemRequestId];
        if (redeemRequest.fallbackTriggered) {
            revert RedeemRequestAlreadyFallbacked();
        }
        if (redeemRequest.fulfilledAssets > 0) {
            revert RedeemRequestAlreadyFulfilled();
        }
        if (redeemRequest.totalRedeemShares == 0) {
            revert ZeroPendingRedeems();
        }
        redeemRequest.fallbackTriggered = true;
    }

    /// @notice Claims shares given for a previous redemption request in the event a redemption fulfillment for a
    /// given epoch fails.
    /// @param receiver The address to receive the shares.
    /// @param controller The address of the controller of the redemption request.
    /// @return shares The amount of shares claimed.
    function claimFallbackShares(address receiver, address controller) public returns (uint256 shares) {
        // Checks
        _onlySelfOrOperator(controller);
        shares = claimableFallbackShares(controller);
        if (shares == 0) {
            revert ZeroClaimableFallbackShares();
        }
        // Effects
        _redeemRequests[lastRedeemRequestId[controller]].redeemShares[controller] = 0;
        _transfer(address(this), receiver, shares);
    }

    /// @notice Allows the caller to claim their own fallback shares.
    /// @return shares The amount of shares claimed.
    function claimFallbackShares() public returns (uint256 shares) {
        return claimFallbackShares(msg.sender, msg.sender);
    }

    /// @notice Returns the amount of shares claimable for a given user in the event of a failed redemption
    /// fulfillment.
    /// @param controller The address of the controller.
    /// @return shares The amount of shares claimable by the controller.
    function claimableFallbackShares(address controller) public view returns (uint256 shares) {
        RedeemRequestStruct storage redeemRequest = _redeemRequests[lastRedeemRequestId[controller]];
        if (redeemRequest.fallbackTriggered) {
            return redeemRequest.redeemShares[controller];
        }
        return 0;
    }

    /// @notice Immediately redeems shares for all assets associated with this basket. This is synchronous and does not
    /// require the rebalance process to be completed.
    /// @param shares Number of shares to redeem.
    /// @param to Address to receive the assets.
    /// @param from Address to redeem shares from.
    function proRataRedeem(uint256 shares, address to, address from) public {
        // Checks and effects
        if (msg.sender != from) {
            if (!isOperator[from][msg.sender]) {
                _spendAllowance(from, msg.sender, shares);
            }
        }

        // Interactions
        BasketManager bm = BasketManager(basketManager);
        _harvestManagementFee(bm.managementFee(address(this)), bm.feeCollector());
        bm.proRataRedeem(totalSupply(), shares, to);

        // We intentionally defer the `_burn()` operation until after the external call to
        // `BasketManager.proRataRedeem()` to prevent potential price manipulation via read-only reentrancy attacks. By
        // performing the external interaction before updating balances, we ensure that total supply and user balances
        // cannot be manipulated if a malicious contract attempts to reenter during the ERC20 transfer (e.g., through
        // ERC777 tokens or plugins with callbacks).
        _burn(from, shares);
    }

    /// @notice Harvests management fees owed to the fee collector.
    function harvestManagementFee() external {
        BasketManager bm = BasketManager(basketManager);
        address feeCollector = bm.feeCollector();
        if (msg.sender != feeCollector) {
            revert NotFeeCollector();
        }
        uint16 feeBps = bm.managementFee(address(this));
        _harvestManagementFee(feeBps, feeCollector);
    }

    /// @notice Internal function to harvest management fees. Updates the timestamp of the last management fee harvest
    /// if a non zero fee is collected. Mints the fee to the fee collector and notifies the basket manager.
    /// @param feeBps The management fee in basis points to be harvested.
    /// @param feeCollector The address that will receive the harvested management fee.
    // slither-disable-next-line timestamp
    function _harvestManagementFee(uint16 feeBps, address feeCollector) internal {
        // Checks
        if (feeBps > _MAX_MANAGEMENT_FEE) {
            revert InvalidManagementFee();
        }
        uint256 timeSinceLastHarvest = block.timestamp - lastManagementFeeHarvestTimestamp;

        // Effects
        if (feeBps != 0) {
            if (timeSinceLastHarvest != 0) {
                // remove shares held by the treasury
                uint256 currentTotalSupply = totalSupply() - balanceOf(feeCollector);
                if (currentTotalSupply > 0) {
                    uint256 fee = FixedPointMathLib.fullMulDiv(
                        currentTotalSupply,
                        feeBps * timeSinceLastHarvest,
                        ((_MANAGEMENT_FEE_DECIMALS - feeBps) * uint256(365 days))
                    );
                    if (fee != 0) {
                        lastManagementFeeHarvestTimestamp = uint40(block.timestamp);
                        emit ManagementFeeHarvested(fee);
                        _mint(feeCollector, fee);
                        // Interactions
                        FeeCollector(feeCollector).notifyHarvestFee(fee);
                    }
                } else {
                    lastManagementFeeHarvestTimestamp = uint40(block.timestamp);
                }
            }
        } else {
            lastManagementFeeHarvestTimestamp = uint40(block.timestamp);
        }
    }

    /// ERC4626 OVERRIDDEN LOGIC ///

    /// @notice Transfers a user's shares owed for a previously fulfillled deposit request.
    /// @param assets The amount of assets previously requested for deposit.
    /// @param receiver The address to receive the shares.
    /// @param controller The address of the controller of the deposit request.
    /// @return shares The amount of shares minted.
    function deposit(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
        // Checks
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        _onlySelfOrOperator(controller);
        DepositRequestStruct storage depositRequest = _depositRequests[lastDepositRequestId[controller]];
        uint256 fulfilledShares = depositRequest.fulfilledShares;
        uint256 depositAssets = depositRequest.depositAssets[controller];
        if (assets != _claimableDepositRequest(fulfilledShares, depositAssets)) {
            revert MustClaimFullAmount();
        }
        shares = _maxMint(fulfilledShares, depositAssets, depositRequest.totalDepositAssets);
        // Effects
        _claimDeposit(depositRequest, assets, shares, receiver, controller);
    }

    /// @notice Transfers a user's shares owed for a previously fulfillled deposit request.
    /// @param assets The amount of assets to be claimed.
    /// @param receiver The address to receive the assets.
    /// @return shares The amount of shares previously requested for redemption.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        return deposit(assets, receiver, msg.sender);
    }

    /// @notice Transfers a user's shares owed for a previously fulfillled deposit request.
    /// @dev Deposit should be used in all instances instead.
    /// @param shares The amount of shares to receive.
    /// @param receiver The address to receive the shares.
    /// @param controller The address of the controller of the deposit request.
    /// @return assets The amount of assets previously requested for deposit.
    function mint(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        // Checks
        _onlySelfOrOperator(controller);
        DepositRequestStruct storage depositRequest = _depositRequests[lastDepositRequestId[controller]];
        uint256 fulfilledShares = depositRequest.fulfilledShares;
        uint256 depositAssets = depositRequest.depositAssets[controller];
        if (shares != _maxMint(fulfilledShares, depositAssets, depositRequest.totalDepositAssets)) {
            revert MustClaimFullAmount();
        }
        // Effects
        assets = _claimableDepositRequest(fulfilledShares, depositAssets);
        _claimDeposit(depositRequest, assets, shares, receiver, controller);
    }

    /// @notice Transfers a user's shares owed for a previously fulfillled deposit request.
    /// @param shares The amount of shares to receive.
    /// @param receiver The address to receive the shares.
    /// @return assets The amount of assets previously requested for deposit.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        return mint(shares, receiver, msg.sender);
    }

    /// @notice Internal function to claim deposit for a given amount of assets and shares.
    /// @param assets The amount of assets to claim.
    /// @param shares The amount of shares to claim.
    /// @param receiver The address of the receiver of the claimed assets.
    /// @param controller The address of the controller of the deposit request.
    function _claimDeposit(
        DepositRequestStruct storage depositRequest,
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    )
        internal
    {
        // Effects
        depositRequest.depositAssets[controller] = 0;
        emit Deposit(controller, receiver, assets, shares);
        // Interactions
        _transfer(address(this), receiver, shares);
    }

    /// @notice Transfers a user's assets owed for a previously fulfillled redemption request.
    /// @dev Redeem should be used in all instances instead.
    /// @param assets The amount of assets to be claimed.
    /// @param receiver The address to receive the assets.
    /// @param controller The address of the controller of the redeem request.
    /// @return shares The amount of shares previously requested for redemption.
    function withdraw(uint256 assets, address receiver, address controller) public override returns (uint256 shares) {
        // Checks
        _onlySelfOrOperator(controller);
        RedeemRequestStruct storage redeemRequest = _redeemRequests[lastRedeemRequestId[controller]];
        uint256 fulfilledAssets = redeemRequest.fulfilledAssets;
        uint256 redeemShares = redeemRequest.redeemShares[controller];
        if (assets != _maxWithdraw(fulfilledAssets, redeemShares, redeemRequest.totalRedeemShares)) {
            revert MustClaimFullAmount();
        }
        shares = _claimableRedeemRequest(fulfilledAssets, redeemShares);
        // Effects
        _claimRedemption(redeemRequest, assets, shares, receiver, controller);
    }

    /// @notice Transfers the receiver assets owed for a fulfilled redeem request.
    /// @param shares The amount of shares to be claimed.
    /// @param receiver The address to receive the assets.
    /// @param controller The address of the controller of the redeem request.
    /// @return assets The amount of assets previously requested for redemption.
    function redeem(uint256 shares, address receiver, address controller) public override returns (uint256 assets) {
        // Checks
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        _onlySelfOrOperator(controller);
        RedeemRequestStruct storage redeemRequest = _redeemRequests[lastRedeemRequestId[controller]];
        uint256 fulfilledAssets = redeemRequest.fulfilledAssets;
        uint256 redeemShares = redeemRequest.redeemShares[controller];
        if (shares != _claimableRedeemRequest(fulfilledAssets, redeemShares)) {
            revert MustClaimFullAmount();
        }
        assets = _maxWithdraw(fulfilledAssets, redeemShares, redeemRequest.totalRedeemShares);
        // Effects & Interactions
        _claimRedemption(redeemRequest, assets, shares, receiver, controller);
    }

    /// @notice Internal function to claim redemption for a given amount of assets and shares.
    /// @param assets The amount of assets to claim.
    /// @param shares The amount of shares to claim.
    /// @param receiver The address of the receiver of the claimed assets.
    /// @param controller The address of the controller of the redemption request.
    function _claimRedemption(
        RedeemRequestStruct storage redeemRequest,
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    )
        internal
    {
        // Effects
        redeemRequest.redeemShares[controller] = 0;
        emit Withdraw(msg.sender, receiver, controller, assets, shares);
        // Interactions
        IERC20(asset()).safeTransfer(receiver, assets);
    }

    /// @notice Returns an controller's amount of assets fulfilled for redemption.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param controller The address of the controller.
    /// @return The amount of assets that can be withdrawn.
    function maxWithdraw(address controller) public view override returns (uint256) {
        RedeemRequestStruct storage redeemRequest = _redeemRequests[lastRedeemRequestId[controller]];
        return _maxWithdraw(
            redeemRequest.fulfilledAssets, redeemRequest.redeemShares[controller], redeemRequest.totalRedeemShares
        );
    }

    function _maxWithdraw(
        uint256 fulfilledAssets,
        uint256 redeemShares,
        uint256 totalRedeemShares
    )
        internal
        pure
        returns (uint256)
    {
        return
            totalRedeemShares == 0 ? 0 : FixedPointMathLib.fullMulDiv(fulfilledAssets, redeemShares, totalRedeemShares);
    }

    /// @notice Returns an controller's amount of shares fulfilled for redemption.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param controller The address of the controller.
    /// @return The amount of shares that can be redeemed.
    function maxRedeem(address controller) public view override returns (uint256) {
        return claimableRedeemRequest(lastRedeemRequestId[controller], controller);
    }

    /// @notice Returns an controller's amount of assets fulfilled for deposit.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param controller The address of the controller.
    /// @return The amount of assets that can be deposited.
    function maxDeposit(address controller) public view override returns (uint256) {
        return claimableDepositRequest(lastDepositRequestId[controller], controller);
    }

    /// @notice Returns an controller's amount of shares fulfilled for deposit.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param controller The address of the controller.
    /// @return The amount of shares that can be minted.
    function maxMint(address controller) public view override returns (uint256) {
        DepositRequestStruct storage depositRequest = _depositRequests[lastDepositRequestId[controller]];
        return _maxMint(
            depositRequest.fulfilledShares, depositRequest.depositAssets[controller], depositRequest.totalDepositAssets
        );
    }

    function _maxMint(
        uint256 fulfilledShares,
        uint256 depositAssets,
        uint256 totalDepositAssets
    )
        internal
        pure
        returns (uint256)
    {
        return totalDepositAssets == 0
            ? 0
            : FixedPointMathLib.fullMulDiv(fulfilledShares, depositAssets, totalDepositAssets);
    }

    // solhint-disable custom-errors,gas-custom-errors,reason-string
    // Preview functions always revert for async flows
    function previewDeposit(uint256) public pure override returns (uint256) {
        revert();
    }

    // Preview functions always revert for async flows
    function previewMint(uint256) public pure override returns (uint256) {
        revert();
    }

    // Preview functions always revert for async flows
    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert();
    }

    // Preview functions always revert for async flows
    function previewRedeem(uint256) public pure override returns (uint256) {
        revert();
    }
    // solhint-enable custom-errors,gas-custom-errors,reason-string

    /// @notice Returns true if the redemption request's fallback has been triggered.
    /// @param requestId The id of the request.
    /// @return True if the fallback has been triggered, false otherwise.
    function fallbackTriggered(uint256 requestId) public view returns (bool) {
        return _redeemRequests[requestId].fallbackTriggered;
    }

    /// @notice Returns the deposit request data for a given requestId without the internal mapping.
    /// @param requestId The id of the deposit request.
    /// @return A DepositRequestView struct containing the deposit request data.
    function getDepositRequest(uint256 requestId) external view returns (DepositRequestView memory) {
        DepositRequestStruct storage depositRequest = _depositRequests[requestId];
        return DepositRequestView({
            totalDepositAssets: depositRequest.totalDepositAssets,
            fulfilledShares: depositRequest.fulfilledShares
        });
    }

    /// @notice Returns the redeem request data for a given requestId without the internal mapping.
    /// @param requestId The id of the redeem request.
    /// @return A RedeemRequestView struct containing the redeem request data.
    function getRedeemRequest(uint256 requestId) external view returns (RedeemRequestView memory) {
        RedeemRequestStruct storage redeemRequest = _redeemRequests[requestId];
        return RedeemRequestView({
            totalRedeemShares: redeemRequest.totalRedeemShares,
            fulfilledAssets: redeemRequest.fulfilledAssets,
            fallbackTriggered: redeemRequest.fallbackTriggered
        });
    }

    //// ERC165 OVERRIDDEN LOGIC ///
    /// @notice Checks if the contract supports the given interface.
    /// @param interfaceID The interface ID.
    /// @return True if the contract supports the interface, false otherwise.
    function supportsInterface(bytes4 interfaceID) public view virtual override returns (bool) {
        return interfaceID == 0x2f0a18c5 || interfaceID == 0xf815c03d
            || interfaceID == type(IERC7540Operator).interfaceId || interfaceID == type(IERC7540Deposit).interfaceId
            || interfaceID == type(IERC7540Redeem).interfaceId || super.supportsInterface(interfaceID);
    }

    /// @dev Override to call the ERC20PluginsUpgradeable's _update function.
    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20PluginsUpgradeable, ERC20Upgradeable)
    {
        ERC20PluginsUpgradeable._update(from, to, amount);
    }

    /// @dev Override to call the ERC20PluginsUpgradeable's balanceOf function.
    /// See {IERC20-balanceOf}.
    function balanceOf(address account)
        public
        view
        override(ERC20PluginsUpgradeable, ERC20Upgradeable, IERC20)
        returns (uint256)
    {
        return ERC20PluginsUpgradeable.balanceOf(account);
    }

    /// @dev Override to return 18 decimals.
    /// See {IERC20Metadata-decimals}.
    function decimals() public pure override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return 18;
    }

    /// @notice External wrapper around Permit2Lib's permit2 function to handle ERC20 permit signatures.
    /// @dev Supports both Permit2 and ERC20Permit (ERC-2612) signatures. Will try ERC-2612 first,
    /// then fall back to Permit2 if the token doesn't support ERC-2612 or if the permit call fails.
    /// @param token The token to permit
    /// @param owner The owner of the tokens
    /// @param spender The spender to approve
    /// @param value The amount to approve
    /// @param deadline The deadline for the permit
    /// @param v The v component of the signature
    /// @param r The r component of the signature
    /// @param s The s component of the signature
    function permit2(
        IERC20 token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        Permit2Lib.permit2(token, owner, spender, value, deadline, v, r, s);
    }
}

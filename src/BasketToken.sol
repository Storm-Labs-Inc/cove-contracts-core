// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerableUpgradeable } from
    "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { IERC7540Deposit, IERC7540Operator, IERC7540Redeem } from "src/interfaces/IERC7540.sol";
import { Errors } from "src/libraries/Errors.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

/// @title BasketToken
/// @notice Contract responsible for accounting for users deposit and redemption requests, which are asynchronously
/// fulfilled by the Basket Manager
// slither-disable-next-line missing-inheritance
contract BasketToken is
    ERC4626Upgradeable,
    AccessControlEnumerableUpgradeable,
    IERC7540Operator,
    IERC7540Deposit,
    IERC7540Redeem
{
    /// LIBRARIES ///
    using SafeERC20 for IERC20;

    // STATE VARS //
    uint256 private _lastManagementFeeHarvestTimestamp;

    /// CONSTANTS ///
    bytes32 private constant _BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    uint16 private constant _MANAGEMENT_FEE_DECIMALS = 1e4;
    uint16 private constant _MAX_MANAGEMENT_FEE = 1e4;

    /// STRUCTS ///
    /// @notice Struct to hold the amount of assets and shares requested by a controller
    struct Requests {
        // Amount of assets requested for deposit
        uint256 depositAssets;
        // Amount of shares requested for redemption
        uint256 redemptionShares;
    }

    /// @notice Struct to hold the amount of assets and shares fulfilled for a given requestId
    struct FulfilledRate {
        // Amount of assets fulfilled for pending redemption requests
        uint256 assets;
        // Amount of shares fulfilled for pending deposit requests
        uint256 shares;
    }

    /// STATE VARIABLES ///
    // slither-disable-start uninitialized-state,constable-states
    /// @notice Mapping of operator to operator status
    mapping(address controller => mapping(address operator => bool)) public isOperator;
    /// @notice Mapping of requestId to a controllers pending assets for deposit and shares for redemption
    mapping(uint256 requestId => mapping(address controller => Requests)) internal _requestIdControllerRequest;
    /// @notice Mapping of requestId to the total amount of assets pending deposit
    mapping(uint256 requestId => uint256 assets) internal _totalPendingAssets;
    /// @notice Mapping of requestId to the total amount of shares pending redemption
    mapping(uint256 requestId => uint256 assets) internal _totalPendingRedemptions;
    /// @notice Mapping of controller to the last requestId of a deposit request
    mapping(address controller => uint256 requestId) public lastDepositRequestId;
    /// @notice Mapping of controller to the last requestId of a redemption request
    mapping(address controller => uint256 requestId) public lastRedeemRequestId;
    /// @notice Mapping of requestId to the rate at which shares can be claimed for deposited assets
    mapping(uint256 requestId => FulfilledRate) internal _fulfilledRate;
    /// @notice Mapping of requestId to a bool indicating if the fallback redeem trigger has been called
    mapping(uint256 requestId => bool fallbackTriggered) public fallbackTriggered;
    /// @notice Latest requestId, initialized as 1
    uint256 internal _currentRequestId;
    /// @notice Address of the admin of the contract, used to set the BasketManager and AssetRegistry
    address public admin;
    /// @notice Address of the BasketManager contract used to fulfill deposit and redemption requests and manage
    /// deposited assets
    address public basketManager;
    /// @notice Address of the AssetRegistry contract used to check if a given asset is paused
    address public assetRegistry;
    /// @notice Bitflag representing the selection of assets
    uint256 public bitFlag;
    /// @notice Strategy ID used by the BasketManager to identify this basket token
    address public strategy;
    // slither-disable-end uninitialized-state,constable-states

    /// EVENTS ///
    /// @notice Emitted when a the Management fee is harvested by the treasury
    event ManagementFeeHarvested(uint256 indexed timestamp, uint256 fee);

    /// ERRORS ///
    error ZeroPendingDeposits();
    error ZeroPendingRedeems();
    error AssetPaused();
    error MustClaimOutstandingDeposit();
    error MustClaimOutstandingRedeem();
    error MustClaimFullAmount();
    error CannotFulfillWithZeroShares();
    error ZeroClaimableFallbackShares();
    error NotAuthorizedOperator();
    error PrepareForRebalanceNotCalled();
    error InvalidManagementFee();

    /// @notice Disables the ability to call initializers.
    constructor() payable {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @param asset_ Address of the asset.
    /// @param name_ Name of the token. All names will be prefixed with "CoveBasket-".
    /// @param symbol_ Symbol of the token. All symbols will be prefixed with "cb".
    /// @param bitFlag_  Bitflag representing the selection of assets.
    /// @param strategy_ Strategy address.
    /// @param admin_ Admin of the contract. Capable of setting the basketManager and AssetRegistry.
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        address strategy_,
        address admin_
    )
        public
        initializer
    {
        if (admin_ == address(0) || strategy_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        admin = admin_;
        basketManager = msg.sender;
        bitFlag = bitFlag_;
        _currentRequestId = 1;
        strategy = strategy_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_BASKET_MANAGER_ROLE, basketManager);
        __ERC4626_init(IERC20(address(asset_)));
        __ERC20_init(string.concat("CoveBasket-", name_), string.concat("covb", symbol_));
    }

    /// @notice Sets the basket manager address. Only callable by the contract admin.
    /// @param basketManager_ The new basket manager address.
    function setBasketManager(address basketManager_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basketManager_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        _revokeRole(_BASKET_MANAGER_ROLE, basketManager);
        basketManager = basketManager_;
        _grantRole(_BASKET_MANAGER_ROLE, basketManager_);
    }

    /// @notice Sets the asset registry address. Only callable by the contract admin.
    /// @param assetRegistry_ The new asset registry address.
    function setAssetRegistry(address assetRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (assetRegistry_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        assetRegistry = assetRegistry_;
    }

    /// @notice Returns the value of the basket in assets. This will be an estimate as it does not account for other
    /// factors that may affect the swap rates.
    /// @return The total value of the basket in assets.
    function totalAssets() public view override returns (uint256) {
        // TODO: Replace this with value of the basket divided by the value of the asset
        return 0;
    }

    /// @notice Returns the current epoch's target weights for this basket.
    /// @return The target weights for the basket.
    function getCurrentTargetWeights() external view returns (uint64[] memory) {
        return getTargetWeights(BasketManager(basketManager).rebalanceStatus().epoch);
    }

    /// @notice Returns the target weights for the given epoch.
    /// @param epoch The epoch to get the target weights for.
    /// @return The target weights for the basket.
    function getTargetWeights(uint40 epoch) public view returns (uint64[] memory) {
        return WeightStrategy(strategy).getTargetWeights(epoch, bitFlag);
    }

    /// ERC7540 LOGIC ///

    /// @notice Transfers assets from owner and submits a request for an asynchronous deposit.
    /// @param assets The amount of assets to deposit.
    /// @param controller The address of the controller of the position being created.
    /// @param owner The address of the owner of the assets being deposited.
    // slither-disable-next-line arbitrary-send-erc20
    function requestDeposit(uint256 assets, address controller, address owner) public returns (uint256 requestId) {
        // Checks
        if (maxDeposit(controller) > 0) {
            revert MustClaimOutstandingDeposit();
        }
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (AssetRegistry(assetRegistry).getAssetStatus(asset()) != AssetRegistry.AssetStatus.ENABLED) {
            revert AssetPaused();
        }
        // Effects
        // @dev if the current requestId is in the process of being fulfilled, a deposit request will be made for the
        // next requestId
        requestId = _currentRequestId;
        // update controllers balance of assets pending deposit
        _requestIdControllerRequest[requestId][controller].depositAssets += assets;
        // update total pending deposits for the current requestId
        _totalPendingAssets[requestId] += assets;
        // update controllers latest deposit request id
        lastDepositRequestId[controller] = requestId;
        emit DepositRequest(controller, owner, requestId, msg.sender, assets);
        // Interactions
        // Assets are immediately transferrred to here to await the basketManager to pull them
        IERC20(asset()).safeTransferFrom(owner, address(this), assets);
    }

    /// @notice Returns the pending deposit request amount for a controller.
    /// @dev If the epoch has been advanced then the request has been fulfilled and is no longer pending.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller of the deposit request.
    /// @return assets The amount of assets pending deposit.
    function pendingDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        assets =
            _fulfilledRate[requestId].shares == 0 ? _requestIdControllerRequest[requestId][controller].depositAssets : 0;
    }

    /// @notice Returns the amount of requested assets in Claimable state for the controller with the given requestId.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller.
    // solhint-disable-next-line no-unused-vars
    function claimableDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        assets =
            _fulfilledRate[requestId].shares == 0 ? 0 : _requestIdControllerRequest[requestId][controller].depositAssets;
    }

    /// @notice Requests a redemption of shares from the basket.
    /// @param shares The amount of shares to redeem.
    /// @param controller The address of the controller of the redeemed shares.
    /// @param owner The address of the request owner.
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        returns (uint256 currentRedeemRequestId)
    {
        // Checks
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        if (maxRedeem(owner) > 0) {
            revert MustClaimOutstandingRedeem();
        }
        if (msg.sender != owner) {
            if (!isOperator[owner][msg.sender]) {
                _spendAllowance(owner, msg.sender, shares);
            }
        }
        if (AssetRegistry(assetRegistry).getAssetStatus(asset()) != AssetRegistry.AssetStatus.ENABLED) {
            revert AssetPaused();
        }
        // Effects
        /// @dev currentRequestId + 1 is reserved for redemptions
        currentRedeemRequestId = _currentRequestId + 1;
        _totalPendingRedemptions[currentRedeemRequestId] += shares;
        lastRedeemRequestId[controller] = currentRedeemRequestId;
        // update controllers balance of assets pending deposit
        _requestIdControllerRequest[currentRedeemRequestId][controller].redemptionShares += shares;
        _transfer(owner, address(this), shares);
        emit RedeemRequest(controller, owner, currentRedeemRequestId, msg.sender, shares);
        return currentRedeemRequestId;
    }

    /// @notice Returns the pending redeem request amount for an operator.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller of the redemption request.
    /// @return shares The amount of shares pending redemption.
    /// TODO: this will be incorrect for requestIds that have triggered a fallback, should be documented or explicitly
    /// checked? (has no implact as cancelRedeemRequest does not allow a requestId to be specified)
    function pendingRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        shares = _fulfilledRate[requestId].assets == 0
            ? _requestIdControllerRequest[requestId][controller].redemptionShares
            : 0;
    }

    /// @notice Returns the amount of requested shares in Claimable state for the controller with the given requestId.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller of the redemption request.
    /// @return shares The amount of shares claimable.
    // solhint-disable-next-line no-unused-vars
    function claimableRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        shares = _fulfilledRate[requestId].assets == 0
            ? 0
            : _requestIdControllerRequest[requestId][controller].redemptionShares;
    }

    /// @notice Fulfills all pending deposit requests. Only callable by the basket manager. Assets are held by the
    /// basket manager. Locks in the rate at which users can claim their shares for deposited assets.
    /// @param shares The amount of shares the deposit was fulfilled with.
    function fulfillDeposit(uint256 shares) public onlyRole(_BASKET_MANAGER_ROLE) {
        // Checks
        /// @dev currentRequestId was advanced by 2 to prepare for rebalance
        uint256 currentRequestId = _currentRequestId - 2;
        uint256 assets = _totalPendingAssets[currentRequestId];
        if (assets == 0) {
            revert ZeroPendingDeposits();
        }
        if (shares == 0) {
            revert CannotFulfillWithZeroShares();
        }
        // Effects
        // Update the shares given to deposits for the current requestId;
        if (_fulfilledRate[currentRequestId].shares == 0) {
            _fulfilledRate[currentRequestId].shares = shares;
        } else {
            revert PrepareForRebalanceNotCalled();
        }
        _mint(address(this), shares);
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, assets);
    }

    /// @notice Called by the basket manager to advance the redeem epoch, preventing any further redeem requests for the
    /// current epoch. Records the total amount of shares pending redemption. This is called at the first step of the
    /// rebalance process regardless of the presence of any pending deposits or redemptions. When there are no pending
    /// deposits or redeems, the epoch is not advanced.
    /// @return sharesPendingRedemption The total amount of shares pending redemption.
    function prepareForRebalance() public onlyRole(_BASKET_MANAGER_ROLE) returns (uint256 sharesPendingRedemption) {
        uint256 currentRequestId = _currentRequestId;
        sharesPendingRedemption = _totalPendingRedemptions[currentRequestId + 1];
        if (_totalPendingAssets[currentRequestId] > 0 || sharesPendingRedemption > 0) {
            /// @notice currentRequestId is incremented by 2 as _currentRequestId + 1 is reserved for redemptions
            _currentRequestId = currentRequestId + 2;
        }
    }

    /// @notice Fulfills all pending redeem requests. Only callable by the basket manager. Burns the shares which are
    /// pending redemption. Locks in the rate at which users can claim their assets for redeemed shares.
    /// @dev prepareForRebalance must be called before this function.
    /// @param assets The amount of assets the redemption was fulfilled with.
    function fulfillRedeem(uint256 assets) public onlyRole(_BASKET_MANAGER_ROLE) {
        uint256 currentRequestId = _currentRequestId - 1;
        if (_fulfilledRate[currentRequestId].assets > 0) {
            revert PrepareForRebalanceNotCalled();
        }
        uint256 sharesPendingRedemption = _totalPendingRedemptions[currentRequestId];
        // Effects
        _fulfilledRate[currentRequestId].assets = assets;
        _burn(address(this), sharesPendingRedemption);
        // Interactions
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(asset()).safeTransferFrom(basketManager, address(this), assets);
    }

    /// @notice Returns the total amount of assets pending deposit.
    /// @return The total pending deposit amount.
    function totalPendingDeposits() public view returns (uint256) {
        return _totalPendingAssets[_currentRequestId];
    }

    /// @notice Returns the total number of shares pending redemption.
    /// @return The total pending redeem amount.
    function totalPendingRedemptions() public view returns (uint256) {
        /// @dev currentRequestId + 1 is reserved for redemptions
        return _totalPendingRedemptions[_currentRequestId + 1];
    }

    /// @notice Cancels a pending deposit request.
    function cancelDepositRequest() public {
        uint256 currentRequestId = _currentRequestId;
        // Checks
        uint256 pendingDeposit = pendingDepositRequest(currentRequestId, msg.sender);
        if (pendingDeposit == 0) {
            revert ZeroPendingDeposits();
        }
        // Effects
        /// @dev since the above check did not return 0, the last deposit request id of the sender will be the current
        // request id
        _requestIdControllerRequest[currentRequestId][msg.sender].depositAssets = 0;
        _totalPendingAssets[currentRequestId] -= pendingDeposit;
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, pendingDeposit);
    }

    /// @notice Cancels a pending redeem request.
    function cancelRedeemRequest() public {
        /// @dev currentRequestId + 1 is reserved for redemptions
        uint256 currentRedeemRequestId = _currentRequestId + 1;
        // Checks
        uint256 pendingRedeem = pendingRedeemRequest(currentRedeemRequestId, msg.sender);
        if (pendingRedeem == 0) {
            revert ZeroPendingRedeems();
        }
        // Effects
        _requestIdControllerRequest[currentRedeemRequestId][msg.sender].redemptionShares = 0;
        _totalPendingRedemptions[currentRedeemRequestId] -= pendingRedeem;
        // Interactions
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

    /// @notice Returns the address of the share token as per ERC-7575.
    /// @return shareTokenAddress The address of the share token.
    /// @dev For non-multi asset vaults this should always return address(this).
    function share() public view returns (address shareTokenAddress) {
        shareTokenAddress = address(this);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice In the event of a failed redemption fulfillment this function is called by the basket manager. Allows
    /// users to claim their shares back for a redemption in the future and advances the redemption epoch.
    function fallbackRedeemTrigger() public onlyRole(_BASKET_MANAGER_ROLE) {
        fallbackTriggered[_currentRequestId - 1] = true;
    }

    /// @notice Claims shares given for a previous redemption request in the event a redemption fulfillment for a
    /// given epoch fails.
    /// @return shares The amount of shares claimed.
    function claimFallbackShares() public returns (uint256 shares) {
        // Effects
        shares = claimableFallbackShares(msg.sender);
        if (shares == 0) {
            revert ZeroClaimableFallbackShares();
        }
        _requestIdControllerRequest[lastRedeemRequestId[msg.sender]][msg.sender].redemptionShares = 0;
        _transfer(address(this), msg.sender, shares);
    }

    /// @notice Returns the amount of shares claimable for a given operator in the event of a failed redemption
    /// fulfillment.
    /// @param operator The address of the operator.
    /// @return shares The amount of shares claimable by the operator.
    function claimableFallbackShares(address operator) public view returns (uint256 shares) {
        uint256 lastRedeemRequestId_ = lastRedeemRequestId[operator];
        if (!fallbackTriggered[lastRedeemRequestId_]) {
            return 0;
        }
        return _requestIdControllerRequest[lastRedeemRequestId_][operator].redemptionShares;
    }

    /// @notice Immediately redeems shares for all assets associated with this basket. This is synchronous and does not
    /// require the rebalance process to be completed.
    /// @param shares Number of shares to redeem.
    /// @param to Address to receive the assets.
    /// @param from Address to redeem shares from.
    function proRataRedeem(uint256 shares, address to, address from) public {
        // Effects
        if (msg.sender != from) {
            _spendAllowance(from, msg.sender, shares);
        }
        uint256 totalSupplyBefore = totalSupply();
        _burn(from, shares);
        // Interactions
        BasketManager(basketManager).proRataRedeem(totalSupplyBefore, shares, to);
    }

    /// @notice Harvests the management fee, records the fee has been taken and mints the fee to the treasury.
    /// @param feeBps The fee denominated in _MANAGEMENT_FEE_DECIMALS to be harvested.
    /// @param feeCollector The address to receive the management fee.
    // slither-disable-next-line timestamp
    function harvestManagementFee(uint16 feeBps, address feeCollector) external onlyRole(_BASKET_MANAGER_ROLE) {
        // Checks
        if (feeBps > _MAX_MANAGEMENT_FEE) {
            revert InvalidManagementFee();
        }
        uint256 timeSinceLastHarvest = block.timestamp - _lastManagementFeeHarvestTimestamp;

        // Effects
        _lastManagementFeeHarvestTimestamp = block.timestamp;
        if (feeBps != 0) {
            if (timeSinceLastHarvest != 0) {
                // remove shares held by the treasury or currently pending redemption from calculation
                uint256 currentTotalSupply =
                    totalSupply() - balanceOf(feeCollector) - pendingRedeemRequest(_currentRequestId - 1, feeCollector);
                uint256 fee = FixedPointMathLib.fullMulDiv(
                    currentTotalSupply, feeBps * timeSinceLastHarvest, _MANAGEMENT_FEE_DECIMALS * uint256(365 days)
                );
                if (fee != 0) {
                    emit ManagementFeeHarvested(block.timestamp, fee);
                    _mint(feeCollector, fee);
                    // Interactions
                    FeeCollector(feeCollector).notifyHarvestFee(fee);
                }
            }
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
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
        if (assets != _requestIdControllerRequest[lastDepositRequestId[controller]][controller].depositAssets) {
            revert MustClaimFullAmount();
        }
        shares = maxMint(controller);
        // Effects
        _claimDeposit(assets, shares, receiver, controller);
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
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
        uint256 claimableShares = maxMint(controller);
        if (shares != claimableShares) {
            revert MustClaimFullAmount();
        }
        // Effects
        assets = _requestIdControllerRequest[lastDepositRequestId[controller]][controller].depositAssets;
        _claimDeposit(assets, shares, receiver, controller);
    }

    /// @notice Transfers a user's shares owed for a previously fulfillled deposit request.
    /// @param shares The amount of shares to receive.
    /// @param receiver The address to receive the shares.
    /// @return assets The amount of assets previously requested for deposit.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        return mint(shares, receiver, msg.sender);
    }

    /// @notice Transfers a user's assets owed for a previously fulfillled redemption request.
    /// @dev Redeem should be used in all instances instead.
    /// @param assets The amount of assets to be claimed.
    /// @param receiver The address to receive the assets.
    /// @param controller The address of the controller of the redeem request.
    /// @return shares The amount of shares previously requested for redemption.
    function withdraw(uint256 assets, address receiver, address controller) public override returns (uint256 shares) {
        // Checks
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
        if (assets != maxWithdraw(controller)) {
            revert MustClaimFullAmount();
        }
        // Effects
        shares = _requestIdControllerRequest[lastRedeemRequestId[controller]][controller].redemptionShares;
        _claimRedemption(assets, shares, receiver, controller);
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
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) revert NotAuthorizedOperator();
        }
        if (shares != _requestIdControllerRequest[lastRedeemRequestId[controller]][controller].redemptionShares) {
            revert MustClaimFullAmount();
        }
        assets = maxWithdraw(controller);
        // Effects
        _claimRedemption(assets, shares, receiver, controller);
    }

    /// @notice Returns an operator's amount of assets fulfilled for redemption.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of assets that can be withdrawn.
    function maxWithdraw(address operator) public view override returns (uint256) {
        uint256 lastRedeemRequestId_ = lastRedeemRequestId[operator];
        uint256 totalPendingRedemptions_ = _totalPendingRedemptions[lastRedeemRequestId_];
        return totalPendingRedemptions_ == 0
            ? 0
            : FixedPointMathLib.fullMulDiv(
                _fulfilledRate[lastRedeemRequestId_].assets,
                _requestIdControllerRequest[lastRedeemRequestId_][operator].redemptionShares,
                totalPendingRedemptions_
            );
    }

    /// @notice Returns an operator's amount of shares fulfilled for redemption.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of shares that can be redeemed.
    function maxRedeem(address operator) public view override returns (uint256) {
        uint256 lastRedeemRequestId_ = lastRedeemRequestId[operator];
        return _fulfilledRate[lastRedeemRequestId_].assets == 0
            ? 0
            : _requestIdControllerRequest[lastRedeemRequestId_][operator].redemptionShares;
    }

    /// @notice Returns an operator's amount of assets fulfilled for deposit.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of assets that can be deposited.
    function maxDeposit(address operator) public view override returns (uint256) {
        uint256 lastDepositRequestID_ = lastDepositRequestId[operator];
        return _fulfilledRate[lastDepositRequestID_].shares == 0
            ? 0
            : _requestIdControllerRequest[lastDepositRequestID_][operator].depositAssets;
    }

    /// @notice Returns an operator's amount of shares fulfilled for deposit.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of shares that can be minted.
    function maxMint(address operator) public view override returns (uint256) {
        uint256 lastDepositRequestID_ = lastDepositRequestId[operator];
        uint256 totalPendingAssets = _totalPendingAssets[lastDepositRequestID_];
        return totalPendingAssets == 0
            ? 0
            : FixedPointMathLib.fullMulDiv(
                _fulfilledRate[lastDepositRequestID_].shares,
                _requestIdControllerRequest[lastDepositRequestID_][operator].depositAssets,
                totalPendingAssets
            );
    }

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

    /// @notice Internal function to claim redemption for a given amount of assets and shares.
    /// @param assets The amount of assets to claim.
    /// @param shares The amount of shares to claim.
    /// @param receiver The address of the receiver of the claimed assets.
    /// @param controller The address of the controller of the redemption request.
    function _claimRedemption(uint256 assets, uint256 shares, address receiver, address controller) internal {
        // Effects
        _requestIdControllerRequest[lastRedeemRequestId[controller]][controller].redemptionShares = 0;
        // Interactions
        emit Withdraw(msg.sender, receiver, controller, assets, shares);
        IERC20(asset()).safeTransfer(receiver, assets);
    }

    /// @notice Internal function to claim deposit for a given amount of assets and shares.
    /// @param assets The amount of assets to claim.
    /// @param shares The amount of shares to claim.
    /// @param receiver The address of the receiver of the claimed assets.
    /// @param controller The address of the controller of the deposit request.

    function _claimDeposit(uint256 assets, uint256 shares, address receiver, address controller) internal {
        // Effects
        _requestIdControllerRequest[lastDepositRequestId[controller]][controller].depositAssets = 0;
        // Interactions
        emit Deposit(controller, receiver, assets, shares);
        _transfer(address(this), receiver, shares);
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
}

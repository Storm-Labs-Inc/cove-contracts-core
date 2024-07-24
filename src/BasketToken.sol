// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerableUpgradeable } from
    "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { AllocationResolver } from "src/allocation/AllocationResolver.sol";
import { Errors } from "src/libraries/Errors.sol";

// TODO: interfaces will be removed in the future
interface IBasketManager {
    function totalAssetValue(address strategyId) external view returns (uint256);
}

/// @title BasketToken
/// @notice Contract responsible for accounting for users deposit and redemption requests, which are asynchronously
/// fulfilled by the Basket Manager
contract BasketToken is ERC4626Upgradeable, AccessControlEnumerableUpgradeable, ERC165 {
    /// LIBRARIES ///
    using SafeERC20 for IERC20;

    /// CONSTANTS ///
    bytes32 private constant _BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes4 private constant _OPERATOR7540_INTERFACE = 0xe3bc4e65;
    bytes4 private constant _ASYNCHRONOUS_DEPOSIT_INTERFACE = 0xce3bbe50;
    bytes4 private constant _ASYNCHRONOUS_REDEMPTION_INTERFACE = 0x620ee8e4;

    /// ENUMS ///
    /// @notice Enum representing the status of a redeem epoch.
    ///   - OPEN: Default status of an epoch.
    ///   - REDEEM_PREFULFILLED: preFulfillRedeem has been called.
    ///   - REDEEM_FULFILLED: fulFillRedeem has been called.
    ///   - FALLBACK_TRIGGERED: A fallback redeem has been triggered.
    enum RedemptionStatus {
        OPEN,
        REDEEM_PREFULFILLED,
        REDEEM_FULFILLED,
        FALLBACK_TRIGGERED
    }

    /// STRUCTS ///
    struct Request {
        uint256 assets;
        uint256 shares;
    }

    /// STATE VARIABLES ///
    /// @notice Mapping of operator to the amount of assets pending deposit
    mapping(address operator => uint256 assets) internal _pendingDeposit;
    /// @notice Mapping of operator to the amount of shares pending redemption
    mapping(address operator => uint256 shares) internal _pendingRedeem;
    /// @notice Mapping of epoch to the rate that deposit requests were fulfilled
    mapping(uint256 epoch => Request depositRequest) internal _epochDepositRequests;
    /// @notice Mapping of epoch to the rate that redemption requests were fulfilled
    mapping(uint256 epoch => Request redeemRequest) internal _epochRedeemRequests;
    /// @notice Mapping of operator to the epoch of the last deposit request
    mapping(address operator => uint256 epoch) internal _lastDepositedEpoch;
    /// @notice Mapping of operator to the epoch of the last redemption request
    mapping(address operator => uint256 epoch) internal _lastRedeemEpoch;
    /// @notice Mapping of epoch to its current status
    mapping(uint256 epoch => RedemptionStatus) internal _epochRedeemStatus;
    /// @notice Mapping of supported interfaces as per ERC165
    /// @dev You must not set element 0xffffffff to true
    mapping(bytes4 => bool) internal _supportedInterfaces;
    /// @notice Mapping of operator to operator status
    mapping(address controller => mapping(address operator => bool)) public isOperator;
    /// @notice Latest deposit epoch, initialized as 1
    uint256 internal _currentDepositEpoch;
    /// @notice Latest redemption epoch, initialized as 1
    uint256 internal _currentRedeemEpoch;
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

    /// EVENTS ///
    /// @notice Emitted when a deposit request is made
    // event DepositRequested(address indexed sender, uint256 indexed epoch, uint256 assets);
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );
    /// @notice Emitted when a redemption request is fulfilled
    event RedeemRequested(
        address indexed sender, uint256 indexed epoch, address operator, address owner, uint256 shares
    );
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /// ERRORS ///
    error ZeroPendingDeposits();
    error ZeroPendingRedeems();
    error AssetPaused();
    error MustClaimOutstandingDeposit();
    error MustClaimOutstandingRedeem();
    error MustClaimFullAmount();
    error PreFulFillRedeemNotCalled();
    error CurrentlyFulfillingRedeem();
    error CannotFulfillWithZeroShares();
    error ZeroClaimableFallbackShares();
    error MustWaitForPreviousRedeemEpoch();
    error NotAuthorizedOperator();

    /// @notice Disables the ability to call initializers.
    constructor() payable {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @param asset_ Address of the asset.
    /// @param name_ Name of the token. All names will be prefixed with "CoveBasket-".
    /// @param symbol_ Symbol of the token. All symbols will be prefixed with "cb".
    /// @param bitFlag_  Bitflag representing the selection of assets.
    /// @param strategyId_ Strategy ID.
    /// @param admin_ Admin of the contract. Capable of setting the basketManager and AssetRegistry.
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        uint256 strategyId_,
        address admin_
    )
        public
        initializer
    {
        if (admin_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        admin = admin_;
        basketManager = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_BASKET_MANAGER_ROLE, basketManager);
        bitFlag = bitFlag_;
        strategy = strategy_;
        _currentRedeemEpoch = 1;
        _currentDepositEpoch = 1;
        _epochRedeemStatus[0] = RedemptionStatus.REDEEM_FULFILLED;
        _supportedInterfaces[_OPERATOR7540_INTERFACE] = true;
        _supportedInterfaces[_ASYNCHRONOUS_DEPOSIT_INTERFACE] = true;
        _supportedInterfaces[_ASYNCHRONOUS_REDEMPTION_INTERFACE] = true;
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
        // Below will not be effected by pending assets
        // TODO: Replace this with value of the basket divided by the value of the asset
        return IBasketManager(basketManager).totalAssetValue(strategy);
    }

    function getTargetWeights() external view returns (uint256[] memory) {
        return AllocationResolver(strategy).getTargetWeights(bitFlag);
    }

    /// @notice Returns the current redemption epoch.
    /// @return The current redemption epoch.
    function currentRedeemEpoch() external view returns (uint256) {
        return _currentRedeemEpoch;
    }

    /// @notice Returns the current deposit epoch.
    /// @return The current deposit epoch.
    function currentDepositEpoch() external view returns (uint256) {
        return _currentDepositEpoch;
    }

    /// @notice Returns the status of a redemption epoch.
    /// @param epoch The epoch to check.
    /// @return The status of the epoch.
    function redemptionStatus(uint256 epoch) public view returns (RedemptionStatus) {
        return _epochRedeemStatus[epoch];
    }

    /// ERC7540 LOGIC ///

    /// @notice Transfers assets from owner and submits a request for an asynchronous deposit.
    /// @param assets The amount of assets to deposit.
    /// @param controller The address of the controller of the position being created.
    /// @param owner The address of the owner of the assets being deposited.
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
        uint256 currentPendingAssets = _pendingDeposit[controller];
        uint256 depositEpoch = _currentDepositEpoch;
        _lastDepositedEpoch[controller] = depositEpoch;
        _pendingDeposit[controller] = (currentPendingAssets + assets);
        Request storage depositRequest = _epochDepositRequests[depositEpoch];
        depositRequest.assets = (depositRequest.assets + assets);
        // TODO implement requestId logic
        requestId = 0;
        // emit DepositRequested(receiver, depositEpoch, assets);
        emit DepositRequest(controller, owner, requestId, msg.sender, assets);
        // Interactions
        // Assets are immediately transferrred to here to await the basketManager to pull them
        IERC20(asset()).safeTransferFrom(owner, address(this), assets);
    }

    /// @notice Returns the pending deposit request amount for an operator.
    /// @dev If the epoch has been advanced then the request has been fulfilled and is no longer pending.
    /// @param requestId The id of the request.
    /// @param operator The address of the operator.
    /// @return assets The amount of assets pending deposit.
    function pendingDepositRequest(uint256 requestId, address operator) public view returns (uint256 assets) {
        // TODO: implement requestId logic
        if (_lastDepositedEpoch[operator] != _currentDepositEpoch) {
            return 0;
        }
        assets = _pendingDeposit[operator];
    }

    // TODO: remove after implementing requestId logic
    function pendingDepositRequest(address operator) public view returns (uint256 assets) {
        assets = pendingDepositRequest(0, operator);
    }

    /// @notice Returns the amount of requested assets in Claimable state for the controller with the given requestId.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller.
    function claimableDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        // TODO: implement requestId logic
        assets = maxDeposit(controller);
    }

    /// @notice Requests a redemption of shares from the basket.
    /// @param shares The amount of shares to redeem.
    /// @param controller The address of the controller of the redeemed shares.
    /// @param owner The address of the request owner.
    function requestRedeem(uint256 shares, address controller, address owner) public returns (uint256 requestId) {
        // Checks
        if (msg.sender != owner) {
            if (!isOperator[owner][msg.sender]) {
                _spendAllowance(owner, msg.sender, shares);
            }
        }

        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        // Checks for the case of a user requesting a redeem before claiming a previous redeem request
        if (maxRedeem(owner) > 0) {
            revert MustClaimOutstandingRedeem();
        }
        if (AssetRegistry(assetRegistry).getAssetStatus(asset()) != AssetRegistry.AssetStatus.ENABLED) {
            revert AssetPaused();
        }
        uint256 redeemEpoch = _currentRedeemEpoch;
        // Checks for the case of a user requesting a redeem after a previous redeem request's epoch has been
        // preFulfilled
        if (_epochRedeemStatus[_lastRedeemEpoch[owner]] == RedemptionStatus.REDEEM_PREFULFILLED) {
            revert CurrentlyFulfillingRedeem();
        }
        // Effects
        uint256 currentPendingRedeem = _pendingRedeem[controller];
        _lastRedeemEpoch[controller] = redeemEpoch;
        _pendingRedeem[controller] = (currentPendingRedeem + shares);
        Request storage redeemRequest = _epochRedeemRequests[redeemEpoch];
        redeemRequest.shares = (redeemRequest.shares + shares);
        // TODO implement requestId logic
        requestId = 0;
        _transfer(owner, address(this), shares);
        emit RedeemRequested(msg.sender, redeemEpoch, owner, controller, shares);
    }

    /// @notice Requests a redemption of shares from the basket for the caller.
    /// @param shares The amount of shares to redeem.
    function requestRedeem(uint256 shares) public {
        requestRedeem(shares, msg.sender, msg.sender);
    }

    /// @notice Returns the pending redeem request amount for an operator.
    /// @dev If the epoch has been advanced then the request has been fulfilled and is no longer pending.
    /// @param requestId The id of the request.
    /// @param operator The address of the operator.
    /// @return shares The amount of shares pending redemption.
    function pendingRedeemRequest(uint256 requestId, address operator) public view returns (uint256 shares) {
        // TODO: implement requestId logic
        if (_lastRedeemEpoch[operator] != _currentRedeemEpoch) {
            return 0;
        }
        shares = _pendingRedeem[operator];
    }

    // TODO: remove when requestId logic is implemented
    function pendingRedeemRequest(address operator) public view returns (uint256 shares) {
        return pendingRedeemRequest(0, operator);
    }

    /// @notice Returns the amount of requested shares in Claimable state for the controller with the given requestId.
    /// @param requestId The id of the request.
    /// @param controller The address of the controller.
    /// @return shares The amount of shares claimable.
    function claimableRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        // TODO: implement requestId logic
        return maxRedeem(controller);
    }

    /// @notice Fulfills all pending deposit requests. Only callable by the basket manager. Assets are held by the
    /// basket manager. Locks in the rate at which users can claim their shares for deposited assets.
    /// @param shares The amount of shares the deposit was fulfilled with.
    function fulfillDeposit(uint256 shares) public onlyRole(_BASKET_MANAGER_ROLE) {
        // Checks
        uint256 depositEpoch = _currentDepositEpoch;
        Request storage depositRequest = _epochDepositRequests[depositEpoch];
        uint256 assets = depositRequest.assets;
        if (assets == 0) {
            revert ZeroPendingDeposits();
        }
        if (shares == 0) {
            revert CannotFulfillWithZeroShares();
        }
        // Effects
        depositRequest.shares = shares;
        _currentDepositEpoch = depositEpoch + 1;
        _mint(address(this), shares);
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, assets);
    }

    /// @notice Called by the basket manager to advance the redeem epoch, preventing any further redeem requests for the
    /// current epoch. Records the total amount of shares pending redemption. This is called at the first step of the
    /// rebalance process. When there are no pending redeems, the epoch is not advanced.
    /// @return The total amount of shares pending redemption.
    function preFulfillRedeem() public onlyRole(_BASKET_MANAGER_ROLE) returns (uint256) {
        uint256 redeemEpoch = _currentRedeemEpoch;
        if (_epochRedeemStatus[redeemEpoch - 1] < RedemptionStatus.REDEEM_FULFILLED) {
            revert MustWaitForPreviousRedeemEpoch();
        }
        Request storage redeemRequest = _epochRedeemRequests[redeemEpoch];
        uint256 currentPendingRedeems = redeemRequest.shares;
        if (currentPendingRedeems == 0) {
            return 0;
        }
        _epochRedeemStatus[redeemEpoch] = RedemptionStatus.REDEEM_PREFULFILLED;
        _currentRedeemEpoch = redeemEpoch + 1;
        return currentPendingRedeems;
    }

    /// @notice Fulfills all pending redeem requests. Only callable by the basket manager. Burns the shares which are
    /// pending redemption. Locks in the rate at which users can claim their assets for redeemed shares.
    /// @dev preFulfillRedeem must be called before this function.
    /// @param assets The amount of assets the redemption was fulfilled with.
    function fulfillRedeem(uint256 assets) public onlyRole(_BASKET_MANAGER_ROLE) {
        uint256 redeemEpoch = _currentRedeemEpoch - 1;
        Request storage redeemRequest = _epochRedeemRequests[redeemEpoch];
        uint256 shares = redeemRequest.shares;
        // The currentRedeemEpoch was incremented in preFulfillRedeem
        if (_epochRedeemStatus[redeemEpoch] != RedemptionStatus.REDEEM_PREFULFILLED) {
            revert PreFulFillRedeemNotCalled();
        }
        // Effects
        _epochRedeemRequests[redeemEpoch] = Request(assets, shares);
        _epochRedeemStatus[redeemEpoch] = RedemptionStatus.REDEEM_FULFILLED;
        _burn(address(this), shares);
        // Interactions
        IERC20(asset()).safeTransferFrom(basketManager, address(this), assets);
    }

    /// @notice Returns the total amount of assets pending deposit.
    /// @return The total pending deposit amount.
    function totalPendingDeposits() public view returns (uint256) {
        Request storage depositRequest = _epochDepositRequests[_currentDepositEpoch];
        return depositRequest.assets;
    }

    /// @notice Returns the total number of shares pending redemption.
    /// @return The total pending redeem amount.
    function totalPendingRedeems() public view returns (uint256) {
        Request storage redeemRequest = _epochRedeemRequests[_currentRedeemEpoch];
        return redeemRequest.shares;
    }

    /// @notice Cancels a pending deposit request.
    function cancelDepositRequest() public {
        // Checks
        uint256 pendingDeposit = pendingDepositRequest(msg.sender);
        if (pendingDeposit == 0) {
            revert ZeroPendingDeposits();
        }
        // Effects
        delete _pendingDeposit[msg.sender];
        Request storage depositRequest = _epochDepositRequests[_lastDepositedEpoch[msg.sender]];
        depositRequest.assets = depositRequest.assets - pendingDeposit;
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, pendingDeposit);
    }

    /// @notice Cancels a pending redeem request.
    function cancelRedeemRequest() public {
        // Checks
        uint256 pendingRedeem = pendingRedeemRequest(msg.sender);
        if (pendingRedeem == 0) {
            revert ZeroPendingRedeems();
        }
        // Effects
        delete _pendingRedeem[msg.sender];
        Request storage redeemRequest = _epochRedeemRequests[_lastRedeemEpoch[msg.sender]];
        redeemRequest.shares = redeemRequest.shares - pendingRedeem;
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
        uint256 previousRedeemEpoch = _currentRedeemEpoch - 1;
        if (_epochRedeemStatus[previousRedeemEpoch] != RedemptionStatus.REDEEM_PREFULFILLED) {
            revert PreFulFillRedeemNotCalled();
        }
        _epochRedeemStatus[previousRedeemEpoch] = RedemptionStatus.FALLBACK_TRIGGERED;
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
        delete _pendingRedeem[msg.sender];
        _transfer(address(this), msg.sender, shares);
    }

    /// @notice Returns the amount of shares claimable for a given operator in the event of a failed redemption
    /// fulfillment.
    /// @param operator The address of the operator.
    /// @return shares The amount of shares claimable by the operator.
    function claimableFallbackShares(address operator) public view returns (uint256 shares) {
        if (_epochRedeemStatus[_lastRedeemEpoch[operator]] != RedemptionStatus.FALLBACK_TRIGGERED) {
            return 0;
        }
        shares = _pendingRedeem[operator];
    }

    /// @notice Immediately redeems shares for all assets associated with this basket. This is synchronous and does not
    /// require the rebalance process to be completed.
    /// @param shares Number of shares to redeem.
    /// @param to Address to receive the assets.
    /// @param from Address to redeem shares from.
    function proRataRedeem(uint256 shares, address to, address from) public {
        // Checks
        // Effects
        if (msg.sender != from) {
            _spendAllowance(from, msg.sender, shares);
        }
        uint256 totalSupplyBefore = totalSupply();
        _burn(from, shares);
        // Interactions
        BasketManager(basketManager).proRataRedeem(totalSupplyBefore, shares, to);
    }

    /// ERC4626 OVERRIDDEN LOGIC ///

    /// @notice Transfers a users shares owed for a previously fulfillled deposit request.
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
        if (assets != maxDeposit(controller)) {
            revert MustClaimFullAmount();
        }
        // Effects
        // maxMint returns shares at the fulfilled rate only if the deposit has been fulfilled
        shares = maxMint(controller);
        _claimDeposit(assets, shares, receiver, controller);
    }

    /// @notice Transfers a users shares owed for a previously fulfilled redeem request.
    /// @param assets The amount of assets to be claimed.
    /// @param receiver The address to receive the assets.
    /// @return shares The amount of shares previously requested for redemption.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        return deposit(assets, receiver, msg.sender);
    }

    /// @notice Transfers a users shares owed for a previously fulfillled deposit request.
    /// @dev Deposit should be used in all instances instead
    /// @param shares The amount of shares to receive.
    /// @param receiver The address to receive the shares.
    /// @param controller The address of the controller of the deposit request.
    /// @return assets The amount of assets previously requested for deposit.
    function mint(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        // Checks
        // maxMint returns shares at the fulfilled rate only if the deposit has been fulfilled
        uint256 claimableShares = maxMint(controller);
        if (claimableShares == 0) {
            revert Errors.ZeroAmount();
        }
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
        if (shares != claimableShares) {
            revert MustClaimFullAmount();
        }
        // Effects
        assets = _pendingDeposit[controller];
        _claimDeposit(assets, shares, receiver, controller);
    }

    /// @notice Transfers a users shares owed for a previously fulfilled deposit request.
    /// @param shares The amount of shares to receive.
    /// @param receiver The address to receive the shares.
    /// @return assets The amount of assets previously requested for deposit.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        return mint(shares, receiver, msg.sender);
    }

    /// @notice Transfers a user shares owed for a previously fulfilled redeem request.
    /// @dev Redeem should be used in all instances instead
    /// @param assets The amount of assets to be claimed.
    /// @param receiver The address to receive the assets.
    /// @param controller The address of the controller of the redeem request.
    /// @return shares The amount of shares previously requested for redemption.
    function withdraw(uint256 assets, address receiver, address controller) public override returns (uint256 shares) {
        // Checks
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (msg.sender != controller) {
            if (!isOperator[controller][msg.sender]) {
                revert NotAuthorizedOperator();
            }
        }
        if (assets != maxWithdraw(controller)) {
            revert MustClaimFullAmount();
        }
        // Effects
        shares = _pendingRedeem[controller];
        _claimRedemption(assets, shares, receiver, controller);
    }

    /// @notice Transfers the receiver shares owed for a previously fulfilled redeem request.
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
        if (shares != maxRedeem(controller)) {
            revert MustClaimFullAmount();
        }
        // Effects
        assets = maxWithdraw(controller);
        _claimRedemption(assets, shares, receiver, controller);
    }

    /// @notice Returns an operator's amount of assets fulfilled for redemption.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of assets that can be withdrawn.
    function maxWithdraw(address operator) public view override returns (uint256) {
        Request storage redeemRequest = _epochRedeemRequests[_lastRedeemEpoch[operator]];
        uint256 totalShares = redeemRequest.shares;
        return totalShares == 0
            ? 0
            : FixedPointMathLib.fullMulDiv(redeemRequest.assets, _pendingRedeem[operator], totalShares);
    }

    /// @notice Returns an operator's amount of shares fulfilled for redemption.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of shares that can be redeemed.
    function maxRedeem(address operator) public view override returns (uint256) {
        Request storage redeemRequest = _epochRedeemRequests[_lastRedeemEpoch[operator]];
        return redeemRequest.assets == 0 ? 0 : _pendingRedeem[operator];
    }

    /// @notice Returns an operator's amount of assets fulfilled for deposit.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of assets that can be deposited.
    function maxDeposit(address operator) public view override returns (uint256) {
        Request storage depositRequest = _epochDepositRequests[_lastDepositedEpoch[operator]];
        return depositRequest.shares == 0 ? 0 : _pendingDeposit[operator];
    }

    /// @notice Returns an operator's amount of shares fulfilled for deposit.
    /// @dev For requests yet to be fulfilled, this will return 0.
    /// @param operator The address of the operator.
    /// @return The amount of shares that can be minted.
    function maxMint(address operator) public view override returns (uint256) {
        Request storage depositRequest = _epochDepositRequests[_lastDepositedEpoch[operator]];
        uint256 assets = depositRequest.assets;
        return assets == 0 ? 0 : FixedPointMathLib.fullMulDiv(depositRequest.shares, _pendingDeposit[operator], assets);
    }

    // Preview functions always revert for async flows
    function previewDeposit(uint256) public pure override returns (uint256) {
        revert();
    }

    // Preview functions always revert for async flows
    function previewMint(uint256) public pure override returns (uint256) {
        revert();
    }

    /// @notice Internal function to claim redemption for a given amount of assets and shares.
    /// @param assets The amount of assets to claim.
    /// @param shares The amount of shares to claim.
    /// @param receiver The address of the receiver of the claimed assets.
    /// @param controller The address of the controller of the redemption request.
    function _claimRedemption(uint256 assets, uint256 shares, address receiver, address controller) internal {
        // Effects
        delete _pendingRedeem[controller];
        // Interactions
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /// @notice Internal function to claim deposit for a given amount of assets and shares.
    /// @param assets The amount of assets to claim.
    /// @param shares The amount of shares to claim.
    /// @param receiver The address of the receiver of the claimed assets.
    /// @param controller The address of the controller of the deposit request.

    function _claimDeposit(uint256 assets, uint256 shares, address receiver, address controller) internal {
        // Effects
        delete _pendingDeposit[controller];
        // Interactions
        _transfer(address(this), receiver, shares);
        emit Deposit(controller, receiver, assets, shares);
    }

    //// ERC165 OVERRIDDEN LOGIC ///
    /// @notice Checks if the contract supports the given interface.
    /// @param interfaceID The interface ID.
    /// @return True if the contract supports the interface, false otherwise.
    function supportsInterface(bytes4 interfaceID)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, ERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceID) || _supportedInterfaces[interfaceID];
    }
}

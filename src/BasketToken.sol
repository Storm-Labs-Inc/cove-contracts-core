// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerableUpgradeable } from
    "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasketManager } from "src/BasketManager.sol";
import { Errors } from "src/libraries/Errors.sol";

// TODO: interfaces will be removed in the future
interface IBasketManager {
    function totalAssetValue(uint256 strategyId) external view returns (uint256);
}

interface IAssetRegistry {
    function isPaused(address asset) external view returns (bool);
}

/**
 * @title BasketToken
 * @notice Contract responsible for accounting for users deposit and redemption requests, which are asynchronously
 * fulfilled by the Basket Manager
 */
contract BasketToken is ERC4626Upgradeable, AccessControlEnumerableUpgradeable {
    /**
     * Libraries
     */
    using SafeERC20 for IERC20;

    /**
     * Constants
     */
    bytes32 public constant BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    uint256 public constant DECIMAL_BUFFER = 1e18;

    /**
     * Structs
     */
    /**
     * @notice Enum representing the status of a redeem epoch.
     *   - OPEN: Default status of an epoch.
     *   - REDEEM_PREFULFILLED: preFulfillRedeem has been called.
     *   - REDEEM_FULFILLED: fulFillRedeem has been called.
     *   - FALLBACK_TRIGGERED: A fallback redeem has been triggered.
     */
    enum RedemptionStatus {
        OPEN,
        REDEEM_PREFULFILLED,
        REDEEM_FULFILLED,
        FALLBACK_TRIGGERED
    }

    /**
     * State variables
     */
    /// @notice Mapping of operator to the amount of assets pending deposit
    mapping(address operator => uint256 assets) internal _pendingDeposit;
    /// @notice Mapping of operator to the amount of shares pending redemption
    mapping(address operator => uint256 shares) internal _pendingRedeem;
    /// @notice Mapping of epoch to the rate that deposit requests were fulfilled
    mapping(uint256 epoch => uint256 rate) internal _epochDepositRate;
    /// @notice Mapping of epoch to the rate that redemption requests were fulfilled
    mapping(uint256 epoch => uint256 rate) internal _epochRedeemRate;
    /// @notice Mapping of operator to the epoch of the last deposit request
    mapping(address operator => uint256 epoch) internal _lastDepositedEpoch;
    /// @notice Mapping of operator to the epoch of the last redemption request
    mapping(address operator => uint256 epoch) internal _lastRedeemEpoch;
    /// @notice Mapping of epoch to its current status
    mapping(uint256 epoch => RedemptionStatus) internal _epochStatus;
    /// @notice Total amount of assets pending deposit
    uint256 internal _totalPendingDeposits;
    /// @notice Total amount of shares pending redemption
    uint256 internal _totalPendingRedeems;
    /// @notice Latest deposit epoch, initialized as 1
    uint256 internal _currentDepositEpoch;
    /// @notice Latest redemption epoch, initialized as 1
    uint256 internal _currentRedeemEpoch;
    /// @notice Amount of shares pending redemption for the current epoch
    uint256 internal _currentRedeemEpochAmount;
    /// @notice Address of the owner of the contract, used to set the BasketManager and AssetRegistry
    address public owner;
    /// @notice Address of the BasketManager contract used to fulfill deposit and redemption requests and manage
    /// deposited assets
    address public basketManager;
    /// @notice Address of the AssetRegistry contract used to check if a given asset is paused
    address public assetRegistry;
    /// @notice Bitflag representing the selection of assets
    uint256 public bitFlag;
    /// @notice Strategy ID used by the BasketManager to identify this basket token
    uint256 public strategyId;

    /**
     * Events
     */
    /// @notice Emitted when a deposit request is made
    event DepositRequested(address indexed sender, uint256 indexed epoch, uint256 assets);
    /// @notice Emitted when a redemption request is fulfilled
    event RedeemRequested(
        address indexed sender, uint256 indexed epoch, address operator, address owner, uint256 shares
    );

    /**
     * Errors
     */
    error ZeroPendingDeposits();
    error ZeroPendingRedeems();
    error AssetPaused();
    error NotOwner();
    error MustClaimOutstandingDeposit();
    error MustClaimOutstandingRedeem();
    error MustClaimFullAmount();
    error NotBasketManager();
    error PreFulFillRedeemNotCalled();
    error EpochFallbackNotTriggered();
    error CurrentlyFulfillingRedeem();

    /**
     * @notice Disables the ability to call initializers.
     */
    constructor() payable {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param asset_ Address of the asset.
     * @param name_ Name of the token. All names will be prefixed with "CoveBasket-".
     * @param symbol_ Symbol of the token. All symbols will be prefixed with "cb".
     * @param bitFlag_  Bitflag representing the selection of assets.
     * @param strategyId_ Strategy ID.
     * @param owner_ Owner of the contract. Capable of setting the basketManager and AssetRegistry.
     */
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        uint256 strategyId_,
        address owner_
    )
        public
        initializer
    {
        if (owner_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        owner = owner_;
        basketManager = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(BASKET_MANAGER_ROLE, basketManager);
        bitFlag = bitFlag_;
        strategyId = strategyId_;
        _currentRedeemEpoch = 1;
        _currentDepositEpoch = 1;
        __ERC4626_init(IERC20(address(asset_)));
        __ERC20_init(string.concat("CoveBasket-", name_), string.concat("covb", symbol_));
    }

    /**
     * @notice Sets the basket manager address. Only callable by the contract owner.
     * @param basketManager_ The new basket manager address.
     */
    function setBasketManager(address basketManager_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basketManager_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        _revokeRole(BASKET_MANAGER_ROLE, basketManager);
        basketManager = basketManager_;
        _grantRole(BASKET_MANAGER_ROLE, basketManager_);
    }

    /**
     * @notice Sets the asset registry address. Only callable by the contract owner.
     * @param assetRegistry_ The new asset registry address.
     */
    function setAssetRegistry(address assetRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (assetRegistry_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        assetRegistry = assetRegistry_;
    }

    /**
     * @notice Returns the total asset value of the basket reported by the BasketManager.
     * @return The total asset value.
     */
    function totalAssets() public view override returns (uint256) {
        // Below will not be effected by pending assets
        return IBasketManager(basketManager).totalAssetValue(strategyId);
    }

    /**
     * @notice Returns the current redemption epoch.
     * @return The current redemption epoch.
     */
    function currentRedeemEpoch() external view returns (uint256) {
        return _currentRedeemEpoch;
    }

    /**
     * @notice Returns the current deposit epoch.
     * @return The current deposit epoch.
     */
    function currentDepositEpoch() external view returns (uint256) {
        return _currentDepositEpoch;
    }

    /**
     * @notice Returns the status of a redemption epoch.
     * @param epoch The epoch to check.
     * @return The status of the epoch.
     */
    function redemptionStatus(uint256 epoch) public view returns (RedemptionStatus) {
        return _epochStatus[epoch];
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Requests a deposit of assets to the basket.
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the shares.
     */
    function requestDeposit(uint256 assets, address receiver) public {
        // Checks
        if (maxDeposit(receiver) > 0) {
            revert MustClaimOutstandingDeposit();
        }
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (IAssetRegistry(assetRegistry).isPaused(asset())) {
            revert AssetPaused();
        }
        // Effects
        uint256 currentPendingAssets = _pendingDeposit[receiver];
        uint256 depositEpoch = _currentDepositEpoch;
        _lastDepositedEpoch[receiver] = depositEpoch;
        _pendingDeposit[receiver] = (currentPendingAssets + assets);
        _totalPendingDeposits = _totalPendingDeposits + assets;
        emit DepositRequested(receiver, depositEpoch, assets);
        // Interactions
        // Assets are immediately transferrred to here to await the basketManager to pull them
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
    }

    /**
     * @notice Requests a deposit of assets to the basket for the caller.
     * @param assets The amount of assets to deposit.
     */
    function requestDeposit(uint256 assets) public {
        requestDeposit(assets, msg.sender);
    }

    /**
     * @notice Returns the pending deposit request amount for an operator.
     * @dev If the epoch has been advanced then the request has been fulfilled and is no longer pending.
     * @param operator The address of the operator.
     * @return assets The amount of assets pending deposit.
     */
    function pendingDepositRequest(address operator) public view returns (uint256 assets) {
        if (_lastDepositedEpoch[operator] != _currentDepositEpoch) {
            return 0;
        }
        assets = _pendingDeposit[operator];
    }

    /**
     * @notice Requests a redemption of shares from the basket.
     * @param shares The amount of shares to redeem.
     * @param operator The address of the operator.
     * @param requestOwner The address of the request owner.
     */
    function requestRedeem(uint256 shares, address operator, address requestOwner) public {
        // Checks
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        // Checks for the case of a user requesting a redeem before claiming a previous redeem request
        if (maxRedeem(requestOwner) > 0) {
            revert MustClaimOutstandingRedeem();
        }
        if (IAssetRegistry(assetRegistry).isPaused(asset())) {
            revert AssetPaused();
        }
        uint256 redeemEpoch = _currentRedeemEpoch;
        // Checks for the case of a user requesting a redeem after a previous redeem request's epoch has been
        // preFulfilled
        if (_epochStatus[_lastRedeemEpoch[requestOwner]] == RedemptionStatus.REDEEM_PREFULFILLED) {
            revert CurrentlyFulfillingRedeem();
        }
        // Effects
        if (msg.sender != requestOwner) {
            _spendAllowance(requestOwner, msg.sender, shares);
        }
        uint256 currentPendingRedeem = _pendingRedeem[operator];
        _lastRedeemEpoch[operator] = redeemEpoch;
        _pendingRedeem[operator] = (currentPendingRedeem + shares);
        _totalPendingRedeems = _totalPendingRedeems + shares;
        _transfer(requestOwner, address(this), shares);
        emit RedeemRequested(msg.sender, redeemEpoch, operator, requestOwner, shares);
    }

    /**
     * @notice Requests a redemption of shares from the basket for the caller.
     * @param shares The amount of shares to redeem.
     */
    function requestRedeem(uint256 shares) public {
        requestRedeem(shares, msg.sender, msg.sender);
    }

    /**
     * @notice Returns the pending redeem request amount for an operator.
     * @dev If the epoch has been advanced then the request has been fulfilled and is no longer pending.
     * @param operator The address of the operator.
     * @return shares The amount of shares pending redemption.
     */
    function pendingRedeemRequest(address operator) public view returns (uint256 shares) {
        if (_lastRedeemEpoch[operator] != _currentRedeemEpoch) {
            return 0;
        }
        shares = _pendingRedeem[operator];
    }

    /**
     * @notice Fulfills all pending deposit requests. Only callable by the basket manager. Assets are held by the basket
     * manager. Locks in the rate at which users can claim their shares for deposited assets.
     * @param shares The amount of shares the deposit was fulfilled with.
     */
    function fulfillDeposit(uint256 shares) public onlyRole(BASKET_MANAGER_ROLE) {
        // Checks
        if (_totalPendingDeposits == 0) {
            revert ZeroPendingDeposits();
        }
        // Effects
        uint256 assets = _totalPendingDeposits;
        uint256 rate = assets * DECIMAL_BUFFER / shares;
        uint256 depositEpoch = _currentDepositEpoch;
        _epochDepositRate[depositEpoch] = rate;
        _currentDepositEpoch = depositEpoch + 1;
        _totalPendingDeposits = 0;
        _mint(address(this), shares);
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, assets);
    }

    /**
     * @notice Called by the basket manager to advance the redeem epoch, preventing any further redeem requests for the
     * current epoch. Records the total amount of shares pending redemption. This is called at the first step of the
     * rebalance process. When there are no pending redeems, the epoch is not advanced.
     */
    function preFulfillRedeem() public onlyRole(BASKET_MANAGER_ROLE) returns (uint256) {
        uint256 currentPendingRedeems = _totalPendingRedeems;
        uint256 redeemEpoch = _currentRedeemEpoch;
        if (currentPendingRedeems == 0) {
            return 0;
        }
        _epochStatus[redeemEpoch] = RedemptionStatus.REDEEM_PREFULFILLED;
        _currentRedeemEpoch = redeemEpoch + 1;
        _currentRedeemEpochAmount = currentPendingRedeems;
        _totalPendingRedeems = 0;
        return currentPendingRedeems;
    }

    /**
     * @notice Fulfills all pending redeem requests. Only callable by the basket manager. Burns the shares which are
     * pending redemption. Locks in the rate at which users can claim their assets for redeemed shares.
     * @dev preFulfillRedeem must be called before this function.
     * @param assets The amount of assets the redemption was fulfilled with.
     */
    function fulfillRedeem(uint256 assets) public onlyRole(BASKET_MANAGER_ROLE) {
        uint256 currentRedeemEpochAmount = _currentRedeemEpochAmount;
        uint256 redeemEpoch = _currentRedeemEpoch - 1;
        if (_epochStatus[redeemEpoch] != RedemptionStatus.REDEEM_PREFULFILLED) {
            revert PreFulFillRedeemNotCalled();
        }
        // Effects
        uint256 shares = currentRedeemEpochAmount;
        uint256 rate = assets * DECIMAL_BUFFER / shares;
        // The currentRedeemEpoch was incremented in preFulfillRedeem
        _epochRedeemRate[redeemEpoch] = rate;
        _currentRedeemEpochAmount = 0;
        _epochStatus[redeemEpoch] = RedemptionStatus.REDEEM_FULFILLED;
        _burn(address(this), shares);
        // Interactions
        IERC20(asset()).safeTransferFrom(basketManager, address(this), assets);
    }

    /**
     * @notice Returns the total amount of assets pending deposit.
     * @return The total pending deposit amount.
     */
    function totalPendingDeposits() public view returns (uint256) {
        return _totalPendingDeposits;
    }

    /**
     * @notice Returns the total number of shares pending redemption.
     * @return The total pending redeem amount.
     */
    function totalPendingRedeems() public view returns (uint256) {
        return _totalPendingRedeems;
    }

    /**
     * @notice Cancels a pending deposit request.
     */
    function cancelDepositRequest() public {
        // Checks
        uint256 pendingDeposit = pendingDepositRequest(msg.sender);
        if (pendingDeposit == 0) {
            revert ZeroPendingDeposits();
        }
        // Effects
        delete _pendingDeposit[msg.sender];
        _totalPendingDeposits = _totalPendingDeposits - pendingDeposit;
        // Interactions
        IERC20(asset()).safeTransfer(msg.sender, pendingDeposit);
    }

    /**
     * @notice Cancels a pending redeem request.
     */
    function cancelRedeemRequest() public {
        // Checks
        uint256 pendingRedeem = pendingRedeemRequest(msg.sender);
        if (pendingRedeem == 0) {
            revert ZeroPendingRedeems();
        }
        // Effects
        delete _pendingRedeem[msg.sender];
        _totalPendingRedeems = _totalPendingRedeems - pendingRedeem;
        _transfer(address(this), msg.sender, pendingRedeem);
    }

    /*//////////////////////////////////////////////////////////////
                        FALLBACK REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice In the event of a failed redemption fulfillment this function is called by the basket manager. Allows
     * users to claim their shares back for a redemption in the future and advances the redemption epoch.
     */
    function fallbackRedeemTrigger() public onlyRole(BASKET_MANAGER_ROLE) {
        uint256 previousRedeemEpoch = _currentRedeemEpoch - 1;
        if (_epochStatus[previousRedeemEpoch] != RedemptionStatus.REDEEM_PREFULFILLED) {
            revert PreFulFillRedeemNotCalled();
        }
        // Setting the rate to 0 disallow normal redemption
        _epochRedeemRate[previousRedeemEpoch] = 0;
        _currentRedeemEpochAmount = 0;
        _epochStatus[previousRedeemEpoch] = RedemptionStatus.FALLBACK_TRIGGERED;
    }

    /**
     * @notice Retrieve shares given for a previous redemption request in the event a redemption fulfillment for a
     * given epoch fails.
     */
    function fallbackCancelRedeemRequest() public {
        // Checks
        if (_epochStatus[_currentRedeemEpoch - 1] != RedemptionStatus.FALLBACK_TRIGGERED) {
            revert EpochFallbackNotTriggered();
        }
        // Effects
        uint256 pendingRedeem = _pendingRedeem[msg.sender];
        delete _pendingRedeem[msg.sender];
        _transfer(address(this), msg.sender, pendingRedeem);
    }

    function fallbackRedeem(uint256 shares, address to, address from) public {
        // Checks
        // Effects
        if (msg.sender != from) {
            _spendAllowance(from, msg.sender, shares);
        }
        uint256 totalSupplyBefore = totalSupply();
        _burn(from, shares);
        // Interactions
        BasketManager(basketManager).fallbackRedeem(totalSupplyBefore, shares, to);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfers a users shares owed for a previously fulfillled deposit request.
     * @param assets The amount of assets previously requested for deposit.
     * @param receiver The address to receive the shares.
     * @return shares The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // Checks
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (assets != maxDeposit(msg.sender)) {
            revert MustClaimFullAmount();
        }
        // Effects
        // maxMint returns shares at the fulfilled rate only if the deposit has been fulfilled
        shares = maxMint(msg.sender);
        delete _pendingDeposit[msg.sender];
        _transfer(address(this), receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Transfers a users shares owed for a previously fulfillled deposit request.
     * @dev Deposit should be used in all instances instead
     * @param shares The amount of shares to receive.
     * @param receiver The address to receive the shares.
     * @return assets The amount of assets previously requested for deposit.
     */
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // Checks
        // maxMint returns shares at the fulfilled rate only if the deposit has been fulfilled
        uint256 claimableShares = maxMint(msg.sender);
        if (claimableShares == 0) {
            revert Errors.ZeroAmount();
        }
        if (shares != claimableShares) {
            revert MustClaimFullAmount();
        }
        // Effects
        assets = _pendingDeposit[msg.sender];
        delete _pendingDeposit[msg.sender];
        _transfer(address(this), receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Transfers a user shares owed for a previously fulfilled redeem request.
     * @dev Redeem should be used in all instances instead
     * @param assets The amount of assets to be claimed.
     * @param receiver The address to receive the assets.
     * @return shares The amount of shares previously requested for redemption.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address /*operator*/
    )
        public
        override
        returns (uint256 shares)
    {
        // Checks
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (assets != maxWithdraw(msg.sender)) {
            revert MustClaimFullAmount();
        }
        // Effects
        emit Withdraw(msg.sender, receiver, msg.sender, assets, _pendingRedeem[msg.sender]);
        delete _pendingRedeem[msg.sender];
        // Interactions
        IERC20(asset()).safeTransfer(receiver, assets);
    }

    /**
     * @notice Transfers the receiver shares owed for a previously fulfilled redeem request.
     * @param shares The amount of shares to be claimed.
     * @param receiver The address to receive the assets.
     * @return assets The amount of assets previously requested for redemption.
     */
    function redeem(uint256 shares, address receiver, address /*operator*/ ) public override returns (uint256 assets) {
        // Checks
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        if (shares != maxRedeem(msg.sender)) {
            revert MustClaimFullAmount();
        }
        // Effects
        assets = maxWithdraw(msg.sender);
        delete _pendingRedeem[msg.sender];
        // Interactions
        // slither-disable-next-line reentrancy-events
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
    }

    /**
     * @notice Returns an operator's amount of assets fulfilled for redemption.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of assets that can be withdrawn.
     */
    function maxWithdraw(address operator) public view override returns (uint256) {
        uint256 rate = _epochRedeemRate[_lastRedeemEpoch[operator]];
        return rate == 0 ? 0 : _pendingRedeem[operator] * rate / DECIMAL_BUFFER;
    }

    /**
     * @notice Returns an operator's amount of shares fulfilled for redemption.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of shares that can be redeemed.
     */
    function maxRedeem(address operator) public view override returns (uint256) {
        return _epochRedeemRate[_lastRedeemEpoch[operator]] == 0 ? 0 : _pendingRedeem[operator];
    }

    /**
     * @notice Returns an operator's amount of assets fulfilled for deposit.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of assets that can be deposited.
     */
    function maxDeposit(address operator) public view override returns (uint256) {
        return _epochDepositRate[_lastDepositedEpoch[operator]] == 0 ? 0 : _pendingDeposit[operator];
    }

    /**
     * @notice Returns an operator's amount of shares fulfilled for deposit.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of shares that can be minted.
     */
    function maxMint(address operator) public view override returns (uint256) {
        uint256 rate = _epochDepositRate[_lastDepositedEpoch[operator]];
        return rate == 0 ? 0 : _pendingDeposit[operator] * DECIMAL_BUFFER / rate;
    }

    // Preview functions always revert for async flows
    function previewDeposit(uint256) public pure override returns (uint256) {
        revert();
    }

    // Preview functions always revert for async flows
    function previewMint(uint256) public pure override returns (uint256) {
        revert();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessControlEnumerableUpgradeable } from
    "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    /// @notice Total amount of assets pending deposit
    uint256 internal _totalPendingDeposits;
    /// @notice Total amount of shares pending redemption
    uint256 internal _totalPendingRedeems;
    /// @notice Latest deposit epoch
    uint256 _currentDepositEpoch;
    /// @notice Latest redemption epoch
    uint256 _currentRedeemEpoch;
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
     * @notice Disables the ability to call initializers.
     */
    constructor() {
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
        owner = owner_;
        basketManager = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(BASKET_MANAGER_ROLE, basketManager);
        bitFlag = bitFlag_;
        strategyId = strategyId_;
        __ERC4626_init(IERC20(address(asset_)));
        __ERC20_init(string.concat("CoveBasket-", name_), string.concat("covb", symbol_));
    }

    /**
     * @notice Sets the basket manager address. Only callable by the contract owner.
     * @param _basketManager The new basket manager address.
     */
    function setBasketManager(address _basketManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BASKET_MANAGER_ROLE, basketManager);
        basketManager = _basketManager;
        _grantRole(BASKET_MANAGER_ROLE, _basketManager);
    }

    /**
     * @notice Sets the asset registry address. Only callable by the contract owner.
     * @param _assetRegistry The new asset registry address.
     */
    function setAssetRegistry(address _assetRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        assetRegistry = _assetRegistry;
    }

    /**
     * @notice Returns the total asset value of the basket reported by the BasketManager.
     * @return The total asset value.
     */
    function totalAssets() public view override returns (uint256) {
        // Below will not be effected by pending assets
        return IBasketManager(basketManager).totalAssetValue(strategyId);
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
            revert Errors.MustClaimOutstandingDeposit();
        }
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (IAssetRegistry(assetRegistry).isPaused(asset())) {
            revert Errors.AssetPaused();
        }
        // Effects
        uint256 currentPendingAssets = _pendingDeposit[receiver];
        _lastDepositedEpoch[receiver] = _currentDepositEpoch;
        _pendingDeposit[receiver] = (currentPendingAssets + assets);
        _totalPendingDeposits += assets;
        emit DepositRequested(receiver, _currentDepositEpoch, assets);
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
     * @dev If the deposit rate for the last pending deposit request is 0, the request has been fulfilled and is no
     * longer pending, and this function will return 0.
     * @param operator The address of the operator.
     * @return assets The pending deposit amount.
     */
    function pendingDepositRequest(address operator) public view returns (uint256 assets) {
        if (_epochDepositRate[_lastDepositedEpoch[operator]] != 0) {
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
        if (maxRedeem(requestOwner) > 0) {
            revert Errors.MustClaimOutstandingRedeem();
        }
        if (IAssetRegistry(assetRegistry).isPaused(asset())) {
            revert Errors.AssetPaused();
        }
        if (msg.sender != requestOwner) {
            _spendAllowance(requestOwner, msg.sender, shares);
        }
        // Effects
        uint256 currentPendingWithdraw = _pendingRedeem[operator];
        _lastRedeemEpoch[operator] = _currentRedeemEpoch;
        _pendingRedeem[operator] = (currentPendingWithdraw + shares);
        _totalPendingRedeems += shares;
        // Interactions
        _transfer(requestOwner, address(this), shares);
        emit RedeemRequested(msg.sender, _currentRedeemEpoch, operator, requestOwner, shares);
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
     * @dev If the redeem rate for the last pending redeem request is 0, the request has been fulfilled and is no longer
     * pending, and this function will return 0.
     * @param operator The address of the operator.
     * @return shares The pending redeem share amount.
     */
    function pendingRedeemRequest(address operator) public view returns (uint256 shares) {
        if (_epochRedeemRate[_lastRedeemEpoch[operator]] != 0) {
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
        if (_totalPendingDeposits == 0) {
            revert Errors.ZeroPendingDeposits();
        }
        uint256 assets = _totalPendingDeposits;
        _mint(address(this), shares);
        uint256 rate = assets * DECIMAL_BUFFER / shares;
        _epochDepositRate[_currentDepositEpoch] = rate;
        _currentDepositEpoch += 1;
        _totalPendingDeposits = 0;
        IERC20(asset()).safeTransfer(msg.sender, assets);
    }

    /**
     * @notice Fulfills all pending redeem requests. Only callable by the basket manager. Burns the shares which are
     * pending redemption. Locks in the rate at which users can claim their assets for redeemed shares.
     * @param assets The amount of assets the redemption was fulfilled with.
     */
    function fulfillRedeem(uint256 assets) public onlyRole(BASKET_MANAGER_ROLE) {
        if (_totalPendingRedeems == 0) {
            revert Errors.ZeroPendingRedeems();
        }
        uint256 shares = _totalPendingRedeems;
        _burn(address(this), shares);
        uint256 rate = assets * DECIMAL_BUFFER / shares;
        _epochRedeemRate[_currentRedeemEpoch] = rate;
        _currentRedeemEpoch += 1;
        _totalPendingRedeems = 0;
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
            revert Errors.ZeroPendingDeposits();
        }
        // Effects
        delete _pendingDeposit[msg.sender];
        _totalPendingDeposits -= pendingDeposit;
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
            revert Errors.ZeroPendingRedeems();
        }
        // Effects
        delete _pendingRedeem[msg.sender];
        _totalPendingRedeems -= pendingRedeem;
        // Interactions
        _transfer(address(this), msg.sender, pendingRedeem);
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
            revert Errors.MustClaimFullAmount();
        }
        // Effects
        // maxMint returns shares at the fulfilled rate only if the deposit has been filfilled
        shares = maxMint(msg.sender);
        delete _pendingDeposit[msg.sender];
        // Interactions
        // TODO: does not work with public transfer(), errors on `transfer amount exceeds balance`
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
        // maxMint returns shares at the fulfilled rate only if the deposit has been filfilled
        uint256 claimableShares = maxMint(msg.sender);
        if (claimableShares == 0) {
            revert Errors.ZeroAmount();
        }
        if (shares != claimableShares) {
            revert Errors.MustClaimFullAmount();
        }
        // Effects
        assets = _pendingDeposit[msg.sender];
        delete _pendingDeposit[msg.sender];
        // Interactions
        // TODO does not work with public transfer(), errors on `transfer amount exceeds balance`
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
            revert Errors.MustClaimFullAmount();
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
            revert Errors.MustClaimFullAmount();
        }
        // Effects
        assets = maxWithdraw(msg.sender);
        delete _pendingRedeem[msg.sender];
        // Interactions
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
        uint256 epoch = _lastRedeemEpoch[operator];
        uint256 rate = _epochRedeemRate[epoch];
        return rate == 0 ? 0 : _pendingRedeem[operator] * rate / DECIMAL_BUFFER;
    }

    /**
     * @notice Returns an operator's amount of shares fulfilled for redemption.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of shares that can be redeemed.
     */
    function maxRedeem(address operator) public view override returns (uint256) {
        uint256 epoch = _lastRedeemEpoch[operator];
        uint256 rate = _epochRedeemRate[epoch];
        return rate == 0 ? 0 : _pendingRedeem[operator];
    }

    /**
     * @notice Returns an operator's amount of assets fulfilled for deposit.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of assets that can be deposited.
     */
    function maxDeposit(address operator) public view override returns (uint256) {
        uint256 epoch = _lastDepositedEpoch[operator];
        uint256 rate = _epochDepositRate[epoch];
        return rate == 0 ? 0 : _pendingDeposit[operator];
    }

    /**
     * @notice Returns an operator's amount of shares fulfilled for deposit.
     * @dev For requests yet to be fulfilled, this will return 0.
     * @param operator The address of the operator.
     * @return The amount of shares that can be minted.
     */
    function maxMint(address operator) public view override returns (uint256) {
        uint256 epoch = _lastDepositedEpoch[operator];
        uint256 rate = _epochDepositRate[epoch];
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

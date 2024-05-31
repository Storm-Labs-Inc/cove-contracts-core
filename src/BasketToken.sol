// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Errors } from "src/libraries/Errors.sol";

// import safetrasnfer from openzeppelin
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IBasketManager {
    function totalAssetValue(uint256 strategyId) external view returns (uint256);
}

interface IAssetRegistry {
    function isAssetsPaused(address) external returns (bool);
}

contract BasketToken is ERC4626Upgradeable {
    using SafeERC20 for IERC20;

    /**
     * Modifiers
     */
    modifier onlyOwner() {
        // TODO what is role of owner vs BM
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    modifier onlyBasketManager() {
        if (msg.sender != basketManager) {
            revert Errors.NotBasketManager();
        }
        _;
    }

    /**
     * Events
     */
    event DepositRequested(address indexed sender, uint256 indexed epoch, uint256 assets);
    event RedeemRequested(address indexed sender, address indexed operator, address indexed owner, uint256 shares);

    mapping(address operator => uint256 assets) internal _pendingDeposit;
    mapping(address operator => uint256 shares) internal _pendingRedeem;

    mapping(uint256 epoch => uint256 rate) internal _epochDepositRate;
    mapping(uint256 epoch => uint256 rate) internal _epochRedeemRate;

    mapping(address operator => uint256 epoch) internal _lastDepositedEpoch;
    mapping(address operator => uint256 epoch) internal _lastRedeemEpoch;

    uint256 internal _totalPendingDeposits;
    uint256 internal _totalPendingRedeems;

    address public owner;
    uint256 public ids;
    address public basketManager;
    address public assetRegistry;
    uint256 public bitFlag;
    uint256 public strategyId;
    uint256 _currentDepositEpoch;
    uint256 _currentRedeemEpoch;

    /**
     * @notice Disables the ability to call initializers.
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 _asset,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        uint256 strategyId_
    )
        public
        initializer
    {
        owner = msg.sender;
        // TODO: basketManager is set to msg.sender, what is role of owner vs BM?
        basketManager = msg.sender;
        bitFlag = bitFlag_;
        strategyId = strategyId_;
        __ERC4626_init(IERC20Upgradeable(address(_asset)));
        __ERC20_init(string.concat("CoveBasket-", name_), string.concat("cb", symbol_));
    }

    function setBasketManager(address _basketManager) external {
        basketManager = _basketManager;
    }

    function setAssetRegistry(address _assetRegistry) external {
        assetRegistry = _assetRegistry;
    }

    function totalAssets() public view override returns (uint256) {
        // Below will not be effected by pending assets
        return IBasketManager(basketManager).totalAssetValue(strategyId);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice this deposit request is added to any pending deposit request
    function requestDeposit(uint256 assets, address receiver) public {
        if (maxDeposit(receiver) > 0) {
            revert Errors.MustClaimOutstandingDeposit();
        }
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        // Check if asset is paused
        if (IAssetRegistry(assetRegistry).isAssetsPaused(asset())) {
            revert Errors.AssetPaused();
        }
        // Assets are immediately transferrred to here to await the basketManager to pull them
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        uint256 currentPendingAssets = _pendingDeposit[receiver];
        _lastDepositedEpoch[receiver] = _currentDepositEpoch;
        _pendingDeposit[receiver] = (currentPendingAssets + assets);
        _totalPendingDeposits += assets;

        emit DepositRequested(receiver, _currentDepositEpoch, assets);
    }

    /// @notice this deposit request is added to any pending deposit request
    function requestDeposit(uint256 assets) public {
        requestDeposit(assets, msg.sender);
    }

    function pendingDepositRequest(address operator) public view returns (uint256 assets) {
        // check if rate is 0 if not return 0 otherwise return assets
        if (_epochDepositRate[_lastDepositedEpoch[operator]] != 0) {
            return 0;
        }
        assets = _pendingDeposit[operator];
    }

    function requestRedeem(uint256 shares, address operator, address requestOwner) public {
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        if (maxRedeem(requestOwner) > 0) {
            revert Errors.MustClaimOutstandingRedeem();
        }
        if (IAssetRegistry(assetRegistry).isAssetsPaused(asset())) {
            revert Errors.AssetPaused();
        }
        if (msg.sender != requestOwner) {
            _spendAllowance(requestOwner, msg.sender, shares);
        }
        _transfer(requestOwner, address(this), shares);
        uint256 currentPendingWithdraw = _pendingRedeem[operator];
        _lastRedeemEpoch[operator] = _currentRedeemEpoch;
        _pendingRedeem[operator] = (currentPendingWithdraw + shares);
        _totalPendingRedeems += shares;
        emit RedeemRequested(msg.sender, operator, requestOwner, shares);
    }

    function requestRedeem(uint256 shares) public {
        requestRedeem(shares, msg.sender, msg.sender);
    }

    function pendingRedeemRequest(address operator) public view returns (uint256 shares) {
        // check if rate is 0 if not return 0 otherwise return shares
        if (_epochRedeemRate[_lastRedeemEpoch[operator]] != 0) {
            return 0;
        }
        shares = _pendingRedeem[operator];
    }

    function fulfillDeposit(uint256 shares) public onlyBasketManager {
        if (_totalPendingDeposits == 0) {
            revert Errors.ZeroPendingDeposits();
        }
        uint256 assets = _totalPendingDeposits;
        _mint(address(this), shares);
        uint256 rate = assets / shares;
        _epochDepositRate[_currentDepositEpoch] = rate;
        _currentDepositEpoch += 1;
        _totalPendingDeposits = 0;
        IERC20(asset()).safeTransfer(basketManager, assets);
    }

    function fulfillRedeem(uint256 assets) public onlyBasketManager {
        if (_totalPendingRedeems == 0) {
            revert Errors.ZeroPendingRedeems();
        }
        uint256 shares = _totalPendingRedeems;
        _burn(address(this), shares);
        uint256 rate = assets / shares;
        _epochRedeemRate[_currentRedeemEpoch] = rate;
        _currentRedeemEpoch += 1;
        _totalPendingRedeems = 0;
        IERC20(asset()).safeTransferFrom(basketManager, address(this), assets); // <-- pull function from BM?
    }

    function totalPendingDeposits() public view returns (uint256) {
        return _totalPendingDeposits;
    }

    function totalPendingRedeems() public view returns (uint256) {
        return _totalPendingRedeems;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    // Instead of usual operations, the deposit and mint functions will transfer the fulfilled deposits shares
    function deposit(uint256 assets, address receiver) public override returns (uint256 claimableShares) {
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (assets != maxDeposit(msg.sender)) {
            revert Errors.MustClaimFullAmount();
        }

        // maxMint returns shares at the fulfilled rate only if the deposit has been filfilled
        claimableShares = maxMint(msg.sender);
        delete _pendingDeposit[msg.sender];
        _transfer(address(this), receiver, claimableShares); //TODO does not work with public transfer(), errors on
            // `transfer amount exceeds balance`

        emit Deposit(msg.sender, receiver, assets, claimableShares);
    }

    // NOTE: Deposit should be used in all instances
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // The maxWithdraw call checks that shares are claimable
        uint256 claimableShares = maxMint(msg.sender);
        if (claimableShares == 0) {
            revert Errors.ZeroAmount();
        }
        if (shares != claimableShares) {
            revert Errors.MustClaimFullAmount();
        }

        assets = _pendingDeposit[msg.sender];
        delete _pendingDeposit[msg.sender];
        _transfer(address(this), receiver, claimableShares); //TODO does not work with public transfer(), errors on
            // `transfer amount exceeds balance`

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address operator) public override returns (uint256 shares) {
        // TODO: what to do with operator here
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (assets != maxWithdraw(msg.sender)) {
            revert Errors.MustClaimFullAmount();
        }
        delete _pendingRedeem[msg.sender];
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
        // Is it worth the gas to get shares amount just for an event?
    }

    function redeem(uint256 shares, address receiver, address operator) public override returns (uint256 assets) {
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        if (shares != maxRedeem(msg.sender)) {
            revert Errors.MustClaimFullAmount();
        }
        uint256 assets = maxWithdraw(msg.sender);
        delete _pendingRedeem[msg.sender];
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
    }

    function maxWithdraw(address operator) public view override returns (uint256) {
        uint256 epoch = _lastRedeemEpoch[operator];
        uint256 rate = _epochRedeemRate[epoch];
        if (rate == 0) {
            return 0;
        }
        return _pendingRedeem[operator] * rate;
    }

    function maxRedeem(address operator) public view override returns (uint256) {
        uint256 epoch = _lastRedeemEpoch[operator];
        uint256 rate = _epochRedeemRate[epoch];
        if (rate == 0) {
            return 0;
        }
        return _pendingRedeem[operator];
    }

    function maxDeposit(address operator) public view override returns (uint256) {
        uint256 epoch = _lastDepositedEpoch[operator];
        uint256 rate = _epochDepositRate[epoch];
        if (rate == 0) {
            return 0;
        }
        return _pendingDeposit[operator];
    }

    function maxMint(address operator) public view override returns (uint256) {
        uint256 epoch = _lastDepositedEpoch[operator];
        uint256 rate = _epochDepositRate[epoch];
        if (rate == 0) {
            return 0;
        }
        return _pendingDeposit[operator] / rate;
    }

    // Preview functions always revert for async flows
    function previewDeposit(uint256) public pure override returns (uint256) {
        revert();
    }

    // NOTE: if using claimable deposits, this will need to be updated to reflect the claimable deposits
    function previewMint(uint256) public pure override returns (uint256) {
        revert();
    }

    // TODO: add functions for cancelling requests
    function cancelDepositRequest(address operator) public {
        if (msg.sender != operator) {
            revert Errors.NotOwner();
        }
        uint256 pendingDeposit = pendingDepositRequest(operator);
        if (pendingDeposit == 0) {
            revert Errors.ZeroPendingDeposits();
        }
        delete _pendingDeposit[operator];
        _totalPendingDeposits -= pendingDeposit;
        IERC20(asset()).safeTransfer(operator, pendingDeposit);
    }

    function cancelRedeemRequest(address operator) public {
        if (msg.sender != operator) {
            revert Errors.NotOwner();
        }
        uint256 pendingRedeem = pendingRedeemRequest(operator);
        if (pendingRedeem == 0) {
            revert Errors.ZeroPendingRedeems();
        }
        delete _pendingRedeem[operator];
        _totalPendingRedeems -= pendingRedeem;
        _transfer(address(this), msg.sender, pendingRedeem);
    }
}

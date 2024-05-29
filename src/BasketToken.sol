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
    // function isRebalancing(uint256 strategyId) external returns (bool); // get rid of
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
    event DepositRequest(address indexed sender, uint256 indexed epoch, uint256 assets);
    event RedeemRequest(address indexed sender, address indexed operator, address indexed owner, uint256 shares);

    mapping(address => uint256) internal _pendingDeposit;
    mapping(address => uint256) internal _pendingWithdraw;

    mapping(uint256 => uint256) internal _epochDepositRate;
    mapping(uint256 => uint256) internal _epochWithdrawRate;

    mapping(address => uint256) internal _lastDepositedEpoch;
    mapping(address => uint256) internal _lastWithdrawnEpoch;

    uint256 internal _totalPendingDeposits;
    uint256 internal _totalPendingRedeems;
    address[] internal _pendingDepositors;
    address[] internal _pendingWithdrawers;

    address public owner;
    uint256 public ids;
    address public basketManager;
    address public assetRegistry;
    uint256 public bitFlag;
    uint256 public strategyId;
    uint32 public constant REDEEM_DELAY_SECONDS = 3 days; // remove

    // get rid of below
    struct ClaimableDeposit {
        uint256 assets;
        uint256 shares;
    }

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
        // NOTE: basketManager is set to msg.sender, what is role of owner vs BM
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

        emit DepositRequest(receiver, _currentDepositEpoch, assets);
    }

    /// @notice this deposit request is added to any pending deposit request
    function requestDeposit(uint256 assets) public {
        requestDeposit(assets, msg.sender);
    }

    function pendingDepositRequest(address operator) public view returns (uint256 assets) {
        // check if rate is 0 if not return 0 orhterwise return assets
        if (_epochDepositRate[_lastDepositedEpoch[operator]] != 0) {
            return 0;
        }
        assets = _pendingDeposit[operator];
    }

    function requestRedeem(uint256 shares, address operator, address requestOwner) public {
        if (IAssetRegistry(assetRegistry).isAssetsPaused(asset())) {
            revert Errors.AssetPaused();
        }
        if (msg.sender != requestOwner) {
            _spendAllowance(requestOwner, msg.sender, shares);
        }
        transfer(address(this), shares);
        uint256 currentPendingWithdraw = _pendingWithdraw[operator]; //<-- is this needed?
        _lastWithdrawnEpoch[operator] = _currentRedeemEpoch;
        _pendingWithdraw[operator] = (currentPendingWithdraw + shares);
        _totalPendingRedeems += shares;
        emit RedeemRequest(msg.sender, operator, requestOwner, shares);
    }

    function requestRedeem(uint256 shares, address operator) public {
        requestRedeem(shares, operator, msg.sender);
    }

    function pendingRedeemRequest(address operator) public view returns (uint256 shares) {
        // check if rate is 0 if not return 0 orhterwise return shares
        if (_epochWithdrawRate[_lastWithdrawnEpoch[operator]] != 0) {
            return 0;
        }
        shares = _pendingWithdraw[operator];
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
            revert Errors.ZeroPendingDeposits();
        }
        uint256 shares = _totalPendingRedeems;
        _burn(address(this), shares);
        uint256 rate = assets / shares;
        _epochWithdrawRate[_currentRedeemEpoch] = rate;
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
        _transfer(address(this), receiver, claimableShares); //TODO does not work with public transfer()

        emit Deposit(msg.sender, receiver, assets, claimableShares);
    }

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
        _transfer(address(this), receiver, claimableShares); //TODO does not work with public transfer()

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address operator) public override returns (uint256 shares) {
        // TODO: what to do with operator here
        if (assets == 0) {
            revert Errors.ZeroAmount();
        }
        if (assets != maxWithdraw(operator)) {
            revert Errors.MustClaimFullAmount();
        }
        uint256 withdrawableAmount = maxWithdraw(msg.sender);
        delete _pendingWithdraw[msg.sender];
        IERC20(asset()).safeTransfer(receiver, withdrawableAmount);
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
        // TODO fix return value
    }

    function redeem(uint256 shares, address receiver, address operator) public override returns (uint256 assets) {
        uint256 withdrawableShares = maxRedeem(msg.sender);
        if (withdrawableShares == 0) {
            revert Errors.ZeroAmount();
        }
        if (shares != withdrawableShares) {
            revert Errors.MustClaimFullAmount();
        }

        assets = _pendingWithdraw[msg.sender];
        delete _pendingWithdraw[msg.sender];
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
        // TODO fix return value
    }

    function maxWithdraw(address operator) public view override returns (uint256) {
        uint256 epoch = _lastWithdrawnEpoch[operator];
        uint256 rate = _epochWithdrawRate[epoch];
        if (rate == 0) {
            return 0;
        }
        return _pendingWithdraw[operator];
    }

    function maxRedeem(address operator) public view override returns (uint256) {
        uint256 epoch = _lastWithdrawnEpoch[operator];
        uint256 rate = _epochWithdrawRate[epoch];
        if (rate == 0) {
            return 0;
        }
        return _pendingWithdraw[operator] / rate; // TODO: use safemath
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
        return _pendingDeposit[operator] / rate; // TODO: use safemath
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
        // check if rate is 0 if not revert
        require(msg.sender == operator, "NOT_OWNER"); // remove operator just use sender
        if (_epochDepositRate[_lastDepositedEpoch[operator]] != 0) {
            revert("Deposit already fulfilled");
        }
        uint256 assets = _pendingDeposit[operator];
        delete _pendingDeposit[operator];
        _totalPendingDeposits -= assets; // TODO: this underflows
        IERC20(asset()).safeTransfer(operator, assets);
    }

    function cancelWithdrawRequest(address operator) public {
        // check if rate is 0 if not revert
        require(msg.sender == operator, "NOT_OWNER");
        if (_epochWithdrawRate[_lastWithdrawnEpoch[operator]] != 0) {
            revert("Withdraw already fulfilled");
        }
        uint256 shares = _pendingWithdraw[operator];
        delete _pendingWithdraw[operator];
        _totalPendingRedeems -= shares; // TODO: this underflows
        _transfer(address(this), msg.sender, shares);
    }
}

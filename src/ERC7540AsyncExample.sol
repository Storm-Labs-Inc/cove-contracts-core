// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
// import safetrasnfer from openzeppelin
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// THIS VAULT IS AN UNOPTIMIZED, POTENTIALLY INSECURE REFERENCE EXAMPLE AND IN NO WAY MEANT TO BE USED IN PRODUCTION

/**
 * @notice ERC7540 Implementing Controlled Async Deposits
 *
 *     This Vault has the following properties:
 *     - yield for the underlying asset is assumed to be transferred directly into the vault by some arbitrary mechanism
 *     - async deposits are subject to approval by an owner account
 *     - users can only deposit the maximum amount.
 *         To allow partial claims, the deposit and mint functions would need to allow for pro rata claims.
 *         Conversions between claimable assets/shares should be checked for rounding safety.
 */
contract ERC7540AsyncExample is ERC4626 {
    using SafeERC20 for ERC20;

    mapping(address => PendingDeposit) internal _pendingDeposit;
    mapping(uint256 => RedemptionRequest) internal _pendingRedemption;
    mapping(address => uint256) internal _pendingRedemptionIds;
    mapping(address => ClaimableDeposit) internal _claimableDeposit;
    uint256 internal _totalPendingAssets;

    address public owner;
    address public basketManager;
    uint256 public ids;
    uint32 public constant REDEEM_DELAY_SECONDS = 3 days;

    struct PendingDeposit {
        uint256 assets;
    }

    struct ClaimableDeposit {
        uint256 assets;
        uint256 shares;
    }

    struct RedemptionRequest {
        address operator;
        uint256 assets;
        uint256 shares;
        uint32 claimableTimestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    event DepositRequest(address indexed sender, address indexed operator, uint256 assets);
    event ManagerDepositRequest(uint256 assets);
    event RedeemRequest(address indexed sender, address indexed operator, address indexed owner, uint256 shares);

    constructor(IERC20 _asset, string memory name_, string memory symbol_) ERC4626(_asset) ERC20(name_, symbol_) {
        owner = msg.sender;
        // NOTE: basketManager is set to this address for testing purposes
        basketManager = address(this);
    }

    function setBasketManager(address _basketManager) external {
        basketManager = _basketManager;
    }

    function totalAssets() public view override returns (uint256) {
        // total assets pending redemption must be removed from the reported total assets
        // otherwise pending assets would be treated as yield for outstanding shares
        // NOTE: changed below to use basketManager instead of address(this)
        return ERC20(asset()).balanceOf(basketManager) - _totalPendingAssets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice this deposit request is added to any pending deposit request
    /// @dev will be removed in favor of requestDepositFromManager
    function requestDeposit(uint256 assets, address operator) public {
        require(assets != 0, "ZERO_ASSETS");

        ERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        uint256 currentPendingAssets = _pendingDeposit[operator].assets;
        _pendingDeposit[operator] = PendingDeposit(assets + currentPendingAssets);

        _totalPendingAssets += assets;

        emit DepositRequest(msg.sender, operator, assets);
    }

    // @notice function to only be used by the basketManager, requests a deposit while holding the funds in the manager
    // contract
    function requestDepositFromManager(uint256 assets, address operator) public {
        require(assets != 0, "ZERO_ASSETS");

        // the transfer of assets is omitted here as the assets are held within the basketManager
        // all other operations are the same for share accounting

        uint256 currentPendingAssets = _pendingDeposit[operator].assets;
        _pendingDeposit[operator] = PendingDeposit(assets + currentPendingAssets);

        _totalPendingAssets += assets;

        emit ManagerDepositRequest(assets);
    }

    function pendingDepositRequest(address operator) public view returns (uint256 assets) {
        assets = _pendingDeposit[operator].assets;
    }

    /// @notice this redemption request locks in the current exchange rate, restarts the withdrawal timelock delay, and
    /// increments any outstanding request
    /// NOTE: if there is an outstanding claimable request, users benefit from claiming before requesting again
    function requestRedeem(uint256 shares, address operator, address requestOwner) public returns (uint256 id) {
        if (msg.sender != requestOwner && msg.sender != owner) {
            revert("NOT_OWNER");
        }

        uint256 assets;
        require((assets = convertToAssets(shares)) != 0, "ZERO_ASSETS");

        // TODO changed below from owner to operator, check if correct
        _burn(operator, shares);

        id = ids++;

        _pendingRedemption[id] =
            RedemptionRequest(operator, assets, shares, uint32(block.timestamp) + REDEEM_DELAY_SECONDS);
        _pendingRedemptionIds[operator] = id;

        _totalPendingAssets += assets;

        emit RedeemRequest(msg.sender, operator, owner, shares);
    }

    function pendingRedeemRequest(uint256 id) public view returns (uint256 shares) {
        RedemptionRequest memory request = _pendingRedemption[id];

        // If the claimable timestamp is in the future, return the pending shares
        // Otherwise return 0 as all are claimable
        if (request.claimableTimestamp > block.timestamp) {
            return request.shares;
        }
    }

    function ownerOf(uint256 rid) public view returns (address) {
        return _pendingRedemption[rid].operator;
    }

    function transferRequest(uint256 rid, address to) public returns (address) {
        require(msg.sender == ownerOf(rid)); // Can optionally add additional approval/validation logic here

        _pendingRedemption[rid].operator = to;
    }

    function claimRequest(uint256 rid, address to) public returns (address) {
        redeem(_pendingRedemption[rid].shares, to, _pendingRedemption[rid].operator);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FULFILLMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    function fulfillDeposit(address operator) public onlyOwner returns (uint256 shares) {
        PendingDeposit memory request = _pendingDeposit[operator];

        require(request.assets != 0, "ZERO_ASSETS");

        shares = convertToShares(request.assets);
        _mint(operator, shares);

        uint256 currentClaimableAssets = _claimableDeposit[operator].assets;
        uint256 currentClaimableShares = _claimableDeposit[operator].shares;
        _claimableDeposit[operator] =
            ClaimableDeposit(request.assets + currentClaimableAssets, shares + currentClaimableShares);

        delete _pendingDeposit[operator];
        _totalPendingAssets -= request.assets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // The maxWithdraw call checks that assets are claimable
        require(assets != 0 && assets == maxDeposit(msg.sender), "Must claim nonzero maximum deposit");

        shares = _claimableDeposit[msg.sender].shares;
        delete _claimableDeposit[msg.sender];

        // approve the receiver for the shares
        ERC20(address(this)).approve(receiver, shares);
        require(transfer(receiver, 1e17), "TRANSFER_FAILED");

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // The maxWithdraw call checks that shares are claimable
        require(shares != 0 && shares == maxMint(msg.sender), "Must claim nonzero maximum mint");

        assets = _claimableDeposit[msg.sender].assets;
        delete _claimableDeposit[msg.sender];
        require(transfer(receiver, shares), "TRANSFER_FAILED");

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _getPendingRedemptionId(address operator) internal view returns (uint256) {
        // TODO: this will not work in practice as an operator can have multiple pending redemptions
        return _pendingRedemptionIds[operator];
    }

    function withdraw(uint256 assets, address receiver, address operator) public override returns (uint256 shares) {
        // TODO: removing this check for now, in the future will check for basketManager as the sender
        // require(msg.sender == operator, "Sender must be operator");
        // The maxWithdraw call checks that assets are claimable
        require(assets != 0, "0 assets");
        require(assets != 0 && assets == maxWithdraw(operator), "Must claim nonzero maximum withdraw");
        uint256 id = _getPendingRedemptionId(operator);
        shares = _pendingRedemption[id].shares;
        delete _pendingRedemption[id];

        _totalPendingAssets -= shares;

        require(ERC20(asset()).transfer(receiver, assets), "TRANSFER_FAILED");

        emit Withdraw(msg.sender, receiver, operator, assets, shares);
    }

    // TODO: probably remove original withdraw in favor of this
    function withdrawFromManager(uint256 assets, address receiver, address operator) public returns (uint256 shares) {
        // TODO: removing this check for now, in the future will check for basketManager as the sender
        // require(msg.sender == operator, "Sender must be operator");
        // The maxWithdraw call checks that assets are claimable
        require(assets != 0, "0 assets");
        require(assets != 0 && assets == maxWithdraw(operator), "Must claim nonzero maximum withdraw");
        uint256 id = _getPendingRedemptionId(operator);
        shares = _pendingRedemption[id].shares;
        delete _pendingRedemption[id];

        _totalPendingAssets -= assets;

        // NOTE remove transfer here and instead transfer from basketManager
        // require(ERC20(asset()).transfer(receiver, assets), "TRANSFER_FAILED");

        emit Withdraw(msg.sender, receiver, operator, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address operator) public override returns (uint256 assets) {
        require(msg.sender == operator, "Sender must be operator");
        // The maxWithdraw call checks that assets are claimable
        require(shares != 0 && shares == maxRedeem(operator), "Must claim nonzero maximum redeem");

        uint256 id = _getPendingRedemptionId(operator);
        assets = _pendingRedemption[id].assets;
        delete _pendingRedemption[id];

        _totalPendingAssets -= assets;

        require(ERC20(asset()).transfer(receiver, assets), "TRANSFER_FAILED");

        emit Withdraw(msg.sender, receiver, operator, assets, shares);
    }

    // The max functions return the outstanding quantity if if the redeem delay window has passed

    function maxWithdraw(address operator) public view override returns (uint256) {
        uint256 id = _getPendingRedemptionId(operator);
        RedemptionRequest memory request = _pendingRedemption[id];

        // If the redeem delay window has passed, return the pending assets
        if (request.claimableTimestamp <= block.timestamp) {
            return request.assets;
        }
    }

    function maxRedeem(address operator) public view override returns (uint256) {
        uint256 id = _getPendingRedemptionId(operator);
        RedemptionRequest memory request = _pendingRedemption[id];

        // If the redeem delay window has passed, return the pending shares
        if (request.claimableTimestamp <= block.timestamp) {
            return request.shares;
        }
    }

    function maxDeposit(address operator) public view override returns (uint256) {
        ClaimableDeposit memory claimable = _claimableDeposit[operator];
        return claimable.assets;
    }

    function maxMint(address operator) public view override returns (uint256) {
        ClaimableDeposit memory claimable = _claimableDeposit[operator];
        return claimable.shares;
    }

    function getPendingDeposits(address operator) public view returns (uint256 amount) {
        PendingDeposit memory request = _pendingDeposit[operator];
        return request.assets;
    }

    // Preview functions always revert for async flows

    function previewDeposit(uint256) public pure override returns (uint256) {
        revert();
    }

    function previewMint(uint256) public pure override returns (uint256) {
        revert();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test, console } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IPyth } from "@pyth/IPyth.sol";
import { PythStructs } from "@pyth/PythStructs.sol";
import { Deployer, GlobalDeployer } from "forge-deploy/Deployer.sol";

import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";
import { IAllowanceTransfer } from "src/interfaces/deps/permit2/IAllowanceTransfer.sol";
import { Constants } from "test/utils/Constants.t.sol";

abstract contract BaseTest is Test, Constants {
    /// VARIABLES ///
    struct Fork {
        uint256 forkId;
        uint256 blockNumber;
    }

    uint256 internal _MAX_UINT256 = type(uint256).max;
    /// @dev Hash of the `_PROXY_INITCODE`.
    /// Equivalent to `keccak256(abi.encodePacked(hex"67363d3d37363d34f03d5260086018f3"))`.
    bytes32 internal constant _PROXY_INITCODE_HASH = 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");

    // solhint-disable max-line-length
    bytes32 public constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );
    // solhint-enable max-line-length

    mapping(string => address) public users;
    mapping(string => Fork) public forks;

    /// TEST CONTRACTS ///
    ERC20 internal _usdc;
    ERC20 internal _dai;

    /// HELPER CONTRACTS ///
    Deployer internal deployer;

    /// SETUP FUNCTION ///
    function setUp() public virtual {
        deployer = getDeployer();
    }

    /// HELPERS ///

    /// @dev Generates a user, labels its address, and funds it with test assets.
    /// @param name The name of the user.
    /// @return The address of the user.
    function createUser(string memory name) public returns (address payable) {
        address payable user = payable(makeAddr(name));
        if (users[name] != address(0)) {
            console.log("User ", name, " already exists");
            return user;
        }
        vm.deal({ account: user, newBalance: 100 ether });
        users[name] = user;
        return user;
    }

    /// @dev Approves a list of contracts to spend the maximum of funds for a user.
    /// @param contractAddresses The list of contracts to approve.
    /// @param userAddresses The users to approve the contracts for.
    function _approveProtocol(address[] calldata contractAddresses, address[] calldata userAddresses) internal {
        for (uint256 i = 0; i < contractAddresses.length; i++) {
            for (uint256 n = 0; n < userAddresses.length; n++) {
                changePrank(userAddresses[n]);
                IERC20(contractAddresses[i]).approve(userAddresses[n], _MAX_UINT256);
            }
        }
        vm.stopPrank();
    }

    /// FORKING UTILS ///

    /// @dev Creates a fork at a given block.
    /// @param network The name of the network, matches an entry in the foundry.toml
    /// @param blockNumber The block number to fork from.
    /// @return The fork id.
    function forkNetworkAt(string memory network, uint256 blockNumber) public returns (uint256) {
        string memory rpcURL = vm.rpcUrl(network);
        uint256 forkId = vm.createSelectFork(rpcURL, blockNumber);
        forks[network] = Fork({ forkId: forkId, blockNumber: blockNumber });
        console.log("Started fork ", network, " at block ", block.number);
        console.log("with id", forkId);
        return forkId;
    }

    /// @dev Creates a fork at the latest block number.
    /// @param network The name of the network, matches an entry in the foundry.toml
    /// @return The fork id.
    function forkNetwork(string memory network) public returns (uint256) {
        string memory rpcURL = vm.rpcUrl(network);
        uint256 forkId = vm.createSelectFork(rpcURL);
        forks[network] = Fork({ forkId: forkId, blockNumber: block.number });
        console.log("Started fork ", network, "at block ", block.number);
        console.log("with id", forkId);
        return forkId;
    }

    function selectNamedFork(string memory network) public {
        vm.selectFork(forks[network].forkId);
    }

    /// @notice Airdrop an asset to an address with a given amount
    /// @dev This function should only be used for ERC20s that have totalSupply storage slot
    /// @param _asset address of the asset to airdrop
    /// @param _to address to airdrop to
    /// @param _amount amount to airdrop
    function airdrop(IERC20 _asset, address _to, uint256 _amount, bool adjust) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount, adjust);
    }

    function airdrop(IERC20 _asset, address _to, uint256 _amount) public {
        airdrop(_asset, _to, _amount, true);
    }

    /// @notice Take an asset away from an address with a given amount
    /// @param _asset address of the asset to take away
    /// @param _from address to take away from
    /// @param _amount amount to take away
    function takeAway(IERC20 _asset, address _from, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_from);
        if (balanceBefore < _amount) {
            revert("BaseTest:takeAway(): Insufficient balance");
        }
        deal(address(_asset), _from, balanceBefore - _amount);
    }

    function _formatAccessControlError(address addr, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, addr, role);
        // OpenZeppelin v4 used string error messages instead of revert error selectors
        // return abi.encodePacked(
        //     "AccessControl: account ",
        //     Strings.toHexString(addr),
        //     " is missing role ",
        //     Strings.toHexString(uint256(role), 32)
        // );
    }

    function assertEq(uint64[] memory a, uint64[] memory b) public {
        if (a.length != b.length) {
            revert("BaseTest:assertEq(): Arrays are not the same length");
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                revert("BaseTest:assertEq(): Arrays are not equal");
            }
        }
    }

    /// @dev Returns the deterministic address for `salt` with `deployer`.
    function _predictDeterministicAddress(
        bytes32 salt,
        address deployerAddress
    )
        internal
        pure
        returns (address deployed)
    {
        /// @solidity memory-safe-assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, deployerAddress) // Store `deployerAddress`.
            mstore8(0x0b, 0xff) // Store the prefix.
            mstore(0x20, salt) // Store the salt.
            mstore(0x40, _PROXY_INITCODE_HASH) // Store the bytecode hash.

            mstore(0x14, keccak256(0x0b, 0x55)) // Store the proxy's address.
            mstore(0x40, m) // Restore the free memory pointer.
            // 0xd6 = 0xc0 (short RLP prefix) + 0x16 (length of: 0x94 ++ proxy ++ 0x01).
            // 0x94 = 0x80 + 0x14 (0x14 = the length of an address, 20 bytes, in hex).
            mstore(0x00, 0xd694)
            mstore8(0x34, 0x01) // Nonce of the proxy contract (1).
            deployed := and(keccak256(0x1e, 0x17), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /// PERMIT & PERMIT2 HELPER FUNCTIONS ///
    function _generatePermitSignature(
        address token,
        address approvalFrom,
        uint256 approvalFromPrivKey,
        address approvalTo,
        uint256 amount,
        uint256 deadline
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // Use ERC-2612's domain separator from the token contract
        bytes32 domain = IERC20Permit(token).DOMAIN_SEPARATOR();
        uint256 nonce = IERC20Permit(token).nonces(approvalFrom);
        bytes32 msgHash = keccak256(abi.encode(PERMIT_TYPEHASH, approvalFrom, approvalTo, amount, nonce, deadline));

        // Sign the hashed message with the given domain following EIP-712 signature format
        (v, r, s) = vm.sign(
            approvalFromPrivKey, // user's private key
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-712 encoding
                    domain,
                    msgHash
                )
            )
        );
    }

    function _generatePermitSignatureAndLog(
        address token,
        address owner,
        uint256 ownerPrivateKey,
        address spender,
        uint256 value,
        uint256 deadline
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        string memory typeHashInput =
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";
        console.log("");
        console.log("Generating permit signature for token: ", token);
        console.log("EIP 712 input:");
        console.log("  TYPEHASH input: ", typeHashInput);
        console.log("  TYPEHASH: ", vm.toString(keccak256(bytes(typeHashInput))));
        console.log("Signature parameters:");
        console.log("  Private Key: ", vm.toString(bytes32(ownerPrivateKey)));
        console.log("  Owner: ", owner);
        console.log("  Spender: ", address(0xbeef));
        console.log("  Value: ", uint256(1000 ether));
        console.log("  Nonce: ", IERC20Permit(token).nonces(owner));
        console.log("  Deadline: ", _MAX_UINT256);
        (v, r, s) = _generatePermitSignature(token, owner, ownerPrivateKey, spender, value, deadline);
        console.log("");
        console.log("Generated signature: ");
        console.log("  v: ", v);
        console.log("  r: ", vm.toString(r));
        console.log("  s: ", vm.toString(s));
    }

    function _generatePermit2Signature(
        address token,
        address approvalFrom,
        uint256 approvalFromPrivKey,
        address approvalTo,
        uint256 amount,
        uint256 deadline
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // Use Permit2's domain separator
        bytes32 domain = IAllowanceTransfer(ETH_PERMIT2).DOMAIN_SEPARATOR();
        (,, uint48 nonce) = IAllowanceTransfer(ETH_PERMIT2).allowance(approvalFrom, token, approvalTo);
        bytes32 permitHash = keccak256(
            abi.encode(
                _PERMIT_DETAILS_TYPEHASH,
                IAllowanceTransfer.PermitDetails({
                    token: token, amount: uint160(amount), expiration: type(uint48).max, nonce: uint48(nonce)
                })
            )
        );
        bytes32 msgHash = keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, permitHash, approvalTo, deadline));

        // Sign the hashed message with the given domain following EIP-712 signature format
        (v, r, s) = vm.sign(
            approvalFromPrivKey, // user's private key
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-712 encoding
                    domain,
                    msgHash
                )
            )
        );
    }

    // Helper function to dump state and log timestamp
    function _dumpStateWithTimestamp(string memory label) internal {
        string memory path = string.concat(
            "dumpStates/", label, "_", vm.toString(block.number), "_", vm.toString(vm.getBlockTimestamp()), ".json"
        );
        console.log("Dumping state: ", path);
        vm.dumpState(path);
    }

    /**
     * @notice Returns the deployer contract. If the contract is not deployed, it etches it and initializes it.
     * @dev This is intentionally not marked as persistent because the deployment context will depend on chain ID. For
     * example, if a test changes the chain ID, this function needs to be called again to re-deploy and re-initialize
     * the deployer contract.
     * @return The deployer contract address.
     */
    function getDeployer() public returns (Deployer) {
        address addr = 0x666f7267652d6465706C6f790000000000000000;
        if (addr.code.length > 0) {
            return Deployer(addr);
        }
        bytes memory code = vm.getDeployedCode("Deployer.sol:GlobalDeployer");
        vm.etch(addr, code);
        vm.allowCheatcodes(addr);
        GlobalDeployer deployer_ = GlobalDeployer(addr);
        deployer_.init();
        return deployer_;
    }

    // Updates the timestamp of a Pyth oracle response
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        vm.record();
        IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        (bytes32[] memory readSlots,) = vm.accesses(PYTH);
        // Second read slot contains the timestamp in the last 32 bits
        // key   "0x28b01e5f9379f2a22698d286ce7faa0c31f6e4041ee32933d99cfe45a4a8ced5":
        // value "0x0000000000000000071021bc0000003f435df940fffffff80000000067a59cb0",
        // Where timestamp is 0x67a59cb0
        // overwrite this by using vm.store(readSlots[1], modified state)
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData =
            bytes32((uint256(vm.load(PYTH, readSlots[1])) & ~uint256(0xFFFFFFFF)) | newPublishTime);
        vm.store(PYTH, readSlots[1], modifiedStorageData);

        // Verify the storage was updated.
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        assertEq(res.publishTime, newPublishTime, "PythOracle timestamp was not updated correctly");
    }

    // Updates the timestamp of a ChainLink oracle response
    function _updateChainLinkOracleTimeStamp(address chainlinkOracle) internal {
        address aggregator = IChainlinkAggregatorV3Interface(chainlinkOracle).aggregator();
        vm.record();
        IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        (bytes32[] memory readSlots,) = vm.accesses(aggregator);
        // The third slot of the aggregator reads contains the timestamp in the first 32 bits
        // Format: 0x67a4876b67a48757000000000000000000000000000000000f806f93b728efc0
        // Where 0x67a4876b is the timestamp
        uint256 newPublishTime = vm.getBlockTimestamp();
        bytes32 modifiedStorageData = bytes32(
            (uint256(vm.load(aggregator, readSlots[2])) & ~uint256(0xFFFFFFFF << 224)) | (newPublishTime << 224)
        );
        vm.store(aggregator, readSlots[2], modifiedStorageData);

        // Verify the storage was updated
        (,,, uint256 updatedTimestamp,) = IChainlinkAggregatorV3Interface(chainlinkOracle).latestRoundData();
        assertEq(updatedTimestamp, newPublishTime, "ChainLink timestamp was not updated correctly");
    }
}

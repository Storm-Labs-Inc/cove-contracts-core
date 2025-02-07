export const abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "admin",
        type: "address",
        internalType: "address"
      },
      {
        name: "basketManager",
        type: "address",
        internalType: "address"
      },
      {
        name: "treasury",
        type: "address",
        internalType: "address"
      }
    ],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "DEFAULT_ADMIN_ROLE",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "basketTokenSponsorSplits",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "sponsorSplit",
        type: "uint16",
        internalType: "uint16"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "basketTokenSponsors",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "sponsor",
        type: "address",
        internalType: "address"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "claimSponsorFee",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "claimTreasuryFee",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "claimableSponsorFees",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "claimableFees",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "claimableTreasuryFees",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "claimableFees",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRoleAdmin",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    outputs: [
      {
        name: "",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRoleMember",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "index",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRoleMemberCount",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRoleMembers",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    outputs: [
      {
        name: "",
        type: "address[]",
        internalType: "address[]"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "grantRole",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "account",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "hasRole",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "account",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "notifyHarvestFee",
    inputs: [
      {
        name: "shares",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "protocolTreasury",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "renounceRole",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "callerConfirmation",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "rescue",
    inputs: [
      {
        name: "token",
        type: "address",
        internalType: "contract IERC20"
      },
      {
        name: "to",
        type: "address",
        internalType: "address"
      },
      {
        name: "amount",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "revokeRole",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "account",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setProtocolTreasury",
    inputs: [
      {
        name: "treasury",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setSponsor",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      },
      {
        name: "sponsor",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setSponsorSplit",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      },
      {
        name: "sponsorSplit",
        type: "uint16",
        internalType: "uint16"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "supportsInterface",
    inputs: [
      {
        name: "interfaceId",
        type: "bytes4",
        internalType: "bytes4"
      }
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "event",
    name: "RoleAdminChanged",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32"
      },
      {
        name: "previousAdminRole",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32"
      },
      {
        name: "newAdminRole",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "RoleGranted",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32"
      },
      {
        name: "account",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "sender",
        type: "address",
        indexed: true,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "RoleRevoked",
    inputs: [
      {
        name: "role",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32"
      },
      {
        name: "account",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "sender",
        type: "address",
        indexed: true,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "SponsorSet",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "sponsor",
        type: "address",
        indexed: true,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "SponsorSplitSet",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "sponsorSplit",
        type: "uint16",
        indexed: false,
        internalType: "uint16"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "TreasurySet",
    inputs: [
      {
        name: "treasury",
        type: "address",
        indexed: true,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "error",
    name: "AccessControlBadConfirmation",
    inputs: []
  },
  {
    type: "error",
    name: "AccessControlUnauthorizedAccount",
    inputs: [
      {
        name: "account",
        type: "address",
        internalType: "address"
      },
      {
        name: "neededRole",
        type: "bytes32",
        internalType: "bytes32"
      }
    ]
  },
  {
    type: "error",
    name: "EthTransferFailed",
    inputs: []
  },
  {
    type: "error",
    name: "InsufficientFundsToRescue",
    inputs: []
  },
  {
    type: "error",
    name: "NoSponsor",
    inputs: []
  },
  {
    type: "error",
    name: "NotBasketToken",
    inputs: []
  },
  {
    type: "error",
    name: "NotTreasury",
    inputs: []
  },
  {
    type: "error",
    name: "SafeERC20FailedOperation",
    inputs: [
      {
        name: "token",
        type: "address",
        internalType: "address"
      }
    ]
  },
  {
    type: "error",
    name: "SponsorSplitTooHigh",
    inputs: []
  },
  {
    type: "error",
    name: "Unauthorized",
    inputs: []
  },
  {
    type: "error",
    name: "ZeroAddress",
    inputs: []
  },
  {
    type: "error",
    name: "ZeroEthTransfer",
    inputs: []
  },
  {
    type: "error",
    name: "ZeroTokenTransfer",
    inputs: []
  }
];
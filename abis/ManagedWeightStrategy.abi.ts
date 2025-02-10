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
    name: "getTargetWeights",
    inputs: [
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [
      {
        name: "weights",
        type: "uint64[]",
        internalType: "uint64[]"
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
    name: "lastUpdated",
    inputs: [
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [
      {
        name: "epoch",
        type: "uint40",
        internalType: "uint40"
      },
      {
        name: "timestamp",
        type: "uint40",
        internalType: "uint40"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "multicall",
    inputs: [
      {
        name: "data",
        type: "bytes[]",
        internalType: "bytes[]"
      }
    ],
    outputs: [
      {
        name: "results",
        type: "bytes[]",
        internalType: "bytes[]"
      }
    ],
    stateMutability: "nonpayable"
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
    name: "setTargetWeights",
    inputs: [
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "newTargetWeights",
        type: "uint64[]",
        internalType: "uint64[]"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "supportsBitFlag",
    inputs: [
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
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
    type: "function",
    name: "targetWeights",
    inputs: [
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [
      {
        name: "weights",
        type: "uint64",
        internalType: "uint64"
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
    name: "TargetWeightsUpdated",
    inputs: [
      {
        name: "bitFlag",
        type: "uint256",
        indexed: true,
        internalType: "uint256"
      },
      {
        name: "epoch",
        type: "uint256",
        indexed: true,
        internalType: "uint256"
      },
      {
        name: "timestamp",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "newWeights",
        type: "uint64[]",
        indexed: false,
        internalType: "uint64[]"
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
    name: "AddressEmptyCode",
    inputs: [
      {
        name: "target",
        type: "address",
        internalType: "address"
      }
    ]
  },
  {
    type: "error",
    name: "FailedCall",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidWeightsLength",
    inputs: []
  },
  {
    type: "error",
    name: "NoTargetWeights",
    inputs: []
  },
  {
    type: "error",
    name: "UnsupportedBitFlag",
    inputs: []
  },
  {
    type: "error",
    name: "WeightsSumMismatch",
    inputs: []
  },
  {
    type: "error",
    name: "ZeroAddress",
    inputs: []
  }
];
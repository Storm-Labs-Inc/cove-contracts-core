export const abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "basketTokenImplementation",
        type: "address",
        internalType: "address"
      },
      {
        name: "eulerRouter_",
        type: "address",
        internalType: "address"
      },
      {
        name: "strategyRegistry_",
        type: "address",
        internalType: "address"
      },
      {
        name: "assetRegistry_",
        type: "address",
        internalType: "address"
      },
      {
        name: "admin",
        type: "address",
        internalType: "address"
      },
      {
        name: "feeCollector_",
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
    name: "assetRegistry",
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
    name: "basketAssets",
    inputs: [
      {
        name: "basket",
        type: "address",
        internalType: "address"
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
    name: "basketBalanceOf",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      },
      {
        name: "asset",
        type: "address",
        internalType: "address"
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
    name: "basketIdToAddress",
    inputs: [
      {
        name: "basketId",
        type: "bytes32",
        internalType: "bytes32"
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
    name: "basketTokenToBaseAssetIndex",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
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
    name: "basketTokenToIndex",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
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
    name: "basketTokens",
    inputs: [],
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
    name: "collectSwapFee",
    inputs: [
      {
        name: "asset",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "collectedFees",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "completeRebalance",
    inputs: [
      {
        name: "externalTrades",
        type: "tuple[]",
        internalType: "struct ExternalTrade[]",
        "components": [
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "basketTradeOwnership",
            type: "tuple[]",
            internalType: "struct BasketTradeOwnership[]",
            "components": [
              {
                name: "basket",
                type: "address",
                internalType: "address"
              },
              {
                name: "tradeOwnership",
                type: "uint96",
                internalType: "uint96"
              }
            ]
          }
        ]
      },
      {
        name: "basketsToRebalance",
        type: "address[]",
        internalType: "address[]"
      },
      {
        name: "targetWeights",
        type: "uint64[][]",
        internalType: "uint64[][]"
      },
      {
        name: "basketAssets_",
        type: "address[][]",
        internalType: "address[][]"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "createNewBasket",
    inputs: [
      {
        name: "basketName",
        type: "string",
        internalType: "string"
      },
      {
        name: "symbol",
        type: "string",
        internalType: "string"
      },
      {
        name: "baseAsset",
        type: "address",
        internalType: "address"
      },
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "strategy",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "basket",
        type: "address",
        internalType: "address"
      }
    ],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "eulerRouter",
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
    name: "execute",
    inputs: [
      {
        name: "target",
        type: "address",
        internalType: "address"
      },
      {
        name: "data",
        type: "bytes",
        internalType: "bytes"
      },
      {
        name: "value",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes"
      }
    ],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "executeTokenSwap",
    inputs: [
      {
        name: "externalTrades",
        type: "tuple[]",
        internalType: "struct ExternalTrade[]",
        "components": [
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "basketTradeOwnership",
            type: "tuple[]",
            internalType: "struct BasketTradeOwnership[]",
            "components": [
              {
                name: "basket",
                type: "address",
                internalType: "address"
              },
              {
                name: "tradeOwnership",
                type: "uint96",
                internalType: "uint96"
              }
            ]
          }
        ]
      },
      {
        name: "data",
        type: "bytes",
        internalType: "bytes"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "externalTradesHash",
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
    name: "feeCollector",
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
    name: "getAssetIndexInBasket",
    inputs: [
      {
        name: "basketToken",
        type: "address",
        internalType: "address"
      },
      {
        name: "asset",
        type: "address",
        internalType: "address"
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
    name: "managementFee",
    inputs: [
      {
        name: "basket",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "",
        type: "uint16",
        internalType: "uint16"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "numOfBasketTokens",
    inputs: [],
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
    name: "pause",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "paused",
    inputs: [],
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
    name: "proRataRedeem",
    inputs: [
      {
        name: "totalSupplyBefore",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "burnedShares",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "to",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "proposeRebalance",
    inputs: [
      {
        name: "basketsToRebalance",
        type: "address[]",
        internalType: "address[]"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "proposeTokenSwap",
    inputs: [
      {
        name: "internalTrades",
        type: "tuple[]",
        internalType: "struct InternalTrade[]",
        "components": [
          {
            name: "fromBasket",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "toBasket",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "maxAmount",
            type: "uint256",
            internalType: "uint256"
          }
        ]
      },
      {
        name: "externalTrades",
        type: "tuple[]",
        internalType: "struct ExternalTrade[]",
        "components": [
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "basketTradeOwnership",
            type: "tuple[]",
            internalType: "struct BasketTradeOwnership[]",
            "components": [
              {
                name: "basket",
                type: "address",
                internalType: "address"
              },
              {
                name: "tradeOwnership",
                type: "uint96",
                internalType: "uint96"
              }
            ]
          }
        ]
      },
      {
        name: "basketsToRebalance",
        type: "address[]",
        internalType: "address[]"
      },
      {
        name: "targetWeights",
        type: "uint64[][]",
        internalType: "uint64[][]"
      },
      {
        name: "basketAssets_",
        type: "address[][]",
        internalType: "address[][]"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "rebalanceStatus",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct RebalanceStatus",
        "components": [
          {
            name: "basketHash",
            type: "bytes32",
            internalType: "bytes32"
          },
          {
            name: "basketMask",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "epoch",
            type: "uint40",
            internalType: "uint40"
          },
          {
            name: "proposalTimestamp",
            type: "uint40",
            internalType: "uint40"
          },
          {
            name: "timestamp",
            type: "uint40",
            internalType: "uint40"
          },
          {
            name: "retryCount",
            type: "uint8",
            internalType: "uint8"
          },
          {
            name: "status",
            type: "uint8",
            internalType: "enum Status"
          }
        ]
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
        name: "balance",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "retryCount",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "uint8"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "retryLimit",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "uint8"
      }
    ],
    stateMutability: "view"
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
    name: "setManagementFee",
    inputs: [
      {
        name: "basket",
        type: "address",
        internalType: "address"
      },
      {
        name: "managementFee_",
        type: "uint16",
        internalType: "uint16"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setRetryLimit",
    inputs: [
      {
        name: "retryLimit_",
        type: "uint8",
        internalType: "uint8"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setSlippageLimit",
    inputs: [
      {
        name: "slippageLimit_",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setStepDelay",
    inputs: [
      {
        name: "stepDelay_",
        type: "uint40",
        internalType: "uint40"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setSwapFee",
    inputs: [
      {
        name: "swapFee_",
        type: "uint16",
        internalType: "uint16"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setTokenSwapAdapter",
    inputs: [
      {
        name: "tokenSwapAdapter_",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "setWeightDeviation",
    inputs: [
      {
        name: "weightDeviationLimit_",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "slippageLimit",
    inputs: [],
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
    name: "stepDelay",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint40",
        internalType: "uint40"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "strategyRegistry",
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
    name: "swapFee",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint16",
        internalType: "uint16"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "tokenSwapAdapter",
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
    name: "unpause",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "updateBitFlag",
    inputs: [
      {
        name: "basket",
        type: "address",
        internalType: "address"
      },
      {
        name: "bitFlag",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "weightDeviationLimit",
    inputs: [],
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
    type: "event",
    name: "BasketBitFlagUpdated",
    inputs: [
      {
        name: "basket",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "oldBitFlag",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "newBitFlag",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "oldId",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32"
      },
      {
        name: "newId",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "BasketCreated",
    inputs: [
      {
        name: "basket",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "basketName",
        type: "string",
        indexed: false,
        internalType: "string"
      },
      {
        name: "symbol",
        type: "string",
        indexed: false,
        internalType: "string"
      },
      {
        name: "baseAsset",
        type: "address",
        indexed: false,
        internalType: "address"
      },
      {
        name: "bitFlag",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "strategy",
        type: "address",
        indexed: false,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "ManagementFeeSet",
    inputs: [
      {
        name: "basket",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "oldFee",
        type: "uint16",
        indexed: false,
        internalType: "uint16"
      },
      {
        name: "newFee",
        type: "uint16",
        indexed: false,
        internalType: "uint16"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "Paused",
    inputs: [
      {
        name: "account",
        type: "address",
        indexed: false,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "RetryLimitSet",
    inputs: [
      {
        name: "oldLimit",
        type: "uint8",
        indexed: false,
        internalType: "uint8"
      },
      {
        name: "newLimit",
        type: "uint8",
        indexed: false,
        internalType: "uint8"
      }
    ],
    anonymous: false
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
    name: "SlippageLimitSet",
    inputs: [
      {
        name: "oldSlippage",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "newSlippage",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "StepDelaySet",
    inputs: [
      {
        name: "oldDelay",
        type: "uint40",
        indexed: false,
        internalType: "uint40"
      },
      {
        name: "newDelay",
        type: "uint40",
        indexed: false,
        internalType: "uint40"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "SwapFeeSet",
    inputs: [
      {
        name: "oldFee",
        type: "uint16",
        indexed: false,
        internalType: "uint16"
      },
      {
        name: "newFee",
        type: "uint16",
        indexed: false,
        internalType: "uint16"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "TokenSwapAdapterSet",
    inputs: [
      {
        name: "oldAdapter",
        type: "address",
        indexed: false,
        internalType: "address"
      },
      {
        name: "newAdapter",
        type: "address",
        indexed: false,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "TokenSwapExecuted",
    inputs: [
      {
        name: "epoch",
        type: "uint40",
        indexed: true,
        internalType: "uint40"
      },
      {
        name: "externalTrades",
        type: "tuple[]",
        indexed: false,
        internalType: "struct ExternalTrade[]",
        "components": [
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "basketTradeOwnership",
            type: "tuple[]",
            internalType: "struct BasketTradeOwnership[]",
            "components": [
              {
                name: "basket",
                type: "address",
                internalType: "address"
              },
              {
                name: "tradeOwnership",
                type: "uint96",
                internalType: "uint96"
              }
            ]
          }
        ]
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "TokenSwapProposed",
    inputs: [
      {
        name: "epoch",
        type: "uint40",
        indexed: true,
        internalType: "uint40"
      },
      {
        name: "internalTrades",
        type: "tuple[]",
        indexed: false,
        internalType: "struct InternalTrade[]",
        "components": [
          {
            name: "fromBasket",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "toBasket",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "maxAmount",
            type: "uint256",
            internalType: "uint256"
          }
        ]
      },
      {
        name: "externalTrades",
        type: "tuple[]",
        indexed: false,
        internalType: "struct ExternalTrade[]",
        "components": [
          {
            name: "sellToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "buyToken",
            type: "address",
            internalType: "address"
          },
          {
            name: "sellAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "minAmount",
            type: "uint256",
            internalType: "uint256"
          },
          {
            name: "basketTradeOwnership",
            type: "tuple[]",
            internalType: "struct BasketTradeOwnership[]",
            "components": [
              {
                name: "basket",
                type: "address",
                internalType: "address"
              },
              {
                name: "tradeOwnership",
                type: "uint96",
                internalType: "uint96"
              }
            ]
          }
        ]
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "Unpaused",
    inputs: [
      {
        name: "account",
        type: "address",
        indexed: false,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "WeightDeviationLimitSet",
    inputs: [
      {
        name: "oldDeviation",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "newDeviation",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
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
    name: "AssetExistsInUniverse",
    inputs: []
  },
  {
    type: "error",
    name: "BasketIdAlreadyExists",
    inputs: []
  },
  {
    type: "error",
    name: "BasketTokenNotFound",
    inputs: []
  },
  {
    type: "error",
    name: "BitFlagMustBeDifferent",
    inputs: []
  },
  {
    type: "error",
    name: "BitFlagMustIncludeCurrent",
    inputs: []
  },
  {
    type: "error",
    name: "BitFlagUnsupportedByStrategy",
    inputs: []
  },
  {
    type: "error",
    name: "EmptyExternalTrades",
    inputs: []
  },
  {
    type: "error",
    name: "EnforcedPause",
    inputs: []
  },
  {
    type: "error",
    name: "EthTransferFailed",
    inputs: []
  },
  {
    type: "error",
    name: "ExecuteTokenSwapFailed",
    inputs: []
  },
  {
    type: "error",
    name: "ExecutionFailed",
    inputs: []
  },
  {
    type: "error",
    name: "ExpectedPause",
    inputs: []
  },
  {
    type: "error",
    name: "ExternalTradesHashMismatch",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidHash",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidManagementFee",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidRetryCount",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidSlippageLimit",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidStepDelay",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidSwapFee",
    inputs: []
  },
  {
    type: "error",
    name: "InvalidWeightDeviationLimit",
    inputs: []
  },
  {
    type: "error",
    name: "MustWaitForRebalanceToComplete",
    inputs: []
  },
  {
    type: "error",
    name: "ReentrancyGuardReentrantCall",
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
    name: "TokenSwapNotProposed",
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
export const abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "cloneImplementation_",
        type: "address",
        internalType: "address"
      }
    ],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "cloneImplementation",
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
    name: "completeTokenSwap",
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
      }
    ],
    outputs: [
      {
        name: "claimedAmounts",
        type: "uint256[2][]",
        internalType: "uint256[2][]"
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
        name: "",
        type: "bytes",
        internalType: "bytes"
      }
    ],
    outputs: [],
    stateMutability: "payable"
  },
  {
    type: "event",
    name: "OrderCreated",
    inputs: [
      {
        name: "sellToken",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "buyToken",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "sellAmount",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "buyAmount",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "validTo",
        type: "uint32",
        indexed: false,
        internalType: "uint32"
      },
      {
        name: "swapContract",
        type: "address",
        indexed: false,
        internalType: "address"
      }
    ],
    anonymous: false
  },
  {
    type: "event",
    name: "TokenSwapCompleted",
    inputs: [
      {
        name: "sellToken",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "buyToken",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "claimedSellAmount",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "claimedBuyAmount",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      },
      {
        name: "swapContract",
        type: "address",
        indexed: false,
        internalType: "address"
      }
    ],
    anonymous: false
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
    name: "ZeroAddress",
    inputs: []
  }
];
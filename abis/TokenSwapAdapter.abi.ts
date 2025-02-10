export const abi = [
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
        name: "data",
        type: "bytes",
        internalType: "bytes"
      }
    ],
    outputs: [],
    stateMutability: "payable"
  }
];
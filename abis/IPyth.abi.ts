export const abi = [
  {
    type: "function",
    name: "getPrice",
    inputs: [
      {
        name: "id",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    outputs: [
      {
        name: "price",
        type: "tuple",
        internalType: "struct IPyth.Price",
        "components": [
          {
            name: "price",
            type: "int64",
            internalType: "int64"
          },
          {
            name: "conf",
            type: "uint64",
            internalType: "uint64"
          },
          {
            name: "expo",
            type: "int32",
            internalType: "int32"
          },
          {
            name: "publishTime",
            type: "uint256",
            internalType: "uint256"
          }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getUpdateFee",
    inputs: [
      {
        name: "updateData",
        type: "bytes[]",
        internalType: "bytes[]"
      }
    ],
    outputs: [
      {
        name: "feeAmount",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "updatePriceFeeds",
    inputs: [
      {
        name: "updateData",
        type: "bytes[]",
        internalType: "bytes[]"
      }
    ],
    outputs: [],
    stateMutability: "payable"
  }
];
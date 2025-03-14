export const abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "_vault",
        type: "address",
        internalType: "contract IERC4626"
      }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "base",
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
    name: "getQuote",
    inputs: [
      {
        name: "inAmount",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "base",
        type: "address",
        internalType: "address"
      },
      {
        name: "quote",
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
    name: "getQuotes",
    inputs: [
      {
        name: "inAmount",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "base",
        type: "address",
        internalType: "address"
      },
      {
        name: "quote",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256"
      },
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
    name: "name",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "string",
        internalType: "string"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "quote",
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
    type: "error",
    name: "PriceOracle_NotSupported",
    inputs: [
      {
        name: "base",
        type: "address",
        internalType: "address"
      },
      {
        name: "quote",
        type: "address",
        internalType: "address"
      }
    ]
  }
];
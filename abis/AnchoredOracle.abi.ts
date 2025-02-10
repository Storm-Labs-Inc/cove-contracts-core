export const abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "_primaryOracle",
        type: "address",
        internalType: "address"
      },
      {
        name: "_anchorOracle",
        type: "address",
        internalType: "address"
      },
      {
        name: "_maxDivergence",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "anchorOracle",
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
    name: "maxDivergence",
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
    name: "primaryOracle",
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
    name: "PriceOracle_InvalidAnswer",
    inputs: []
  },
  {
    type: "error",
    name: "PriceOracle_InvalidConfiguration",
    inputs: []
  }
];
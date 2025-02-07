export const abi = [
  {
    type: "function",
    name: "isOperator",
    inputs: [
      {
        name: "controller",
        type: "address",
        internalType: "address"
      },
      {
        name: "operator",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "status",
        type: "bool",
        internalType: "bool"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "setOperator",
    inputs: [
      {
        name: "operator",
        type: "address",
        internalType: "address"
      },
      {
        name: "approved",
        type: "bool",
        internalType: "bool"
      }
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool"
      }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "event",
    name: "OperatorSet",
    inputs: [
      {
        name: "controller",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "operator",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "approved",
        type: "bool",
        indexed: false,
        internalType: "bool"
      }
    ],
    anonymous: false
  }
];
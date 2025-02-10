export const abi = [
  {
    type: "function",
    name: "permit",
    inputs: [
      {
        name: "holder",
        type: "address",
        internalType: "address"
      },
      {
        name: "spender",
        type: "address",
        internalType: "address"
      },
      {
        name: "nonce",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "expiry",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "allowed",
        type: "bool",
        internalType: "bool"
      },
      {
        name: "v",
        type: "uint8",
        internalType: "uint8"
      },
      {
        name: "r",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "s",
        type: "bytes32",
        internalType: "bytes32"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  }
];
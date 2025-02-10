export const abi = [
  {
    type: "function",
    name: "addRegistry",
    inputs: [
      {
        name: "registryName",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "registryAddress",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "resolveAddressToRegistryData",
    inputs: [
      {
        name: "registryAddress",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "registryName",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "version",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "isLatest",
        type: "bool",
        internalType: "bool"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "resolveNameAndVersionToAddress",
    inputs: [
      {
        name: "registryName",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "version",
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
    name: "resolveNameToAllAddresses",
    inputs: [
      {
        name: "registryName",
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
    name: "resolveNameToLatestAddress",
    inputs: [
      {
        name: "registryName",
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
    name: "updateRegistry",
    inputs: [
      {
        name: "registryName",
        type: "bytes32",
        internalType: "bytes32"
      },
      {
        name: "registryAddress",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  }
];
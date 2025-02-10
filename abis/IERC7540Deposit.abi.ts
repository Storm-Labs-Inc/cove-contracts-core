export const abi = [
  {
    type: "function",
    name: "claimableDepositRequest",
    inputs: [
      {
        name: "requestId",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "controller",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "claimableAssets",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "deposit",
    inputs: [
      {
        name: "assets",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "receiver",
        type: "address",
        internalType: "address"
      },
      {
        name: "controller",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "shares",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "mint",
    inputs: [
      {
        name: "shares",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "receiver",
        type: "address",
        internalType: "address"
      },
      {
        name: "controller",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "assets",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "pendingDepositRequest",
    inputs: [
      {
        name: "requestId",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "controller",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "pendingAssets",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "requestDeposit",
    inputs: [
      {
        name: "assets",
        type: "uint256",
        internalType: "uint256"
      },
      {
        name: "controller",
        type: "address",
        internalType: "address"
      },
      {
        name: "owner",
        type: "address",
        internalType: "address"
      }
    ],
    outputs: [
      {
        name: "requestId",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "event",
    name: "DepositRequest",
    inputs: [
      {
        name: "controller",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "owner",
        type: "address",
        indexed: true,
        internalType: "address"
      },
      {
        name: "requestId",
        type: "uint256",
        indexed: true,
        internalType: "uint256"
      },
      {
        name: "sender",
        type: "address",
        indexed: false,
        internalType: "address"
      },
      {
        name: "assets",
        type: "uint256",
        indexed: false,
        internalType: "uint256"
      }
    ],
    anonymous: false
  }
];
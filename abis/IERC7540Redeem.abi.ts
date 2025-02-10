export const abi = [
  {
    type: "function",
    name: "claimableRedeemRequest",
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
        name: "claimableShares",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "pendingRedeemRequest",
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
        name: "pendingShares",
        type: "uint256",
        internalType: "uint256"
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "requestRedeem",
    inputs: [
      {
        name: "shares",
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
    name: "RedeemRequest",
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
# Dump States for Integration Testing

This directory contains various dump states that can be used to test different scenarios in the integration tests. These states represent different points in the contract's lifecycle and can be loaded into a local Anvil instance for testing and development.

## Available States

1. **Initial State**

   - `00_InitialState.json`: Initial fork state with basic setup

2. **Deposit Flow States**

   - `01_AccountHasBasketAssets.json`: State where user has WETH and USDC (basket assets)
   - `02_AccountHasPendingDeposit.json`: State after user has requested a deposit
   - `03_AccountHasClaimableDeposit.json`: State where deposit is claimable after rebalance proposal
   - `04_AccountHasBasketTokensWhileRebalancing.json`: State after user has claimed basket tokens while protocol is still rebalancing

3. **Rebalance and Redeem States**
   - `05_AccountHasBasketTokensCanProRataRedeem.json`: State after protocol rebalance, user can pro-rata redeem
   - `06_AccountHasPendingRedeem.json`: State after user has requested redemption
   - `07_AccountHasClaimableRedeem.json`: State where redemption is claimable after rebalance
   - `08_AccountHasClaimableRewards.json`: State where user has claimable farming rewards
   - `09_AccountHasFailedRedeem.json`: State where redemption failed and fallback shares are claimable

## Usage Instructions

### Basic Usage

To load a state, use the Anvil command with the following format:

```bash
anvil --fork-url $MAINNET_RPC_URL \
      --auto-impersonate \
      --fork-block-number 22046527 \
      --load-state dumpStates/<state_file>.json \
      --steps-tracing
```

### Important Notes

1. **Block Number Matching**: Always use block number 21928744 when forking. This ensures consistency between:

   - The genesis state in the dump files
   - The state fetched via the forked RPC

   Using a different block number may cause state inconsistencies when Anvil fetches storage for unknown addresses.

2. **Timestamp Management**: Each state has a corresponding timestamp that should be set before interacting with the contracts. To set the timestamp:

   ```bash
   # Extract timestamp from filename
   TIMESTAMP=$(echo <state_file> | grep -o '[0-9]*' | tail -1)

   # Set timestamp and mine a block
   cast rpc evm_setNextBlockTimestamp $TIMESTAMP && cast rpc anvil_mine
   ```

### Example Workflow

1. Start Anvil with a specific state:

   ```bash
   anvil --fork-url $MAINNET_RPC_URL \
         --auto-impersonate \
         --fork-block-number 22046527 \
         --load-state dumpStates/02_AccountHasPendingDeposit_1740638063.json \
         --steps-tracing
   ```

2. In a new terminal, set the correct timestamp:

   ```bash
   TIMESTAMP=$(echo 02_AccountHasPendingDeposit_1742058755.json | grep -o '[0-9]*' | tail -1)
   cast rpc evm_setNextBlockTimestamp $TIMESTAMP && cast rpc anvil_mine
   ```

3. Now you can interact with the contracts in their expected state.

## Test Scenario Details

The dump states follow a complete deposit-rebalance-redeem cycle with the test account (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266):

1. User starts with ETH, WETH and USDC
2. User requests a deposit of 10,000 USDC
3. Rebalance is proposed, making the deposit claimable
4. User claims basket shares while protocol is still rebalancing
5. Protocol executes external trades and completes rebalance
6. User requests redemption
7. Protocol rebalances, making the redemption claimable
8. User has claimable farming rewards
9. User experiences a failed redemption and has fallback shares to claim

## Troubleshooting

If you encounter state inconsistencies:

1. Verify you're using block number 21928744
2. Ensure you've set the correct timestamp from the state filename. You may need to mine a block with the new timestamp.
3. Check that you're using the latest version of the dump state files

# Dump States for Integration Testing

This directory contains various dump states that can be used to test different scenarios in the integration tests. These states represent different points in the contract's lifecycle and can be loaded into a local Anvil instance for testing and development.

## Available States

1. **Initial Setup**

   - `IntegrationTest_setup.json`: Initial setup state for integration tests

2. **Deposit Flow States**

   - `completeRebalance_MultipleBaskets_afterRequestDeposit.json`: State after deposit requests
   - `completeRebalance_MultipleBaskets_depositsRequestsProcessing.json`: State during deposit processing
   - `completeRebalance_MultipleBaskets_processDeposits_depositsClaimable.json`: State when user deposits are claimable
   - `completeRebalance_MultipleBaskets_depositsClaimed.json`: State after user deposits are claimed

3. **Redeem Flow States**

   - `completeRebalance_MultipleBaskets_afterRequestRedeem.json`: State after redeem requests
   - `completeRebalance_MultipleBaskets_redeemRequestsProcessing.json`: State during redeem processing
   - `completeRebalance_MultipleBaskets_userRedeemClaimable.json`: State when user redeems are claimable
   - `fallbackRedeem_userFallBackSharesClaimable.json`: State for user fallback redeem scenario

4. **Reward States**
   - `completeRebalance_rewardsHalfClaimable.json`: State with partially claimable rewards
   - `completeRebalance_rewardsFullClaimable.json`: State with fully claimable rewards

## Usage Instructions

### Basic Usage

To load a state, use the Anvil command with the following format:

```bash
anvil --fork-url $MAINNET_RPC_URL \
      --auto-impersonate \
      --fork-block-number 21792603 \
      --load-state dumpStates/<state_file>.json \
      --steps-tracing
```

### Important Notes

1. **Block Number Matching**: Always use block number 21792603 (from Constants.t.sol) when forking. This ensures consistency between:

   - The genesis state in the dump files
   - The state fetched via the forked RPC
     Using a different block number may cause state inconsistencies when Anvil fetches storage for unknown addresses.

2. **Timestamp Management**: Each state has a corresponding `.timestamp.txt` file containing the block timestamp. To set the correct timestamp:

   ```bash
   # Read timestamp from file
   TIMESTAMP=$(cat dumpStates/<state_file>.timestamp.txt)

   # Set timestamp and mine a block
   cast rpc evm_setNextBlockTimestamp $TIMESTAMP && cast rpc anvil_mine
   ```

### Example Workflow

1. Start Anvil with a specific state:

   ```bash
   anvil --fork-url $MAINNET_RPC_URL \
         --auto-impersonate \
         --fork-block-number 21792603 \
         --load-state dumpStates/completeRebalance_MultipleBaskets_afterRequestRedeem.json \
         --steps-tracing
   ```

2. In a new terminal, set the correct timestamp:

   ```bash
   TIMESTAMP=$(cat dumpStates/completeRebalance_MultipleBaskets_afterRequestRedeem.timestamp.txt)
   cast rpc evm_setNextBlockTimestamp $TIMESTAMP && cast rpc anvil_mine
   ```

3. Now you can interact with the contracts in their expected state.

## Troubleshooting

If you encounter state inconsistencies:

1. Verify you're using the same block number as in IntegrationTest.t.sol
2. Ensure you've set the correct timestamp from the corresponding .timestamp.txt file
3. Check that you're using the latest version of the dump state files

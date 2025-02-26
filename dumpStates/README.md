# Dump States for Integration Testing

This directory contains various dump states that can be used to test different scenarios in the integration tests. These states represent different points in the contract's lifecycle and can be loaded into a local Anvil instance for testing and development.

## Available States

1. **Initial States**

   - `BaseState.json`: Initial fork state with basic setup

2. **Deposit Flow States**

   - `01_accountHasSomeUSDC.json`: State where user has been allocated USDC
   - `02_accountHasRequestedDeposit.json`: State after user has requested a deposit
   - `03_accountHasClaimableBasketTokenShares.json`: State where basket shares are claimable
   - `04_accountHasBasketTokenShares.json`: State after user has claimed basket shares

3. **Rebalance and Redeem States**
   - `05_protocolHasCompletedRebalance_accountCanProRataRedeem.json`: State after protocol rebalance
   - `06_accountHasRequestedRedeem.json`: State after user has requested redemption

## Usage Instructions

### Basic Usage

To load a state, use the Anvil command with the following format:

```bash
anvil --fork-url $MAINNET_RPC_URL \
      --auto-impersonate \
      --fork-block-number 21928744 \
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
         --fork-block-number 21928744 \
         --load-state dumpStates/02_accountHasRequestedDeposit_1740638063.json \
         --steps-tracing
   ```

2. In a new terminal, set the correct timestamp:

   ```bash
   TIMESTAMP=$(echo 02_accountHasRequestedDeposit_1740638063.json | grep -o '[0-9]*' | tail -1)
   cast rpc evm_setNextBlockTimestamp $TIMESTAMP && cast rpc anvil_mine
   ```

3. Now you can interact with the contracts in their expected state.

## Test Scenario Details

The dump states follow a complete deposit-rebalance-redeem cycle:

1. User starts with 1,000,000 USDC
2. User requests a deposit of 10,000 USDC
3. Rebalance is proposed
4. User claims basket shares
5. Protocol executes external trades and completes rebalance
6. User requests redemption

## Troubleshooting

If you encounter state inconsistencies:

1. Verify you're using block number 21928744
2. Ensure you've set the correct timestamp from the corresponding .timestamp.txt file
3. Check that you're using the latest version of the dump state files

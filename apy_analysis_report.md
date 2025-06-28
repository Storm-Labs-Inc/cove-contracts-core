# Token APY Analysis Report
## Based on 30-Day Price per Share Data

### Executive Summary

This report analyzes the Annual Percentage Yield (APY) of various tokens on Ethereum blockchain based on their price per share changes over a 30-day period. The data was retrieved from the API endpoint and enhanced with on-chain token information using Foundry's cast command.

### Key Findings

#### Top Performing Tokens (by 30-day APY)

1. **cbBTC (Coinbase Wrapped BTC)** - 19.72% APY
   - 7-day APY: 191.83%
   - 30-day APY: 17.52%
   - Price change: 1.44%

2. **WBTC (Wrapped BTC)** - 19.46% APY
   - 7-day APY: 190.69%
   - 30-day APY: 17.31%
   - Price change: 1.42%

3. **tBTC v2** - 15.88% APY
   - 7-day APY: 188.92%
   - 30-day APY: 14.33%
   - Price change: 1.18%

4. **ysUSDC (SuperUSDC)** - 7.61% APY
   - This is an ERC4626 vault
   - 7-day APY: 6.53%
   - 30-day APY: 7.11%

5. **ysyG-yvUSDS-1 (Wrapped YearnV3 Strategy)** - 6.16% APY
   - This is an ERC4626 vault
   - 7-day APY: 8.58%
   - 30-day APY: 5.79%

### Token Categories

#### Yield-Bearing Vaults (ERC4626)
- ysUSDC (SuperUSDC) - 7.61% APY
- ysyG-yvUSDS-1 - 6.16% APY
- sfrxUSD (Staked Frax USD) - 6.06% APY
- yvUSDS-1 (USDS-1 yVault) - 5.06% APY
- yG-yvUSDS-1 - 5.06% APY
- sUSDe (Staked USDe) - 4.97% APY
- coveUSD - 4.03% APY
- sDAI (Savings Dai) - 1.37% APY

#### Stablecoins
- USDe - 0.96% APY
- crvUSD - 0.29% APY
- USDC - 0.14% APY
- USDS - 0.05% APY
- DAI - -0.01% APY
- frxUSD - -0.56% APY

#### Wrapped/Liquid Staking Tokens
- cbBTC - 19.72% APY (BTC wrapper)
- WBTC - 19.46% APY (BTC wrapper)
- tBTC - 15.88% APY (BTC wrapper)
- ETHx - -63.49% APY (Liquid staking)
- ezETH - -63.53% APY (Liquid staking)

### Observations

1. **BTC Wrappers Dominate**: The top 3 performing tokens are all Bitcoin wrappers, showing significant appreciation likely due to BTC price movements.

2. **Vault Performance**: ERC4626 vaults show moderate but consistent yields between 1-8% APY.

3. **Stablecoin Stability**: Most stablecoins show near-zero APY as expected, with some slight variations.

4. **Negative APYs**: Some liquid staking tokens (ETHx, ezETH) show significant negative APYs, which might indicate:
   - Depegging issues
   - Slashing events
   - Market volatility

5. **7-Day vs 30-Day Divergence**: Many tokens show significantly higher 7-day APYs compared to 30-day APYs, suggesting recent price appreciation.

### Data Quality Notes

- APYs are calculated based on price per share changes
- Extreme values may indicate:
  - Low liquidity
  - Recent market events
  - Data anomalies
- Negative APYs for some tokens warrant further investigation

### Recommendations

1. **For coveUSD Integration**: With a 4.03% APY, coveUSD performs moderately well among yield-bearing vaults but is not in the top tier.

2. **Risk Assessment**: High APYs on BTC wrappers are likely due to underlying asset appreciation rather than yield generation.

3. **Further Analysis**: 
   - Investigate negative APYs for liquid staking tokens
   - Compare vault APYs with their advertised rates
   - Analyze the discrepancy between 7-day and 30-day APYs

### Technical Implementation

- Data source: API endpoint with 30-day price history
- Token info: Retrieved using Foundry cast with Flashbots RPC
- Analysis: Python with pandas, matplotlib, seaborn
- APY Calculation: `((final_price / initial_price) ^ (365.25 / days)) - 1) * 100`

### Files Generated

1. `token_apy_analysis.png` - Visualization dashboard
2. `token_apy_results.csv` - Raw APY calculations
3. `token_apy_results_enhanced.csv` - Enhanced with token metadata
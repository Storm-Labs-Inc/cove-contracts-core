import json
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
import numpy as np
from collections import defaultdict

# Load the data
with open('api_data.json', 'r') as f:
    raw_data = json.load(f)

# Extract the actual data array
data = raw_data['data']

# Extract price data
price_data = defaultdict(list)
timestamps = []

for entry in data:
    timestamp = entry['timestamp']
    timestamps.append(timestamp)
    
    for address, price in entry['snapshot']['prices'].items():
        # Convert from wei to regular units (divide by 10^18)
        price_normalized = int(price) / 10**18
        price_data[address].append({
            'timestamp': timestamp,
            'price': price_normalized
        })

# Create a DataFrame for each token
token_dfs = {}
for address, prices in price_data.items():
    df = pd.DataFrame(prices)
    df['datetime'] = pd.to_datetime(df['timestamp'], unit='s')
    df = df.sort_values('datetime')
    token_dfs[address] = df

# Calculate APYs for each token
apy_results = []

for address, df in token_dfs.items():
    if len(df) < 2:
        continue
    
    # Get the first and last prices
    first_price = df.iloc[0]['price']
    last_price = df.iloc[-1]['price']
    
    # Calculate time difference in years
    time_diff = (df.iloc[-1]['timestamp'] - df.iloc[0]['timestamp']) / (365.25 * 24 * 3600)
    
    # Calculate APY
    if first_price > 0 and time_diff > 0:
        # APY = ((final_value / initial_value) ^ (1 / time_in_years) - 1) * 100
        apy = ((last_price / first_price) ** (1 / time_diff) - 1) * 100
        
        # Calculate 7-day, 30-day APYs if we have enough data
        seven_day_apy = None
        thirty_day_apy = None
        
        # 7-day APY
        seven_days_ago = df.iloc[-1]['timestamp'] - 7 * 24 * 3600
        seven_day_data = df[df['timestamp'] >= seven_days_ago]
        if len(seven_day_data) >= 2:
            seven_day_return = (seven_day_data.iloc[-1]['price'] / seven_day_data.iloc[0]['price'] - 1)
            seven_day_apy = seven_day_return * 365.25 / 7 * 100
        
        # 30-day APY
        thirty_days_ago = df.iloc[-1]['timestamp'] - 30 * 24 * 3600
        thirty_day_data = df[df['timestamp'] >= thirty_days_ago]
        if len(thirty_day_data) >= 2:
            thirty_day_return = (thirty_day_data.iloc[-1]['price'] / thirty_day_data.iloc[0]['price'] - 1)
            thirty_day_apy = thirty_day_return * 365.25 / 30 * 100
        
        apy_results.append({
            'address': address,
            'first_price': first_price,
            'last_price': last_price,
            'apy': apy,
            'seven_day_apy': seven_day_apy,
            'thirty_day_apy': thirty_day_apy,
            'price_change_pct': ((last_price / first_price - 1) * 100)
        })

# Sort by APY
apy_results_sorted = sorted(apy_results, key=lambda x: x['apy'], reverse=True)

# Print results
print("Token APY Analysis (30-day data)")
print("=" * 80)
print(f"{'Address':<45} {'APY':>10} {'7d APY':>10} {'30d APY':>10} {'Change %':>10}")
print("-" * 80)

for result in apy_results_sorted[:20]:  # Top 20
    print(f"{result['address']:<45} {result['apy']:>9.2f}% {result['seven_day_apy'] or 0:>9.2f}% {result['thirty_day_apy'] or 0:>9.2f}% {result['price_change_pct']:>9.2f}%")

# Create visualizations
plt.style.use('seaborn-v0_8-darkgrid')
fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(16, 12))

# 1. Top 10 APYs bar chart
top_10 = apy_results_sorted[:10]
addresses = [r['address'][:8] + '...' for r in top_10]
apys = [r['apy'] for r in top_10]

ax1.bar(addresses, apys, color='skyblue', edgecolor='navy')
ax1.set_xlabel('Token Address (truncated)')
ax1.set_ylabel('APY (%)')
ax1.set_title('Top 10 Token APYs (30-day period)')
ax1.tick_params(axis='x', rotation=45)

# 2. Price trends for top 5 tokens
top_5_addresses = [r['address'] for r in apy_results_sorted[:5]]
for i, addr in enumerate(top_5_addresses):
    df = token_dfs[addr]
    ax2.plot(df['datetime'], df['price'], label=f"{addr[:8]}...", linewidth=2)

ax2.set_xlabel('Date')
ax2.set_ylabel('Price per Share')
ax2.set_title('Price Trends - Top 5 APY Tokens')
ax2.legend()
ax2.tick_params(axis='x', rotation=45)

# 3. APY distribution histogram
all_apys = [r['apy'] for r in apy_results if r['apy'] < 50]  # Filter out extreme outliers
ax3.hist(all_apys, bins=30, color='lightgreen', edgecolor='darkgreen', alpha=0.7)
ax3.set_xlabel('APY (%)')
ax3.set_ylabel('Number of Tokens')
ax3.set_title('Distribution of Token APYs')
ax3.axvline(np.mean(all_apys), color='red', linestyle='dashed', linewidth=2, label=f'Mean: {np.mean(all_apys):.2f}%')
ax3.legend()

# 4. 7-day vs 30-day APY comparison
seven_day_apys = [r['seven_day_apy'] for r in apy_results_sorted[:20] if r['seven_day_apy'] is not None]
thirty_day_apys = [r['thirty_day_apy'] for r in apy_results_sorted[:20] if r['thirty_day_apy'] is not None]
token_labels = [r['address'][:8] + '...' for r in apy_results_sorted[:20] if r['seven_day_apy'] is not None]

x = np.arange(len(token_labels))
width = 0.35

ax4.bar(x - width/2, seven_day_apys[:len(token_labels)], width, label='7-day APY', color='lightcoral')
ax4.bar(x + width/2, thirty_day_apys[:len(token_labels)], width, label='30-day APY', color='lightskyblue')

ax4.set_xlabel('Token Address (truncated)')
ax4.set_ylabel('APY (%)')
ax4.set_title('7-day vs 30-day APY Comparison')
ax4.set_xticks(x)
ax4.set_xticklabels(token_labels, rotation=45, ha='right')
ax4.legend()

plt.tight_layout()
plt.savefig('token_apy_analysis.png', dpi=300, bbox_inches='tight')
print(f"\nVisualization saved as 'token_apy_analysis.png'")

# Save detailed results to CSV
results_df = pd.DataFrame(apy_results_sorted)
results_df.to_csv('token_apy_results.csv', index=False)
print(f"Detailed results saved to 'token_apy_results.csv'")
import subprocess
import json
import pandas as pd
from concurrent.futures import ThreadPoolExecutor, as_completed

# Flashbots RPC URL
RPC_URL = "https://rpc.flashbots.net"

# Common token addresses from the data
TOKEN_INFO = {
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2": "WETH",
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48": "USDC",
    "0x6B175474E89094C44Da98b954EedeAC495271d0F": "DAI",
    "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599": "WBTC",
    "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3": "USDe",
    "0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E": "crvUSD",
}

# Load the APY results
df_results = pd.read_csv('token_apy_results.csv')

# Function to get token info using cast
def get_token_info(address):
    info = {"address": address, "known_name": TOKEN_INFO.get(address, "Unknown")}
    
    try:
        # Get name
        cmd_name = f"cast call {address} 'name()(string)' --rpc-url {RPC_URL}"
        result_name = subprocess.run(cmd_name, shell=True, capture_output=True, text=True)
        if result_name.returncode == 0 and result_name.stdout.strip():
            info["name"] = result_name.stdout.strip()
        else:
            info["name"] = "N/A"
    except:
        info["name"] = "Error"
    
    try:
        # Get symbol
        cmd_symbol = f"cast call {address} 'symbol()(string)' --rpc-url {RPC_URL}"
        result_symbol = subprocess.run(cmd_symbol, shell=True, capture_output=True, text=True)
        if result_symbol.returncode == 0 and result_symbol.stdout.strip():
            info["symbol"] = result_symbol.stdout.strip()
        else:
            info["symbol"] = "N/A"
    except:
        info["symbol"] = "Error"
    
    try:
        # Get decimals
        cmd_decimals = f"cast call {address} 'decimals()(uint8)' --rpc-url {RPC_URL}"
        result_decimals = subprocess.run(cmd_decimals, shell=True, capture_output=True, text=True)
        if result_decimals.returncode == 0 and result_decimals.stdout.strip():
            info["decimals"] = int(result_decimals.stdout.strip(), 0)
        else:
            info["decimals"] = 18
    except:
        info["decimals"] = 18
    
    # Check if it's an ERC4626 vault (has asset() function)
    try:
        cmd_asset = f"cast call {address} 'asset()(address)' --rpc-url {RPC_URL}"
        result_asset = subprocess.run(cmd_asset, shell=True, capture_output=True, text=True)
        if result_asset.returncode == 0 and result_asset.stdout.strip():
            info["is_vault"] = True
            info["underlying_asset"] = result_asset.stdout.strip()
        else:
            info["is_vault"] = False
    except:
        info["is_vault"] = False
    
    return info

# Get top 20 tokens
top_addresses = df_results.head(20)['address'].tolist()

print("Fetching token information using cast...")
print("=" * 80)

# Use thread pool for parallel execution
token_infos = []
with ThreadPoolExecutor(max_workers=5) as executor:
    future_to_address = {executor.submit(get_token_info, addr): addr for addr in top_addresses}
    
    for future in as_completed(future_to_address):
        address = future_to_address[future]
        try:
            info = future.result()
            token_infos.append(info)
        except Exception as e:
            print(f"Error fetching info for {address}: {e}")

# Sort by original order
token_infos = sorted(token_infos, key=lambda x: top_addresses.index(x['address']))

# Print results
print(f"\n{'Address':<45} {'Symbol':<10} {'Name':<30} {'Vault':<7}")
print("-" * 92)

for info in token_infos:
    print(f"{info['address']:<45} {info.get('symbol', 'N/A'):<10} {info.get('name', 'N/A'):<30} {'Yes' if info.get('is_vault', False) else 'No':<7}")

# Merge with APY data and save enhanced results
enhanced_results = []
for index, row in df_results.iterrows():
    token_data = next((item for item in token_infos if item['address'] == row['address']), {})
    enhanced_row = row.to_dict()
    enhanced_row.update({
        'token_symbol': token_data.get('symbol', 'Unknown'),
        'token_name': token_data.get('name', 'Unknown'),
        'is_vault': token_data.get('is_vault', False),
        'decimals': token_data.get('decimals', 18)
    })
    enhanced_results.append(enhanced_row)

# Save enhanced results
enhanced_df = pd.DataFrame(enhanced_results)
enhanced_df.to_csv('token_apy_results_enhanced.csv', index=False)
print(f"\nEnhanced results saved to 'token_apy_results_enhanced.csv'")
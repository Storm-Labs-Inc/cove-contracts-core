import json
import os
import logging
import copy
import re
import urllib.request

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)

# Preferred naming includes block + timestamp; fallback supports legacy timestamp-only files.
BASE_STATE_FILE = "00_InitialState_22442301_1746749783.json"
DEFAULT_FORK_BLOCK_NUMBER = 22_442_301
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
ZERO_B256 = "0x" + "0" * 64


def load_json_file(file_path):
    with open(file_path, "r") as file:
        return json.load(file)


def save_json_file(data, file_path):
    with open(file_path, "w") as file:
        json.dump(data, file, indent=2)
        file.write("\n")

def parse_int(value):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        if value.startswith("0x"):
            return int(value, 16)
        return int(value)
    return None


def extract_numbers_from_filename(filename):
    match = re.search(r"_(\d+)_(\d+)\.json$", filename)
    if match:
        return int(match.group(1)), int(match.group(2))
    match = re.search(r"_(\d+)\.json$", filename)
    if match:
        return None, int(match.group(1))
    return None, None


def get_fork_block_number():
    for key in ("FORK_BLOCK_NUMBER", "STATE_FORK_BLOCK_NUMBER", "DUMP_STATE_FORK_BLOCK"):
        value = os.getenv(key)
        if value:
            return int(value)
    return DEFAULT_FORK_BLOCK_NUMBER


def fetch_block_env_from_rpc(rpc_url, block_number):
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_getBlockByNumber",
        "params": [hex(block_number), False],
    }
    req = urllib.request.Request(
        rpc_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        data = json.loads(response.read().decode("utf-8"))
    block = data.get("result")
    if not block:
        raise RuntimeError(f"RPC returned no block for {block_number}")

    return {
        "number": block.get("number", hex(block_number)),
        "beneficiary": block.get("miner", ZERO_ADDRESS),
        "timestamp": block.get("timestamp"),
        "gas_limit": block.get("gasLimit"),
        "basefee": block.get("baseFeePerGas", "0x0"),
        "difficulty": block.get("difficulty", "0x0"),
        "prevrandao": block.get("mixHash", ZERO_B256),
        "blob_excess_gas_and_price": {
            "excess_blob_gas": parse_int(block.get("excessBlobGas", 0)) or 0,
            "blob_gasprice": 1,
        },
    }


def load_block_template(block_number):
    template_path = os.getenv("BLOCK_ENV_JSON")
    if template_path and os.path.exists(template_path):
        logging.info(f"Loading block template from {template_path}")
        return load_json_file(template_path)

    rpc_url = os.getenv("MAINNET_RPC_URL")
    if rpc_url:
        try:
            logging.info(
                f"Fetching block env from RPC at block {block_number}"
            )
            return fetch_block_env_from_rpc(rpc_url, block_number)
        except Exception as exc:
            logging.warning(f"RPC block fetch failed, using defaults: {exc}")

    return {
        "number": block_number,
        "beneficiary": ZERO_ADDRESS,
        "timestamp": 1,
        "gas_limit": 30_000_000,
        "basefee": 0,
        "difficulty": 0,
        "prevrandao": ZERO_B256,
        "blob_excess_gas_and_price": {"excess_blob_gas": 0, "blob_gasprice": 1},
    }


def normalize_account_record(account):
    nonce = account.get("nonce")
    if isinstance(nonce, str) and nonce.startswith("0x"):
        account["nonce"] = int(nonce, 16)
    elif nonce is None:
        account["nonce"] = 0

    if account.get("balance") is None:
        account["balance"] = "0x0"

    code = account.get("code")
    if code is None:
        account["code"] = "0x"

    storage = account.get("storage")
    if storage is None:
        account["storage"] = {}

    return account


def normalize_accounts(state):
    accounts = state.get("accounts", state)
    if not isinstance(accounts, dict):
        return {}

    for addr, account in accounts.items():
        if isinstance(account, dict):
            accounts[addr] = normalize_account_record(account)
    return accounts


def merge_states(base_state, other_state):
    """Deep merge other_state into base_state for account maps"""
    if not isinstance(base_state, dict) or not isinstance(other_state, dict):
        return copy.deepcopy(other_state)

    merged = copy.deepcopy(base_state)

    for key, value in other_state.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = merge_states(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)

    return merged


def ensure_state_wrapper(state, block_template, block_number, timestamp):
    if "accounts" not in state:
        state = {"accounts": state}

    state["accounts"] = normalize_accounts(state)

    block = copy.deepcopy(state.get("block") or block_template)
    if block_number is not None:
        block["number"] = block_number
    if timestamp is not None:
        block["timestamp"] = timestamp
    state["block"] = block

    best_block_number = state.get("best_block_number")
    if best_block_number is None:
        best_block_number = parse_int(block.get("number"))
    if best_block_number is None:
        best_block_number = block_number or get_fork_block_number()
    state["best_block_number"] = best_block_number

    state.setdefault("blocks", [])
    state.setdefault("transactions", [])

    return state


def process_folder(folder_path):
    base_file = BASE_STATE_FILE
    base_file_path = os.path.join(folder_path, base_file)
    if not os.path.exists(base_file_path):
        for candidate in sorted(os.listdir(folder_path)):
            if candidate.startswith("00_InitialState_") and candidate.endswith(".json"):
                base_file = candidate
                base_file_path = os.path.join(folder_path, base_file)
                break

    if not os.path.exists(base_file_path):
        logging.error(f"Base file {base_file} not found in {folder_path}")
        return

    base_block_number, base_timestamp = extract_numbers_from_filename(base_file)
    if base_block_number is None:
        base_block_number = get_fork_block_number()
    block_template = load_block_template(base_block_number)

    # Load and process base state
    logging.info(f"Loading base state from {base_file}")
    base_state = load_json_file(base_file_path)
    base_state = ensure_state_wrapper(
        base_state, block_template, base_block_number, base_timestamp
    )

    # Save the formatted base state back
    save_json_file(base_state, base_file_path)
    logging.info(f"Updated base file {base_file} with formatted JSON")

    # Process all other JSON files
    for filename in os.listdir(folder_path):
        if not filename.endswith(".json") or filename == base_file:
            continue

        file_path = os.path.join(folder_path, filename)
        logging.info(f"Processing {filename}")

        # Load and process current state
        current_state = load_json_file(file_path)
        current_block_number, current_timestamp = extract_numbers_from_filename(filename)
        if current_block_number is None:
            current_block_number = base_block_number
        current_state = ensure_state_wrapper(
            current_state, block_template, current_block_number, current_timestamp
        )

        # Merge account maps and apply per-file block timestamp
        merged_state = copy.deepcopy(base_state)
        merged_state["accounts"] = merge_states(
            base_state.get("accounts", {}), current_state.get("accounts", {})
        )
        merged_state["block"] = current_state.get("block", base_state.get("block"))
        merged_state["best_block_number"] = current_state.get(
            "best_block_number", base_state.get("best_block_number")
        )
        current_blocks = current_state.get("blocks") or []
        current_txs = current_state.get("transactions") or []
        if current_blocks:
            merged_state["blocks"] = copy.deepcopy(current_blocks)
        else:
            merged_state["blocks"] = copy.deepcopy(base_state.get("blocks", []))
        if current_txs:
            merged_state["transactions"] = copy.deepcopy(current_txs)
        else:
            merged_state["transactions"] = copy.deepcopy(base_state.get("transactions", []))

        # Save merged state back to original file
        save_json_file(merged_state, file_path)
        logging.info(f"Updated {filename} with merged state")

    logging.info("Finished processing all files")


# Process files in dumpStates directory
process_folder("./dumpStates")

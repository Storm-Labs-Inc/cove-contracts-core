import json
import os
import logging
import copy

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)

BASE_STATE_FILE = "00_InitialState_1741972355.json"


def load_json_file(file_path):
    with open(file_path, "r") as file:
        return json.load(file)


def save_json_file(data, file_path):
    with open(file_path, "w") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


def convert_hex_nonces(data):
    """Convert hex nonces to decimal in the data"""
    if isinstance(data, dict):
        for key, value in data.items():
            if key == "nonce" and isinstance(value, str) and value.startswith("0x"):
                data[key] = int(value, 16)
            elif isinstance(value, (dict, list)):
                convert_hex_nonces(value)
    elif isinstance(data, list):
        for item in data:
            convert_hex_nonces(item)
    return data


def merge_states(base_state, other_state):
    """Deep merge other_state into base_state"""
    if not isinstance(base_state, dict) or not isinstance(other_state, dict):
        return other_state

    merged = copy.deepcopy(base_state)

    for key, value in other_state.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = merge_states(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)

    return merged


def process_folder(folder_path):
    base_file = BASE_STATE_FILE
    base_file_path = os.path.join(folder_path, base_file)

    if not os.path.exists(base_file_path):
        logging.error(f"Base file {base_file} not found in {folder_path}")
        return

    # Load and process base state
    logging.info(f"Loading base state from {base_file}")
    base_state = load_json_file(base_file_path)
    base_state = convert_hex_nonces(base_state)

    # Ensure base state has 'accounts' structure
    if "accounts" not in base_state:
        base_state = {"accounts": base_state}

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
        current_state = convert_hex_nonces(current_state)

        # Ensure current state has 'accounts' structure
        if "accounts" not in current_state:
            current_state = {"accounts": current_state}

        # Merge states
        merged_state = merge_states(base_state, current_state)

        # Save merged state back to original file
        save_json_file(merged_state, file_path)
        logging.info(f"Updated {filename} with merged state")

    logging.info("Finished processing all files")


# Process files in dumpStates directory
process_folder("./dumpStates")

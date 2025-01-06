import json
import os
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


def process_json_file(file_path):
    # Load the JSON data
    with open(file_path, "r") as file:
        data = json.load(file)

    # Check if any hex nonces exist that need converting
    needs_processing = False
    # Check if data has "accounts" key
    if "accounts" not in data:
        logging.warning("File %s does not have 'accounts' key, skipping...", file_path)
        needs_processing = True

    for account in data.get("accounts", {}).values():
        nonce = account.get("nonce", "")
        if isinstance(nonce, str) and nonce.startswith("0x"):
            needs_processing = True
            break

    if not needs_processing:
        logging.info("File %s already processed, skipping...", file_path)
        return

    # Convert hex nonce to decimal
    for account in data.values():
        nonce = account.get("nonce", "")
        if isinstance(nonce, str) and nonce.startswith("0x"):
            old_nonce = nonce
            account["nonce"] = int(nonce, 16)
            logging.debug("Converted nonce from %s to %s", old_nonce, account["nonce"])

    # Add the data contents as values of accounts key
    new_data = {"accounts": data}
    # Save the updated JSON data
    with open(file_path, "w") as file:
        json.dump(new_data, file, indent=4)
    logging.info("Successfully processed %s", file_path)


def process_folder(folder_path):
    logging.info("Processing JSON files in %s", folder_path)
    # Process all JSON files in the folder
    for filename in os.listdir(folder_path):
        if filename.endswith(".json"):
            file_path = os.path.join(folder_path, filename)
            process_json_file(file_path)
    logging.info("Finished processing all files")


# Process files in current directory by default
process_folder("./dumpStates")

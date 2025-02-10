import json
import os
from pathlib import Path


def convert_to_ts_format(abi_data):
    """Convert JSON ABI to TypeScript format string."""
    # Convert the ABI to a string with proper formatting
    abi_str = json.dumps(abi_data, indent=2)

    # Remove quotes from property names
    abi_str = abi_str.replace('"name":', "name:")
    abi_str = abi_str.replace('"type":', "type:")
    abi_str = abi_str.replace('"inputs":', "inputs:")
    abi_str = abi_str.replace('"outputs":', "outputs:")
    abi_str = abi_str.replace('"stateMutability":', "stateMutability:")
    abi_str = abi_str.replace('"internalType":', "internalType:")
    abi_str = abi_str.replace('"anonymous":', "anonymous:")
    abi_str = abi_str.replace('"indexed":', "indexed:")

    # Add export statement
    return f"export const abi = {abi_str};"


def is_src_contract(data):
    """Check if the contract is from src/ directory using metadata."""
    try:
        raw_metadata = json.loads(data.get("rawMetadata", "{}"))
        compilation_target = raw_metadata.get("settings", {}).get(
            "compilationTarget", {}
        )
        return any(key.startswith("src/") for key in compilation_target.keys())
    except:
        return False


def extract_abis():
    # Get the out directory path
    out_dir = Path("out")

    # Create abis directory if it doesn't exist
    abis_dir = Path("abis")
    abis_dir.mkdir(exist_ok=True)

    # Walk through all directories in out/
    for root, dirs, files in os.walk(out_dir):
        for file in files:
            if not file.endswith(".json"):
                continue

            file_path = Path(root) / file

            try:
                with open(file_path) as f:
                    data = json.load(f)

                if not is_src_contract(data):
                    continue

                if "abi" not in data:
                    continue

                if not data["abi"]:
                    continue

                contract_name = file.replace(".json", "")

                # Save JSON ABI
                json_path = abis_dir / f"{contract_name}.abi.json"
                with open(json_path, "w") as f:
                    json.dump(data["abi"], f, indent=2)

                # Save TypeScript ABI
                ts_path = abis_dir / f"{contract_name}.abi.ts"
                with open(ts_path, "w") as f:
                    f.write(convert_to_ts_format(data["abi"]))

                print(f"Processed {contract_name}")

            except Exception as e:
                print(f"Error processing {file}: {e}")


if __name__ == "__main__":
    extract_abis()

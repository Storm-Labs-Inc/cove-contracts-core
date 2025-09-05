#!/usr/bin/env python3
"""
List deployment addresses by environment.
Reads JSON files under deployments/1 and prints tables per environment.
Environment is
  - Production: filename starts with "Production_"
  - Staging: filename starts with "Staging_"
  - Test: anything else
"""

import json
import os
import sys
from collections import defaultdict

# Determine project root (directory containing this script and deployments folder)
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
DEPLOY_DIR = os.path.join(ROOT_DIR, "deployments", "1")

if not os.path.isdir(DEPLOY_DIR):
    sys.exit(f"Deployment directory not found: {DEPLOY_DIR}")


def classify_env(filename: str) -> str:
    """Classify environment based on filename prefix."""
    if filename.startswith("Production_"):
        return "Production"
    if filename.startswith("Staging_"):
        return "Staging"
    return "Test"


def strip_prefix(contract_filename: str, env: str) -> str:
    """Remove environment prefix from contract filename (sans extension)."""
    name = os.path.splitext(contract_filename)[0]
    prefixes = {
        "Production": "Production_",
        "Staging": "Staging_",
    }
    prefix = prefixes.get(env, "")
    if prefix and name.startswith(prefix):
        return name[len(prefix) :]
    return name


def collect_addresses() -> dict[str, list[tuple[str, str]]]:
    env_map: dict[str, list[tuple[str, str]]] = defaultdict(list)

    for entry in os.scandir(DEPLOY_DIR):
        if not entry.name.endswith(".json") or not entry.is_file():
            continue
        env = classify_env(entry.name)
        try:
            with open(entry.path, "r") as fp:
                data = json.load(fp)
                address = data.get("address")
        except (json.JSONDecodeError, OSError):
            continue
        if not address:
            continue
        contract = strip_prefix(entry.name, env)
        env_map[env].append((contract, address))
    # Sort each list by contract name for deterministic output
    for lst in env_map.values():
        lst.sort(key=lambda x: x[0].lower())
    return env_map


def format_table(rows: list[tuple[str, str]]) -> str:
    if not rows:
        return ""
    contract_width = max(len("Contract"), *(len(r[0]) for r in rows))
    address_width = max(len("Address"), *(len(r[1]) for r in rows))

    border = "+" + "-" * (contract_width + 2) + "+" + "-" * (address_width + 2) + "+"
    header = f"| {'Contract'.ljust(contract_width)} | {'Address'.ljust(address_width)} |"

    lines = [border, header, border]
    for contract, addr in rows:
        lines.append(f"| {contract.ljust(contract_width)} | {addr.ljust(address_width)} |")
    lines.append(border)
    return "\n".join(lines)


def main() -> None:
    env_map = collect_addresses()

    if not env_map:
        print("No deployment files found.")
        return

    for env in ("Production", "Staging", "Test"):
        rows = env_map.get(env)
        if not rows:
            continue
        print(f"{env}:\n")
        print(format_table(rows))
        print()


if __name__ == "__main__":
    main() 
#!/usr/bin/env python3
"""Divide token amount columns in final-balances.csv by 1e18."""

from __future__ import annotations

import csv
from decimal import Decimal, InvalidOperation, getcontext
from pathlib import Path


SCALE = Decimal("1e18")
AMOUNT_COLUMNS = {
    "wallet_balance",
    "sablier_claimable",
    "gauge_claimable",
    "auction_claimable",
    "echo_balance",
    "total_calculated_cove_balance",
}


def format_decimal(value: Decimal) -> str:
    if value == 0:
        return "0"
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def adjust_value(raw: str) -> str:
    try:
        value = Decimal(raw)
    except (InvalidOperation, TypeError):
        return raw

    adjusted = value / SCALE
    return format_decimal(adjusted)


def main() -> None:
    getcontext().prec = 80

    source = Path("script/oneshot/final-balances.csv")
    target = Path("script/oneshot/final-balances-decimals-adjusted.csv")

    with source.open(newline="") as infile:
        reader = csv.DictReader(infile)
        rows = []
        for row in reader:
            for column in AMOUNT_COLUMNS:
                if column in row:
                    row[column] = adjust_value(row[column])
            rows.append(row)

    with target.open("w", newline="") as outfile:
        writer = csv.DictWriter(outfile, fieldnames=reader.fieldnames)
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()

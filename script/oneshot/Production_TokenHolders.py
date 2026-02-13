#!/usr/bin/env python3
# Summary of work (end-to-end pipeline):
# 1) Fetch tokenholder balances from Etherscan v2 using API_KEY_ETHERSCAN and write tokenholders.csv.
# 2) Keep all fetched holders in tokenholders.csv (no hidden/blacklist section split).
# 3) (Optional) Verify tokenholder balances against mainnet RPC with cast and write tokenholders.cast-check.csv.
# 4) Discover reward gauges from CoveYearnGaugeFactory, discover gauge users from mint Transfer events,
#    then sum claimableReward for those users.
# 5) Scan Sablier V2 Lockup Linear logs from block 19594522 and sum streamedAmountOf per recipient.
# 6) Calculate claimable auction sales from `AUCTION_CONTRACT`.
# 7) Classify addresses as EOAs vs contracts via eth_getCode.
# 8) If a block is provided, recompute wallet balances at that block and write tokenholders.block-<block>.csv.
# 9) Write final-balances.csv with per-address columns:
#    is_contract, is_eligible, wallet_balance, sablier_claimable, gauge_claimable,
#    auction_claimable, total_calculated_cove_balance.

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from decimal import Decimal, getcontext
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlencode

ADDRESS_RE = re.compile(r"^0x[a-fA-F0-9]{40}$")
ZERO_ADDR = "0x0000000000000000000000000000000000000000"
COVE_TOKEN_ADDRESS = "0x32fb7D6E0cBEb9433772689aA4647828Cc7cbBA8"
DEFAULT_SABLIER_FROM_BLOCK = 19594522
DEFAULT_TOKEN_SNAPSHOT_BLOCK = 24448971
DEFAULT_HOLDERS_FILE = "tokenholders.csv"
DEFAULT_VERIFY_FILE = "tokenholders.cast-check.csv"
DEFAULT_FINAL_FILE = "final-balances.csv"
COVE_YEARN_GAUGE_FACTORY = "0x842b22Eb2A1C1c54344eDdbE6959F787c2d15844"
AUCTION_CONTRACT = "0x2f3715F710076Cfdb5AA872Bc8a4b965a07c3A08"
TOKEN_DECIMALS = Decimal("1000000000000000000")
DEFAULT_AUCTION_VESTING_DURATION = 0


# Parse CLI args for the unified pipeline.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Cove balances pipeline")
    parser.add_argument("--contract", default=COVE_TOKEN_ADDRESS)
    parser.add_argument("--rpc-url", default=None, help="RPC URL (defaults to MAINNET_RPC_URL)")
    parser.add_argument("--block", default=DEFAULT_TOKEN_SNAPSHOT_BLOCK, help="Block number for pinned calculations")
    parser.add_argument(
        "--from-block",
        default=str(DEFAULT_SABLIER_FROM_BLOCK),
        help=f"Start block for Sablier log scan (default: {DEFAULT_SABLIER_FROM_BLOCK})",
    )
    parser.add_argument("--offset", default="1000", help="Etherscan pagination offset")
    parser.add_argument("--blacklist", default="blacklist.csv")
    parser.add_argument("--skip-fetch", action="store_true", help="Skip Etherscan tokenholders fetch")
    parser.add_argument("--skip-verify", action="store_true", help="Skip cast verification step")
    parser.add_argument(
        "--raw-final-balances",
        action="store_true",
        help="Write final balances using raw integer token amounts (18-decimal format)",
    )
    parser.add_argument(
        "--auction-vesting-duration",
        type=int,
        default=DEFAULT_AUCTION_VESTING_DURATION,
        help="Auction vesting duration in seconds for claimable auction sales",
    )
    parser.add_argument("--jobs", type=int, default=None, help="Concurrency for RPC calls")
    return parser.parse_args()


# Call Etherscan v2 API with query params.
def etherscan_get(params: dict) -> dict:
    url = "https://api.etherscan.io/v2/api?" + urlencode(params)
    with urllib.request.urlopen(url) as resp:
        return json.loads(resp.read().decode())


# Read blacklist.csv (comma-separated addresses) into a set.
def load_blacklist(path: Path) -> set[str]:
    if not path.exists():
        return set()
    raw = path.read_text().strip()
    addrs = [a.strip().lower() for a in raw.split(",") if a.strip()]
    return {a for a in addrs if ADDRESS_RE.match(a)}


# Fetch all tokenholders via Etherscan and write to CSV.
def fetch_tokenholders(
    api_key: str,
    contract: str,
    offset: str,
    out_path: Path,
    blacklist: set[str],
) -> tuple[int, int]:
    base_params = {
        "chainid": 1,
        "module": "token",
        "action": "tokenholderlist",
        "contractaddress": contract,
        "apikey": api_key,
        "offset": offset,
    }

    page = 1
    rows: list[tuple[str, str]] = []
    blacklisted_count = 0

    while True:
        params = dict(base_params)
        params["page"] = str(page)
        data = etherscan_get(params)
        result = data.get("result")
        if not isinstance(result, list):
            if data.get("message") == "No records found" or data.get("result") == "No records found":
                break
            raise RuntimeError(f"Unexpected response: {data}")
        if not result:
            break

        for item in result:
            addr = item.get("TokenHolderAddress")
            bal = item.get("TokenHolderQuantity")
            if not addr or bal is None:
                continue
            rows.append((addr, bal))
            if addr.lower() in blacklist:
                blacklisted_count += 1

        if len(result) < int(offset):
            break
        page += 1

    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "token_balance"])
        writer.writerows(rows)
    return len(rows), blacklisted_count


# Load tokenholder addresses from CSV, ignoring non-address rows.
def load_tokenholder_addresses(path: Path) -> list[str]:
    addrs = []
    seen = set()
    with path.open(newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row:
                continue
            addr = (row[0] or "").strip().lower()
            if not (addr.startswith("0x") and len(addr) == 42):
                continue
            if addr not in seen:
                seen.add(addr)
                addrs.append(addr)
    return addrs


# Load balances from tokenholders.csv for a subset of addresses.
def load_wallet_balances_from_csv(path: Path, addresses: set[str]) -> dict[str, int]:
    balances: dict[str, int] = {}
    with path.open(newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row:
                continue
            addr = (row[0] or "").strip().lower()
            if addr not in addresses:
                continue
            try:
                balances[addr] = int(row[1])
            except Exception:
                continue
    return balances


# Run a cast command and return (ok, output).
def run_cast(cmd: list[str]) -> tuple[bool, str]:
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        return False, proc.stderr.strip() or proc.stdout.strip()
    return True, proc.stdout.strip()


# Compute a function selector from a signature using cast keccak.
def function_selector(signature: str) -> str:
    return "0x" + subprocess.check_output(["cast", "keccak", signature], text=True).strip().replace("0x", "")[:8]


# Compute a full keccak hash for event topics.
def event_topic(signature: str) -> str:
    return "0x" + subprocess.check_output(["cast", "keccak", signature], text=True).strip().replace("0x", "")


# Generic JSON-RPC call helper.
def rpc_call(rpc_url: str, method: str, params: list) -> dict:
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(rpc_url, data=payload, headers={"Content-Type": "application/json"})
    backoff = 0.5
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as err:
            if err.code == 429 and attempt < 5:
                time.sleep(backoff)
                backoff *= 2
                continue
            raise RuntimeError(f"HTTPError {err.code}: {err.reason}")


# Get latest block number from the RPC.
def get_latest_block(rpc_url: str) -> int:
    res = rpc_call(rpc_url, "eth_blockNumber", [])
    if "error" in res:
        raise RuntimeError(res["error"])
    return int(res["result"], 16)


def get_block_timestamp(rpc_url: str, block: str | int) -> int:
    block_id = hex(int(block)) if isinstance(block, int) else block
    res = rpc_call(rpc_url, "eth_getBlockByNumber", [block_id, False])
    if "error" in res:
        raise RuntimeError(res["error"])
    block_data = res.get("result")
    if not block_data or "timestamp" not in block_data:
        raise RuntimeError(f"Unable to load block data for {block}")
    return int(block_data["timestamp"], 16)


def get_block_before_timestamp(rpc_url: str, timestamp: int) -> int:
    high = get_latest_block(rpc_url)
    low = 0
    while low < high:
        mid = (low + high + 1) // 2
        mid_ts = get_block_timestamp(rpc_url, mid)
        if mid_ts <= timestamp:
            low = mid
        else:
            high = mid - 1
    return low


# Perform eth_call and return raw hex result.
def eth_call_raw(rpc_url: str, to: str, data: str, block: str | None) -> str:
    block_tag = hex(int(block)) if block is not None else "latest"
    res = rpc_call(rpc_url, "eth_call", [{"to": to, "data": data}, block_tag])
    if "error" in res:
        raise RuntimeError(res["error"])
    return res["result"]


# Perform eth_call and return integer result.
def eth_call(rpc_url: str, to: str, data: str, block: str | None) -> int:
    return int(eth_call_raw(rpc_url, to, data, block), 16)


# Check if an address is a contract using eth_getCode.
def is_contract(rpc_url: str, address: str, block: str | None) -> bool:
    block_tag = hex(int(block)) if block is not None else "latest"
    res = rpc_call(rpc_url, "eth_getCode", [address, block_tag])
    if "error" in res:
        raise RuntimeError(res["error"])
    return res["result"] not in ("0x", "0x0")


# Classify addresses and return a map address -> is_contract.
def classify_addresses(rpc_url: str, addresses: list[str], block: str | None, jobs: int) -> dict[str, bool]:
    out: dict[str, bool] = {}

    def check(addr: str) -> tuple[str, bool]:
        return addr, is_contract(rpc_url, addr, block)

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futures = {ex.submit(check, addr): addr for addr in addresses}
        for fut in as_completed(futures):
            addr, is_ctr = fut.result()
            out[addr] = is_ctr

    return out


# Discover reward gauges CoveYearnGaugeFactory.
def get_reward_gauges(rpc_url: str, block: str | None) -> list[str]:
    gauges: set[str] = set()

    factory_addr = COVE_YEARN_GAUGE_FACTORY

    num_sel = function_selector("numOfSupportedYearnGauges()")
    supported_sel = function_selector("supportedYearnGauges(uint256)")
    info_sel = function_selector("getGaugeInfo(address)")

    total = eth_call(rpc_url, factory_addr, num_sel, block)
    for i in range(total):
        data = supported_sel + i.to_bytes(32, "big").hex()
        yearn_gauge_hex = eth_call_raw(rpc_url, factory_addr, data, block)
        yearn_gauge = "0x" + yearn_gauge_hex[-40:]
        data = info_sel + yearn_gauge.lower().replace("0x", "").rjust(64, "0")
        info_hex = eth_call_raw(rpc_url, factory_addr, data, block)
        payload = info_hex[2:]
        if len(payload) < 64 * 7:
            continue
        slots = [payload[i : i + 64] for i in range(0, 64 * 7, 64)]
        auto_gauge = "0x" + slots[5][-40:]
        non_auto_gauge = "0x" + slots[6][-40:]
        if auto_gauge.lower() != ZERO_ADDR:
            gauges.add(auto_gauge.lower())
        if non_auto_gauge.lower() != ZERO_ADDR:
            gauges.add(non_auto_gauge.lower())

    return sorted(gauges)


# Scan Sablier logs for COVE streams and return (stream_id, recipient) pairs.
def get_sablier_streams_for_asset(
    rpc_url: str,
    lockup_addr: str,
    token_addr: str,
    from_block: int,
    to_block: int,
) -> list[tuple[int, str]]:
    sig = "CreateLockupLinearStream(uint256,address,address,address,(uint128,uint128,uint128),address,bool,bool,(uint40,uint40,uint40),address)"
    topic0 = event_topic(sig)
    asset_topic = "0x" + token_addr.lower().replace("0x", "").rjust(64, "0")

    streams: list[tuple[int, str]] = []
    step = 2000
    cursor = max(0, from_block)
    while cursor <= to_block:
        end_block = min(cursor + step - 1, to_block)
        params = [
            {
                "fromBlock": hex(cursor),
                "toBlock": hex(end_block),
                "address": lockup_addr,
                "topics": [topic0, None, None, asset_topic],
            }
        ]
        try:
            res = rpc_call(rpc_url, "eth_getLogs", params)
        except RuntimeError:
            if step > 500:
                step = max(500, step // 2)
                continue
            raise
        if "error" in res:
            if step > 500:
                step = max(500, step // 2)
                continue
            raise RuntimeError(res["error"])

        for log in res.get("result", []):
            data = log.get("data", "")
            if not data.startswith("0x") or len(data) < 66:
                continue
            stream_id = int(data[2:66], 16)
            topics = log.get("topics", [])
            if len(topics) < 3:
                continue
            recipient = "0x" + topics[2][-40:]
            streams.append((stream_id, recipient.lower()))

        cursor = end_block + 1

    return streams


# Compute total streamed (vested) balances per recipient from Sablier streams.
def get_vesting_balances(
    rpc_url: str,
    lockup_addr: str,
    token_addr: str,
    block: str | None,
    from_block: int,
    streamed_selector: str,
) -> dict[str, int]:
    balances: dict[str, int] = {}
    to_block = int(block) if block is not None else get_latest_block(rpc_url)
    streams = get_sablier_streams_for_asset(rpc_url, lockup_addr, token_addr, from_block, to_block)

    for stream_id, recipient in streams:
        try:
            data = streamed_selector + stream_id.to_bytes(32, "big").hex()
            streamed = eth_call(rpc_url, lockup_addr, data, block)
        except Exception:
            continue
        balances[recipient] = balances.get(recipient, 0) + streamed

    return balances


def get_auction_unclaimed(
    rpc_url: str,
    auction_addr: str,
    addresses: list[str],
    block: str | None,
    vesting_duration: int,
    jobs: int,
) -> tuple[dict[str, int], dict[str, int]]:
    end_time_sel = function_selector("endTime()")
    total_sub_sel = function_selector("totalSubscriptions()")
    total_proj_sel = function_selector("totalProjectTokenAmount()")
    floor_sel = function_selector("floorQuoteAmount()")
    sub_sel = function_selector("subscriptions(address)")

    auction_end_ts = eth_call(rpc_url, auction_addr, end_time_sel, block)
    total_subs = eth_call(rpc_url, auction_addr, total_sub_sel, block)
    total_proj = eth_call(rpc_url, auction_addr, total_proj_sel, block)
    floor_quote = eth_call(rpc_url, auction_addr, floor_sel, block)

    auction_end_block = get_block_before_timestamp(rpc_url, auction_end_ts)
    snapshot_block = int(block) if block is not None else get_latest_block(rpc_url)
    snapshot_ts = get_block_timestamp(rpc_url, snapshot_block)

    denom = max(total_subs, floor_quote)
    vesting_duration_bi = max(0, vesting_duration)

    def fetch_sub_at(block_tag: str | int, addr: str) -> int:
        data = sub_sel + addr.replace("0x", "").rjust(64, "0")
        return eth_call(rpc_url, auction_addr, data, str(block_tag))

    subs_end: dict[str, int] = {}
    subs_snap: dict[str, int] = {}

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futs_end = {ex.submit(fetch_sub_at, auction_end_block, addr): addr for addr in addresses}
        for fut in as_completed(futs_end):
            addr = futs_end[fut]
            subs_end[addr] = fut.result()

        futs_snap = {ex.submit(fetch_sub_at, snapshot_block, addr): addr for addr in addresses}
        for fut in as_completed(futs_snap):
            addr = futs_snap[fut]
            subs_snap[addr] = fut.result()

    owed: dict[str, int] = {}
    for addr in addresses:
        sub_end = subs_end.get(addr, 0)
        if sub_end == 0:
            continue
        remaining = subs_snap.get(addr, 0)
        max_vested = (sub_end * total_proj) // denom if denom > 0 else 0
        time_since = max(0, min(snapshot_ts - auction_end_ts, vesting_duration_bi))
        vested = (max_vested * time_since) // vesting_duration_bi if vesting_duration_bi > 0 else max_vested
        if remaining != 0:
            owed[addr] = owed.get(addr, 0) + vested

    return owed, {
        "auction_end_ts": auction_end_ts,
        "auction_end_block": auction_end_block,
        "total_subscriptions": total_subs,
        "total_project_tokens": total_proj,
        "floor_quote": floor_quote,
        "snapshot_ts": snapshot_ts,
    }


# Sum claimable reward balances across gauges for each address.
def get_gauge_claimable(
    rpc_url: str,
    gauges: list[str],
    token_addr: str,
    addresses: list[str],
    block: str | None,
    jobs: int,
    claimable_selector: str,
) -> dict[str, int]:
    def claimable_for_user(addr: str) -> tuple[str, int]:
        total = 0
        arg1 = addr.lower().replace("0x", "").rjust(64, "0")
        arg2 = token_addr.lower().replace("0x", "").rjust(64, "0")
        data = claimable_selector + arg1 + arg2
        for gauge in gauges:
            try:
                total += eth_call(rpc_url, gauge, data, block)
            except Exception:
                continue
        return addr, total

    results: dict[str, int] = {}
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futures = {ex.submit(claimable_for_user, addr): addr for addr in addresses}
        for fut in as_completed(futures):
            addr, total = fut.result()
            results[addr] = total

    return results


# Discover addresses that used gauges by scanning ERC4626 mint Transfer events (from zero address).
def get_gauge_users_from_mint_events(
    rpc_url: str,
    gauges: list[str],
    from_block: int,
    to_block: int,
) -> list[str]:
    if not gauges:
        return []

    transfer_topic = event_topic("Transfer(address,address,uint256)")
    zero_topic = "0x" + "0" * 64
    users: set[str] = set()

    step = 50000
    cursor = max(0, from_block)
    while cursor <= to_block:
        end_block = min(cursor + step - 1, to_block)
        params = [
            {
                "fromBlock": hex(cursor),
                "toBlock": hex(end_block),
                "address": gauges,
                "topics": [transfer_topic, zero_topic],
            }
        ]
        try:
            res = rpc_call(rpc_url, "eth_getLogs", params)
        except RuntimeError:
            if step > 500:
                step = max(500, step // 2)
                continue
            raise

        if "error" in res:
            if step > 500:
                step = max(500, step // 2)
                continue
            raise RuntimeError(res["error"])

        for log in res.get("result", []):
            topics = log.get("topics", [])
            if len(topics) < 3:
                continue
            recipient = ("0x" + topics[2][-40:]).lower()
            if ADDRESS_RE.match(recipient):
                users.add(recipient)

        cursor = end_block + 1

    return sorted(users)


# Verify balances via cast for an input CSV and write a report.
def verify_with_cast(rpc_url: str, token: str, in_csv: Path, out_csv: Path, block: str | None) -> None:
    ok, _ = run_cast(["cast", "--help"])
    if not ok:
        raise RuntimeError("cast not found in PATH")

    def cast_balance(addr: str) -> str:
        cmd = ["cast", "erc20-token", "balance", "--rpc-url", rpc_url]
        if block:
            cmd += ["--block", str(block)]
        cmd += [token, addr]
        out = subprocess.check_output(cmd, text=True).strip()
        return out.split()[0]

    rows = []
    with in_csv.open(newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row:
                continue
            addr = (row[0] or "").strip()
            if not ADDRESS_RE.match(addr):
                continue
            exp = row[1] if len(row) > 1 else ""
            try:
                onchain = cast_balance(addr)
                status = "OK" if exp == onchain else "MISMATCH"
            except Exception as e:
                onchain = ""
                status = f"ERROR: {e}"
            rows.append((addr, exp, onchain, status))

    with out_csv.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "expected_balance", "onchain_balance", "status"])
        for row in sorted(rows, key=lambda r: r[0].lower()):
            writer.writerow(row)


# Fetch ERC20 balances via eth_call for addresses at a specific block and write to CSV.
def fetch_wallet_balances_at_block(
    rpc_url: str,
    token: str,
    addresses: list[str],
    block: str,
    out_path: Path,
    jobs: int,
) -> dict[str, int]:
    selector = function_selector("balanceOf(address)")

    def fetch(addr: str) -> tuple[str, int]:
        data = selector + addr.replace("0x", "").rjust(64, "0")
        bal = eth_call(rpc_url, token, data, block)
        return addr, bal

    results: dict[str, int] = {}
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futures = {ex.submit(fetch, addr): addr for addr in addresses}
        for fut in as_completed(futures):
            addr, bal = fut.result()
            results[addr] = bal

    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "token_balance"])
        for addr, bal in sorted(results.items(), key=lambda r: r[1], reverse=True):
            writer.writerow([addr, bal])

    return results


# Write final balances CSV with an explicit per-column component breakdown.
def write_final_balances(
    addresses: list[str],
    is_contract_map: dict[str, bool],
    blacklist: set[str],
    wallet_balances: dict[str, int],
    sablier_claimable: dict[str, int],
    gauge_claimable: dict[str, int],
    auction_claimable: dict[str, int],
    decimal_adjust: bool,
    out_path: Path,
) -> None:
    getcontext().prec = 80
    decimals = TOKEN_DECIMALS if decimal_adjust else Decimal("1")

    def format_amount(raw: int) -> str:
        scaled = Decimal(raw) / decimals
        if scaled == 0:
            return "0"
        text = format(scaled, "f")
        if "." in text:
            text = text.rstrip("0").rstrip(".")
        return text

    rows = []
    for addr in addresses:
        wallet = wallet_balances.get(addr, 0)
        sablier = sablier_claimable.get(addr, 0)
        gauge = gauge_claimable.get(addr, 0)
        auction = auction_claimable.get(addr, 0)
        total = wallet + sablier + gauge + auction
        rows.append(
            (
                addr,
                "true" if is_contract_map.get(addr, False) else "false",
                "false" if addr in blacklist else "true",
                wallet,
                sablier,
                gauge,
                auction,
                total,
            )
        )

    rows.sort(key=lambda r: r[7], reverse=True)

    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "address",
                "is_contract",
                "is_eligible",
                "wallet_balance",
                "sablier_claimable",
                "gauge_claimable",
                "auction_claimable",
                "total_calculated_cove_balance",
            ]
        )
        for row in rows:
            writer.writerow(
                (
                    row[0],
                    row[1],
                    row[2],
                    format_amount(int(row[3])),
                    format_amount(int(row[4])),
                    format_amount(int(row[5])),
                    format_amount(int(row[6])),
                    format_amount(int(row[7])),
                )
            )


# Run the full pipeline end-to-end.
def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parent

    rpc_url = args.rpc_url or os.environ.get("MAINNET_RPC_URL")
    if not rpc_url:
        print("MAINNET_RPC_URL not set and --rpc-url not provided", file=sys.stderr)
        return 1

    api_key = os.environ.get("API_KEY_ETHERSCAN")
    if not api_key and not args.skip_fetch:
        print("API_KEY_ETHERSCAN not set (required for Etherscan fetch)", file=sys.stderr)
        return 1

    jobs = args.jobs or min(6, max(1, (os.cpu_count() or 2) // 2))

    holders_path = root / DEFAULT_HOLDERS_FILE
    verify_path = root / DEFAULT_VERIFY_FILE
    final_path = root / DEFAULT_FINAL_FILE
    blacklist = load_blacklist(root / args.blacklist)

    print(f"Contract: {args.contract}")
    if args.block:
        print(f"Pinned block: {args.block}")
    print(f"Sablier log scan from block: {args.from_block}")

    if not args.skip_fetch:
        print("Step 1: Fetch tokenholders from Etherscan")
        rows, black_rows = fetch_tokenholders(api_key, args.contract, args.offset, holders_path, blacklist)
        print(f"  Wrote {rows} holder rows ({black_rows} blacklisted by eligibility flag)")
    else:
        print("Step 1: Skipped tokenholder fetch")

    print("Step 2: Load tokenholder addresses")
    addresses = load_tokenholder_addresses(holders_path)
    print(f"  Loaded {len(addresses)} addresses")

    lockup_addr = "0xafb979d9afad1ad27c5eff4e27226e3ab9e5dcc9"
    streamed_selector = function_selector("streamedAmountOf(uint256)")
    claimable_selector = function_selector("claimableReward(address,address)")
    from_block = int(args.from_block)

    print("Step 3: Compute claimable vested balances from Sablier")
    sablier_claimable = get_vesting_balances(
        rpc_url,
        lockup_addr,
        args.contract,
        args.block,
        from_block,
        streamed_selector,
    )
    print(f"  Sablier recipients: {len(sablier_claimable)}")

    print("Step 4: Discover gauges and compute claimable rewards")
    gauges = get_reward_gauges(rpc_url, args.block)
    print(f"  Gauges discovered: {len(gauges)}")
    gauge_to_block = int(args.block) if args.block is not None else get_latest_block(rpc_url)
    gauge_users = get_gauge_users_from_mint_events(rpc_url, gauges, from_block, gauge_to_block)
    print(f"  Gauge users discovered from mint Transfer events: {len(gauge_users)}")
    gauge_claimable = get_gauge_claimable(
        rpc_url,
        gauges,
        args.contract,
        gauge_users,
        args.block,
        jobs,
        claimable_selector,
    )
    non_zero_gauge_users = sum(1 for v in gauge_claimable.values() if v > 0)
    print(f"  Gauge balances computed for {len(gauge_claimable)} addresses ({non_zero_gauge_users} non-zero)")

    print("Step 5: Compute claimable auction sales")
    auction_claimable, auction_meta = get_auction_unclaimed(
        rpc_url,
        AUCTION_CONTRACT,
        addresses,
        args.block,
        args.auction_vesting_duration,
        jobs,
    )
    print(f"  Auction recipients with subscriptions: {len(auction_claimable)}")
    print(
        f"  Auction end block: {auction_meta['auction_end_block']} | "
        f"snapshot ts: {auction_meta['snapshot_ts']}"
    )

    all_addresses = sorted(
        set(addresses) | set(sablier_claimable) | set(gauge_claimable) | set(auction_claimable)
    )
    print(f"Step 6: Classify address types for final output ({len(all_addresses)} addresses)")
    is_contract_map = classify_addresses(rpc_url, all_addresses, args.block, jobs)
    contract_count = sum(1 for _, is_ctr in is_contract_map.items() if is_ctr)
    print(f"  EOAs: {len(all_addresses) - contract_count} | Contracts: {contract_count}")

    if args.block:
        print("Step 7: Fetch wallet balances at pinned block")
        block_holders_path = root / f"tokenholders.block-{args.block}.csv"
        wallet_balances = fetch_wallet_balances_at_block(rpc_url, args.contract, all_addresses, args.block, block_holders_path, jobs)
        print("  Wrote pinned block balances")
    else:
        print("Step 7: Load wallet balances from tokenholders.csv")
        wallet_balances = load_wallet_balances_from_csv(holders_path, set(all_addresses))

    print("Step 8: Write final balances with component columns")
    write_final_balances(
        addresses=all_addresses,
        is_contract_map=is_contract_map,
        blacklist=blacklist,
        wallet_balances=wallet_balances,
        sablier_claimable=sablier_claimable,
        gauge_claimable=gauge_claimable,
        auction_claimable=auction_claimable,
        decimal_adjust=not args.raw_final_balances,
        out_path=final_path,
    )
    print("  Wrote final balances")

    if not args.skip_verify:
        print("Step 9: Verify balances with cast")
        verify_with_cast(rpc_url, args.contract, holders_path, verify_path, args.block)
        print("  Wrote verification report")
    else:
        print("Step 9: Skipped cast verification")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

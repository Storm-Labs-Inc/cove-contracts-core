#!/usr/bin/env python3
# Summary of work (end-to-end pipeline):
# 1) Fetch tokenholder balances from Etherscan v2 using API_KEY_ETHERSCAN and write tokenholders.csv.
# 2) Split blacklisted addresses (from blacklist.csv) into their own section at the bottom of tokenholders.csv.
# 3) (Optional) Verify tokenholder balances against mainnet RPC with cast and write tokenholders.cast-check.csv.
# 4) Discover reward gauges from deployments + CoveYearnGaugeFactory, then sum claimableReward for each holder.
# 5) Scan Sablier V2 Lockup Linear logs from block 19594522 and sum streamedAmountOf per recipient.
# 6) Calculate unclaimed auction vesting from the Sablier auction contract and add it to hidden balances.
# 7) Classify addresses as EOAs vs contracts via eth_getCode and keep both.
# 8) If a block is provided, recompute wallet balances at that block and write tokenholders.block-<block>.csv.
# 9) Merge wallet + hidden balances into final-balances.csv, with contracts in a separate section.

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import urllib.error
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlencode

ADDRESS_RE = re.compile(r"^0x[a-fA-F0-9]{40}$")
ZERO_ADDR = "0x0000000000000000000000000000000000000000"
DEFAULT_SABLIER_FROM_BLOCK = 19594522
AUCTION_CONTRACT = "0x2f3715F710076Cfdb5AA872Bc8a4b965a07c3A08"


# Parse CLI args for the unified pipeline.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Cove balances pipeline")
    parser.add_argument("--contract", default="0x32fb7D6E0cBEb9433772689aA4647828Cc7cbBA8")
    parser.add_argument("--chainid", default="1")
    parser.add_argument("--rpc-url", default=None, help="RPC URL (defaults to MAINNET_RPC_URL)")
    parser.add_argument("--block", default=None, help="Block number for pinned calculations")
    parser.add_argument(
        "--from-block",
        default=str(DEFAULT_SABLIER_FROM_BLOCK),
        help=f"Start block for Sablier log scan (default: {DEFAULT_SABLIER_FROM_BLOCK})",
    )
    parser.add_argument("--offset", default="1000", help="Etherscan pagination offset")
    parser.add_argument("--holders-out", default="tokenholders.csv")
    parser.add_argument("--hidden-out", default="hidden-balances.csv")
    parser.add_argument("--final-out", default="final-balances.csv")
    parser.add_argument("--verify-out", default="tokenholders.cast-check.csv")
    parser.add_argument("--blacklist", default="blacklist.csv")
    parser.add_argument("--skip-fetch", action="store_true", help="Skip Etherscan tokenholders fetch")
    parser.add_argument("--skip-verify", action="store_true", help="Skip cast verification step")
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


# Load auction vesting duration from script/vesting/vesting.json.
def load_auction_vesting_duration(path: Path) -> int:
    data = json.loads(path.read_text())
    vesting_data = data.get("vestingData") or []
    durations = {int(item.get("2_duration")) for item in vesting_data if item.get("2_duration") is not None}
    if not durations:
        raise RuntimeError("No vesting durations found in vesting.json")
    if len(durations) > 1:
        # Use the max duration to be conservative; log caller can surface this.
        return max(durations)
    return durations.pop()


# Fetch all tokenholders via Etherscan and write to CSV, with a blacklist section.
def fetch_tokenholders(
    api_key: str,
    contract: str,
    chainid: str,
    offset: str,
    out_path: Path,
    blacklist: set[str],
) -> tuple[int, int]:
    base_params = {
        "chainid": chainid,
        "module": "token",
        "action": "tokenholderlist",
        "contractaddress": contract,
        "apikey": api_key,
        "offset": offset,
    }

    page = 1
    rows = []
    black_rows = []

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
            addr_l = addr.lower()
            if addr_l in blacklist:
                black_rows.append((addr, bal))
            else:
                rows.append((addr, bal))

        if len(result) < int(offset):
            break
        page += 1

    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "token_balance"])
        writer.writerows(rows)
        if black_rows:
            writer.writerow(["blacklist------------------------------------------------------"])
            writer.writerows(black_rows)
    return len(rows), len(black_rows)


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
    return (
        "0x"
        + subprocess.check_output(["cast", "keccak", signature], text=True)
        .strip()
        .replace("0x", "")[:8]
    )


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


# Get block timestamp for a given block number or tag.
def get_block_timestamp(rpc_url: str, block: str | int) -> int:
    if isinstance(block, int):
        block_tag = hex(block)
    else:
        block_tag = block
    res = rpc_call(rpc_url, "eth_getBlockByNumber", [block_tag, False])
    if "error" in res or not res.get("result"):
        raise RuntimeError(res.get("error") or "Missing block result")
    return int(res["result"]["timestamp"], 16)


# Find the greatest block number with timestamp <= target timestamp.
def get_block_before_timestamp(rpc_url: str, target_ts: int) -> int:
    low = 0
    high = get_latest_block(rpc_url)
    best = 0
    while low <= high:
        mid = (low + high) // 2
        ts = get_block_timestamp(rpc_url, mid)
        if ts <= target_ts:
            best = mid
            low = mid + 1
        else:
            high = mid - 1
    return best


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


# Classify addresses as EOAs vs contracts.
def classify_addresses(
    rpc_url: str, addresses: list[str], block: str | None, jobs: int
) -> tuple[list[str], list[str]]:
    eoas: list[str] = []
    contracts: list[str] = []

    def check(addr: str) -> tuple[str, bool]:
        return addr, is_contract(rpc_url, addr, block)

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futures = {ex.submit(check, addr): addr for addr in addresses}
        for fut in as_completed(futures):
            addr, is_ctr = fut.result()
            if is_ctr:
                contracts.append(addr)
            else:
                eoas.append(addr)

    return eoas, contracts


# Discover reward gauges from deployments + CoveYearnGaugeFactory.
def get_reward_gauges(root: Path, rpc_url: str, block: str | None) -> list[str]:
    gauges: set[str] = set()

    for file in (root / "deployments" / "1").glob("*.json"):
        name = file.name.lower()
        if "rewardsgauge" in name and "impl" not in name and "forwarder" not in name:
            try:
                addr = json.loads(file.read_text()).get("address")
                if addr and ADDRESS_RE.match(addr):
                    gauges.add(addr.lower())
            except Exception:
                pass

    factory_path = root / "deployments" / "1" / "CoveYearnGaugeFactory.json"
    factory_addr = json.loads(factory_path.read_text()).get("address")
    if not factory_addr:
        return sorted(gauges)

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


# Calculate unclaimed auction vesting for addresses based on subscription amounts.
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
    snapshot_ts = (
        get_block_timestamp(rpc_url, int(block))
        if block is not None
        else get_block_timestamp(rpc_url, "latest")
    )

    denom = max(total_subs, floor_quote)
    vesting_duration_bi = max(0, vesting_duration)

    def fetch_sub_at(block_tag: str | int, addr: str) -> int:
        data = sub_sel + addr.replace("0x", "").rjust(64, "0")
        return eth_call(rpc_url, auction_addr, data, str(block_tag))

    # subscription at auction end and at snapshot block
    subs_end: dict[str, int] = {}
    subs_snap: dict[str, int] = {}

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futs_end = {
            ex.submit(fetch_sub_at, auction_end_block, addr): addr for addr in addresses
        }
        for fut in as_completed(futs_end):
            addr = futs_end[fut]
            subs_end[addr] = fut.result()

        snapshot_tag = int(block) if block is not None else "latest"
        futs_snap = {
            ex.submit(fetch_sub_at, snapshot_tag, addr): addr for addr in addresses
        }
        for fut in as_completed(futs_snap):
            addr = futs_snap[fut]
            subs_snap[addr] = fut.result()

    owed: dict[str, int] = {}
    debug: dict[str, int] = {}

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
        debug[addr] = vested

    return owed, {
        "auction_end_ts": auction_end_ts,
        "auction_end_block": auction_end_block,
        "total_subscriptions": total_subs,
        "total_project_tokens": total_proj,
        "floor_quote": floor_quote,
        "snapshot_ts": snapshot_ts,
    }


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


# Fetch ERC20 balances via eth_call for EOAs at a specific block and write to CSV.
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


# Merge wallet and hidden balances into final balances CSV.
def write_final_balances(
    wallet: dict[str, int],
    hidden: dict[str, int],
    eoas: list[str],
    contracts: list[str],
    out_path: Path,
) -> None:
    def total_for(addr: str) -> int:
        return wallet.get(addr, 0) + hidden.get(addr, 0)

    eoa_rows = [(addr, total_for(addr)) for addr in eoas]
    contract_rows = [(addr, total_for(addr)) for addr in contracts]

    eoa_rows.sort(key=lambda r: r[1], reverse=True)
    contract_rows.sort(key=lambda r: r[1], reverse=True)

    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "total_owed"])
        writer.writerows(eoa_rows)
        if contract_rows:
            writer.writerow(["contracts------------------------------------------------------"])
            writer.writerows(contract_rows)


# Run the full pipeline end-to-end.
def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[1]

    rpc_url = args.rpc_url or os.environ.get("MAINNET_RPC_URL")
    if not rpc_url:
        print("MAINNET_RPC_URL not set and --rpc-url not provided", file=sys.stderr)
        return 1

    api_key = os.environ.get("API_KEY_ETHERSCAN")
    if not api_key and not args.skip_fetch:
        print("API_KEY_ETHERSCAN not set (required for Etherscan fetch)", file=sys.stderr)
        return 1

    jobs = args.jobs or min(6, max(1, (os.cpu_count() or 2) // 2))

    holders_path = root / args.holders_out
    hidden_path = root / args.hidden_out
    final_path = root / args.final_out

    print(f"Contract: {args.contract}")
    if args.block:
        print(f"Pinned block: {args.block}")
    print(f"Sablier log scan from block: {args.from_block}")

    if not args.skip_fetch:
        print("Step 1: Fetch tokenholders from Etherscan")
        blacklist = load_blacklist(root / args.blacklist)
        rows, black_rows = fetch_tokenholders(
            api_key, args.contract, args.chainid, args.offset, holders_path, blacklist
        )
        print(f"  Wrote {rows} holder rows and {black_rows} blacklisted rows")
    else:
        print("Step 1: Skipped tokenholder fetch")

    print("Step 2: Load tokenholder addresses")
    addresses = load_tokenholder_addresses(holders_path)
    print(f"  Loaded {len(addresses)} addresses")

    print("Step 3: Classify EOAs vs contracts")
    eoa_addresses, contract_addresses = classify_addresses(rpc_url, addresses, args.block, jobs)
    print(f"  EOAs: {len(eoa_addresses)} | Contracts: {len(contract_addresses)}")
    if contract_addresses:
        for addr in sorted(contract_addresses):
            print(f"  contract: {addr}")

    lockup_addr = "0xafb979d9afad1ad27c5eff4e27226e3ab9e5dcc9"
    streamed_selector = function_selector("streamedAmountOf(uint256)")
    claimable_selector = function_selector("claimableReward(address,address)")

    from_block = int(args.from_block)

    print("Step 4: Compute vesting (streamed) balances from Sablier")
    vesting_balances = get_vesting_balances(
        rpc_url,
        lockup_addr,
        args.contract,
        args.block,
        from_block,
        streamed_selector,
    )
    print(f"  Vesting recipients: {len(vesting_balances)}")

    print("Step 5: Discover gauges and compute claimable rewards")
    gauges = get_reward_gauges(root, rpc_url, args.block)
    print(f"  Gauges discovered: {len(gauges)}")
    gauge_balances = get_gauge_claimable(
        rpc_url,
        gauges,
        args.contract,
        addresses,
        args.block,
        jobs,
        claimable_selector,
    )
    print(f"  Gauge balances computed for {len(gauge_balances)} addresses")

    print("Step 6: Compute auction unclaimed vesting")
    vesting_duration = load_auction_vesting_duration(root / "script" / "vesting" / "vesting.json")
    auction_owed, auction_meta = get_auction_unclaimed(
        rpc_url,
        AUCTION_CONTRACT,
        addresses,
        args.block,
        vesting_duration,
        jobs,
    )
    print(f"  Auction vesting duration (seconds): {vesting_duration}")
    print(f"  Auction end timestamp: {auction_meta['auction_end_ts']}")
    print(f"  Auction end block: {auction_meta['auction_end_block']}")
    print(
        "  Auction totals: subscriptions="
        f"{auction_meta['total_subscriptions']} "
        f"projectTokens={auction_meta['total_project_tokens']} "
        f"floorQuote={auction_meta['floor_quote']}"
    )
    print(f"  Auction snapshot timestamp: {auction_meta['snapshot_ts']}")
    print(f"  Auction addresses with unclaimed vesting: {len(auction_owed)}")
    if auction_owed:
        for addr, amt in sorted(auction_owed.items(), key=lambda r: r[1], reverse=True):
            print(f"  auction_unclaimed: {addr} {amt}")

    # merge hidden balances for all known addresses
    hidden_balances: dict[str, int] = {}
    hidden_addrs = sorted(
        set(addresses) | set(vesting_balances) | set(gauge_balances) | set(auction_owed)
    )
    for addr in hidden_addrs:
        hidden_balances[addr] = (
            vesting_balances.get(addr, 0)
            + gauge_balances.get(addr, 0)
            + auction_owed.get(addr, 0)
        )

    with hidden_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["address", "vesting_streamed", "gauge_claimable", "auction_unclaimed", "total_hidden"]
        )
        rows = [
            (
                addr,
                vesting_balances.get(addr, 0),
                gauge_balances.get(addr, 0),
                auction_owed.get(addr, 0),
                hidden_balances.get(addr, 0),
            )
            for addr in hidden_addrs
        ]
        rows.sort(key=lambda r: r[3], reverse=True)
        writer.writerows(rows)
    print("Step 7: Wrote hidden balances")

    # Wallet balances: use pinned block if provided, else use tokenholders.csv
    if args.block:
        print("Step 8: Fetch wallet balances at pinned block")
        block_holders_path = root / f"tokenholders.block-{args.block}.csv"
        wallet_balances = fetch_wallet_balances_at_block(
            rpc_url,
            args.contract,
            addresses,
            args.block,
            block_holders_path,
            jobs,
        )
        print("  Wrote pinned block balances")
    else:
        print("Step 8: Load wallet balances from tokenholders.csv")
        wallet_balances = load_wallet_balances_from_csv(holders_path, set(addresses))

    print("Step 9: Write final balances (EOA + contract sections)")
    write_final_balances(wallet_balances, hidden_balances, eoa_addresses, contract_addresses, final_path)
    print("  Wrote final balances")

    if not args.skip_verify:
        print("Step 10: Verify balances with cast")
        verify_with_cast(rpc_url, args.contract, holders_path, root / args.verify_out, args.block)
        print("  Wrote verification report")
    else:
        print("Step 10: Skipped cast verification")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

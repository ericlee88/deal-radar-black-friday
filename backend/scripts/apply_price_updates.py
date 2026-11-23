"""CLI helper for Antigravity scheduled automations to update verified prices.

Usage:
    # 1. List all tracked items and their ASINs / strike targets
    uv run python scripts/apply_price_updates.py --list

    # 2. Apply verified price updates from a JSON file (or --stdin) and regenerate deals_snapshot.json
    uv run python scripts/apply_price_updates.py --input /tmp/prices.json

Expected JSON format (object keyed by branch_key):
{
  "wssa0004772": {
    "current_price": 59.95,
    "msrp": 79.95,
    "avg_90d_price": 69.95,
    "all_time_low": 49.99,
    "clip_coupon_amount": 0.0,
    "note": "Amazon Black Friday deal verified via web search"
  }
}
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

from app.composite_bundles import validate_price_update
from scripts.export_snapshot import SNAPSHOT_OUTPUT, VERIFIED_PRICES_FILE, run_export

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_strike_targets() -> Dict[str, float]:
    """Load strike targets keyed by branch_key from deals_snapshot.json if present."""
    if not SNAPSHOT_OUTPUT.is_file():
        return {}
    try:
        data = json.loads(SNAPSHOT_OUTPUT.read_text(encoding="utf-8"))
        strikes: Dict[str, float] = {}
        for m in data.get("missions", []):
            for o in m.get("options", []):
                bk = o.get("branch_key")
                sp = o.get("strike_price")
                if bk and isinstance(sp, (int, float)) and sp > 0:
                    strikes[bk] = float(sp)
        return strikes
    except Exception:
        return {}


def _list_tracked_items() -> None:
    if not SNAPSHOT_OUTPUT.is_file():
        asyncio.run(run_export(poll_live=False))
    data = json.loads(SNAPSHOT_OUTPUT.read_text(encoding="utf-8"))
    print(f"{'branch_key':26s} {'ASIN':12s} {'current':>9s} {'strike':>9s}  title")
    print("-" * 105)
    for m in data.get("missions", []):
        for o in m.get("options", []):
            if o.get("is_trap_warning"):
                continue
            bk = o.get("branch_key", "")
            asin = (o.get("asin_or_sku", "") or "").split(" ")[0]
            cur = float(o.get("current_price") or 0.0)
            strike = float(o.get("strike_price") or 0.0)
            title = (o.get("title") or "")[:52]
            cur_s = f"${cur:.2f}" if cur > 0 else "UNPRICED"
            print(f"{bk:26s} {asin:12s} {cur_s:>9s} ${strike:>8.2f}  {title}")


def _apply_updates(
    updates: Dict[str, Dict[str, Any]],
    rebuild_snapshot: bool = True,
    force: bool = False,
) -> int:
    existing_doc: Dict[str, Any] = {"schema_version": 1, "updated_at": "", "items": {}}
    if VERIFIED_PRICES_FILE.is_file():
        try:
            loaded = json.loads(VERIFIED_PRICES_FILE.read_text(encoding="utf-8"))
            if isinstance(loaded, dict) and isinstance(loaded.get("items"), dict):
                existing_doc = loaded
        except Exception:
            pass

    items: Dict[str, Dict[str, Any]] = existing_doc.setdefault("items", {})
    strike_targets = _load_strike_targets()
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    updated_count = 0

    for branch_key, patch in updates.items():
        if not isinstance(patch, dict):
            continue
        cur = patch.get("current_price")
        if not isinstance(cur, (int, float)) or cur <= 0:
            continue

        cur_val = round(float(cur), 2)
        entry = items.get(branch_key, {})

        if not force:
            prev_price = float(entry.get("current_price") or 0.0)
            ref_msrp = float(patch.get("msrp") or entry.get("msrp") or 0.0)
            strike_price = strike_targets.get(branch_key, 0.0)
            ok, reason = validate_price_update(
                branch_key,
                cur_val,
                prev_price=prev_price,
                msrp=ref_msrp,
                strike_price=strike_price,
            )
            if not ok:
                print(f"[GUARD] Skipped {branch_key} (${cur_val:.2f}): {reason}")
                continue

        entry["current_price"] = cur_val
        for field in ("msrp", "avg_90d_price", "all_time_low"):
            v = patch.get(field)
            if isinstance(v, (int, float)) and v > 0:
                entry[field] = round(float(v), 2)
        coupon = patch.get("clip_coupon_amount")
        if isinstance(coupon, (int, float)) and coupon >= 0:
            entry["clip_coupon_amount"] = round(float(coupon), 2)
        if isinstance(patch.get("components"), dict):
            entry["components"] = patch["components"]

        source = str(patch.get("price_source") or "antigravity_automation")
        note = str(patch.get("note") or "Verified via scheduled Antigravity price check")
        entry["price_source"] = source
        entry["last_checked_at"] = datetime.now(timezone.utc).isoformat()

        hist = [round(float(x), 2) for x in entry.get("price_history", []) if float(x) > 0]
        if not hist or hist[-1] != cur_val:
            hist.append(cur_val)
        entry["price_history"] = hist[-24:]

        log = entry.get("price_log", [])
        if not isinstance(log, list):
            log = []
        # Dedupe identical price logged on the same day
        if not (log and log[0].get("date") == today and log[0].get("price") == cur_val):
            log.insert(
                0,
                {
                    "date": today,
                    "price": cur_val,
                    "source": source,
                    "note": note,
                },
            )
        entry["price_log"] = log[:30]

        items[branch_key] = entry
        updated_count += 1

    existing_doc["updated_at"] = datetime.now(timezone.utc).isoformat()
    VERIFIED_PRICES_FILE.parent.mkdir(parents=True, exist_ok=True)
    VERIFIED_PRICES_FILE.write_text(json.dumps(existing_doc, indent=2), encoding="utf-8")
    print(f"Saved {updated_count} verified price updates to {VERIFIED_PRICES_FILE}.")

    if not rebuild_snapshot:
        return updated_count

    # Rebuild static snapshot immediately
    asyncio.run(run_export(poll_live=False))

    # Print Strike Target Alerts Summary
    snap = json.loads(SNAPSHOT_OUTPUT.read_text(encoding="utf-8"))
    hits = []
    for m in snap.get("missions", []):
        for o in m.get("options", []):
            if o.get("is_below_strike") and not o.get("is_trap_warning"):
                hits.append(o)

    if hits:
        print(f"\nSTRIKE TARGET HITS ({len(hits)}):")
        for o in hits:
            print(
                f"  - {o['branch_key']}: ${o['effective_price']:.2f} "
                f"(Target <= ${o['strike_price']:.2f}) -> {o['amazon_url']}"
            )
    else:
        print("\nNo items are currently below their strike target.")
    return updated_count


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply verified price updates for Deal Radar.")
    parser.add_argument("--list", action="store_true", help="List tracked items & ASINs.")
    parser.add_argument("--input", type=str, help="Path to JSON file with price updates.")
    parser.add_argument("--stdin", action="store_true", help="Read JSON price updates from stdin.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Bypass composite bundle and outlier sanity guards.",
    )
    args = parser.parse_args()

    if args.list:
        _list_tracked_items()
        return

    if args.stdin:
        raw = sys.stdin.read()
    elif args.input:
        raw = Path(args.input).read_text(encoding="utf-8")
    else:
        parser.error("Provide --list, --input <file>, or --stdin.")
        return

    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise SystemExit("Expected a JSON object keyed by branch_key.")
    _apply_updates(payload, force=args.force)


if __name__ == "__main__":
    main()

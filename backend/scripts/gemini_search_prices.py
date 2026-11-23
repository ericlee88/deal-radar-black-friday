"""Scheduled live price checker using Gemini 2.5 Flash with Google Search Grounding.

Designed to run inside GitHub Actions (cron) with a free-tier GEMINI_API_KEY secret:
- Queries Google Search via Gemini grounding for current US retail / Amazon prices
- Strictly ignores any unverified or guessed prices
- Writes verified prices & timestamped history into data/verified_prices.json via apply_price_updates.py
"""

from __future__ import annotations

import asyncio
import json
import os
import re
from typing import Any, Dict, List

import httpx

from app.composite_bundles import (
    get_bundle_components,
    is_composite_bundle,
    validate_component_price,
    validate_price_update,
)
from scripts.apply_price_updates import _apply_updates
from scripts.export_snapshot import SNAPSHOT_OUTPUT, run_export

DEFAULT_MODEL_CANDIDATES = [
    "gemini-2.5-flash",
    "gemini-flash-latest",
    "gemini-3-flash-preview",
    "gemini-2.0-flash",
]
BATCH_SIZE = 5


async def _resolve_gemini_models(client: httpx.AsyncClient, api_key: str) -> List[str]:
    """Queries /v1beta/models to return an ordered list of live Gemini Flash models."""
    override = (os.getenv("GEMINI_PRICE_MODEL") or "").strip()
    if override:
        return [override]
    ordered: List[str] = []
    try:
        resp = await client.get(
            f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}",
            timeout=15.0,
        )
        if resp.status_code == 200:
            models = resp.json().get("models") or []
            available = []
            for m in models:
                name = (m.get("name") or "").replace("models/", "")
                methods = m.get("supportedGenerationMethods") or []
                if "generateContent" in methods and "flash" in name.lower():
                    if not any(skip in name.lower() for skip in ("lite", "image", "tts", "audio", "live", "thinking", "exp")):
                        available.append(name)
            print(f"Discovered Gemini Flash models: {available[:10]}")
            for preferred in (
                "gemini-3.8-flash",
                "gemini-3.6-flash",
                "gemini-3.5-flash",
                "gemini-3-flash",
                "gemini-3-flash-preview",
                "gemini-flash-latest",
                "gemini-2.5-flash",
            ):
                for name in available:
                    if (name == preferred or name.startswith(preferred)) and name not in ordered:
                        ordered.append(name)
            for name in available:
                if name not in ordered:
                    ordered.append(name)
        else:
            print(f"Model list HTTP {resp.status_code}: {resp.text[:200]}")
    except Exception as exc:
        print(f"Warning: could not list Gemini models ({exc}).")
    for fallback in DEFAULT_MODEL_CANDIDATES:
        if fallback not in ordered:
            ordered.append(fallback)
    return ordered


def _extract_json_object(text: str) -> Dict[str, Any]:
    """Extracts the first valid JSON object from a model response (handles markdown fences)."""
    cleaned = text.strip()
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.DOTALL)
    if fenced:
        cleaned = fenced.group(1)
    else:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start != -1 and end != -1 and end > start:
            cleaned = cleaned[start : end + 1]
    parsed = json.loads(cleaned)
    return parsed if isinstance(parsed, dict) else {}


async def _call_gemini_grounded_json(
    client: httpx.AsyncClient,
    api_key: str,
    model_name: str,
    prompt: str,
) -> Dict[str, Any]:
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model_name}:generateContent?key={api_key}"
    )
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "tools": [{"google_search": {}}],
        "generationConfig": {"temperature": 0.1},
    }

    resp = await client.post(url, json=payload, timeout=120.0)
    if resp.status_code >= 400:
        raise httpx.HTTPStatusError(
            f"HTTP {resp.status_code} ({model_name}): {resp.text[:250]}",
            request=resp.request,
            response=resp,
        )
    data = resp.json()

    candidates = data.get("candidates") or []
    if not candidates:
        return {}
    parts = (candidates[0].get("content") or {}).get("parts") or []
    text = "\n".join(p.get("text", "") for p in parts if isinstance(p, dict))
    if not text.strip():
        return {}

    try:
        return _extract_json_object(text)
    except Exception as exc:
        print(f"Warning: could not parse Gemini JSON: {exc}")
        return {}


async def _query_gemini_batch(
    client: httpx.AsyncClient,
    api_key: str,
    model_name: str,
    batch: List[Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    lines = []
    item_by_key: Dict[str, Dict[str, Any]] = {}
    for item in batch:
        bk = item["branch_key"]
        item_by_key[bk] = item
        asin = (item.get("asin_or_sku") or "").split(" ")[0]
        site_name = (item.get("site_name") or "").strip()
        product_url = (item.get("product_url") or "").strip()
        extra = ""
        if site_name and site_name.lower() != "amazon":
            extra += f" | Retailer: {site_name}"
        if product_url and "amazon.com/s?k=" not in product_url:
            extra += f" | URL: {product_url}"
        lines.append(
            f"- branch_key: {bk} | SKU/ASIN: {asin} | Product: {item['title']}{extra}"
        )

    prompt = (
        "Use Google Search to check the CURRENT US dollar retail price today for each product below (at the specified Retailer/URL if provided, or Amazon/major US retailers).\n"
        "STRICT RULES:\n"
        "1. ONLY include an item if you find a real, verified current USD price in the search results.\n"
        "2. Do NOT guess, estimate, or invent prices. Omit any item without a confirmed current USD price.\n"
        "3. Match the EXACT product size, pack count, and model listed — never substitute a smaller size or accessory.\n"
        "4. Return ONLY a raw JSON object keyed by branch_key, like:\n"
        '{"branch_key": {"current_price": 229.95, "msrp": 299.95, "clip_coupon_amount": 0.0, "note": "Amazon / retailer deal"}}\n\n'
        "Products:\n" + "\n".join(lines)
    )

    parsed = await _call_gemini_grounded_json(client, api_key, model_name, prompt)
    valid: Dict[str, Dict[str, Any]] = {}
    for bk, val in parsed.items():
        if bk not in item_by_key or not isinstance(val, dict):
            continue
        price = val.get("current_price")
        if not isinstance(price, (int, float)) or price <= 0:
            continue
        item = item_by_key[bk]
        ok, reason = validate_price_update(
            bk,
            float(price),
            prev_price=float(item.get("current_price") or 0.0),
            msrp=float(item.get("msrp") or 0.0),
            strike_price=float(item.get("strike_price") or 0.0),
        )
        if not ok:
            print(f"  [GUARD] Rejected outlier for {bk}: {reason}")
            continue
        val["price_source"] = "antigravity_automation"
        valid[bk] = val
    return valid


def assemble_bundle_updates(
    bundle_items: List[Dict[str, Any]],
    component_results: Dict[str, Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    """Combine verified component-level prices into complete composite bundle updates.

    A bundle is ONLY emitted when EVERY component has a verified, sane USD price.
    """
    assembled: Dict[str, Dict[str, Any]] = {}
    for item in bundle_items:
        bk = item["branch_key"]
        components = get_bundle_components(bk)
        if not components:
            continue

        total_price = 0.0
        total_msrp = 0.0
        all_have_msrp = True
        total_coupon = 0.0
        comp_breakdown: Dict[str, Dict[str, Any]] = {}
        note_parts: List[str] = []
        missing_or_invalid = False

        for comp in components:
            ck = comp["component_key"]
            res = component_results.get(ck)
            if not isinstance(res, dict):
                print(f"  [BUNDLE] Skipping {bk}: missing verified price for component '{ck}'")
                missing_or_invalid = True
                break
            c_price = res.get("current_price")
            if not isinstance(c_price, (int, float)):
                print(f"  [BUNDLE] Skipping {bk}: non-numeric price for component '{ck}'")
                missing_or_invalid = True
                break
            ok_c, reason_c = validate_component_price(comp, float(c_price))
            if not ok_c:
                print(f"  [BUNDLE] Skipping {bk}: component '{ck}' rejected ({reason_c})")
                missing_or_invalid = True
                break

            c_val = round(float(c_price), 2)
            total_price += c_val
            c_msrp = res.get("msrp")
            if isinstance(c_msrp, (int, float)) and c_msrp > 0:
                total_msrp += round(float(c_msrp), 2)
            else:
                all_have_msrp = False
            c_coupon = res.get("clip_coupon_amount")
            if isinstance(c_coupon, (int, float)) and c_coupon > 0:
                total_coupon += round(float(c_coupon), 2)

            c_note = str(res.get("note") or "").strip()
            comp_breakdown[ck] = {
                "sku_or_asin": comp["sku_or_asin"],
                "current_price": c_val,
                "note": c_note,
            }
            label = comp["sku_or_asin"].split("/")[-1].strip()
            note_parts.append(f"{label} ${c_val:.2f}")

        if missing_or_invalid:
            continue

        total_price = round(total_price, 2)
        ok_b, reason_b = validate_price_update(
            bk,
            total_price,
            prev_price=float(item.get("current_price") or 0.0),
            msrp=float(item.get("msrp") or 0.0),
            strike_price=float(item.get("strike_price") or 0.0),
        )
        if not ok_b:
            print(f"  [GUARD] Rejected assembled bundle {bk}: {reason_b}")
            continue

        entry: Dict[str, Any] = {
            "current_price": total_price,
            "clip_coupon_amount": round(total_coupon, 2),
            "price_source": "antigravity_automation",
            "note": f"Combined bundle verified: {' + '.join(note_parts)}",
            "components": comp_breakdown,
        }
        if all_have_msrp and total_msrp > 0:
            entry["msrp"] = round(total_msrp, 2)
        assembled[bk] = entry

    return assembled


async def _query_gemini_bundle_components(
    client: httpx.AsyncClient,
    api_key: str,
    model_name: str,
    bundle_items: List[Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    """Query each component of registered composite bundles individually and sum them."""
    comp_lines: List[str] = []
    allowed_component_keys = set()
    for item in bundle_items:
        for comp in get_bundle_components(item["branch_key"]):
            ck = comp["component_key"]
            if ck in allowed_component_keys:
                continue
            allowed_component_keys.add(ck)
            comp_lines.append(
                f"- component_key: {ck} | SKU/ASIN: {comp['sku_or_asin']} | Product: {comp['title']}"
            )

    if not comp_lines:
        return {}

    prompt = (
        "Use Google Search to check the CURRENT US dollar retail or Amazon price today for EACH INDIVIDUAL product below.\n"
        "STRICT RULES:\n"
        "1. Price each component SEPARATELY and EXACTLY as specified (genuine OEM brand, exact size/pack count).\n"
        "2. ONLY include a component if you find a real, verified current USD price in the search results.\n"
        "3. Do NOT guess, estimate, or invent prices. Omit any component without a confirmed current USD price.\n"
        "4. Return ONLY a raw JSON object keyed by component_key, like:\n"
        '{"dca1820": {"current_price": 39.88, "msrp": 58.99, "clip_coupon_amount": 0.0, "note": "Home Depot"}}\n\n'
        "Components:\n" + "\n".join(comp_lines)
    )

    parsed = await _call_gemini_grounded_json(client, api_key, model_name, prompt)
    filtered = {
        ck: val
        for ck, val in parsed.items()
        if ck in allowed_component_keys and isinstance(val, dict)
    }
    return assemble_bundle_updates(bundle_items, filtered)


async def run_gemini_price_check() -> None:
    api_key = (os.getenv("GEMINI_API_KEY") or "").strip()
    if not api_key:
        print("GEMINI_API_KEY not set — skipping Gemini Google Search grounded price check.")
        return

    if not SNAPSHOT_OUTPUT.is_file():
        await run_export(poll_live=False)

    snap = json.loads(SNAPSHOT_OUTPUT.read_text(encoding="utf-8"))
    regular_items: List[Dict[str, Any]] = []
    composite_items: List[Dict[str, Any]] = []
    for m in snap.get("missions", []):
        for o in m.get("options", []):
            if o.get("is_trap_warning"):
                continue
            if is_composite_bundle(o.get("branch_key", ""), o.get("asin_or_sku", "")):
                composite_items.append(o)
            else:
                regular_items.append(o)

    all_updates: Dict[str, Dict[str, Any]] = {}

    async with httpx.AsyncClient() as client:
        models = await _resolve_gemini_models(client, api_key)
        model_idx = 0
        print(
            f"Checking live prices for {len(regular_items)} single-SKU items and "
            f"{len(composite_items)} composite bundles via {models[model_idx]} + Google Search..."
        )
        for i in range(0, len(regular_items), BATCH_SIZE):
            batch = regular_items[i : i + BATCH_SIZE]
            while model_idx < len(models):
                try:
                    batch_res = await _query_gemini_batch(client, api_key, models[model_idx], batch)
                    print(f"  Batch {i // BATCH_SIZE + 1} ({models[model_idx]}): verified {len(batch_res)}/{len(batch)} items")
                    all_updates.update(batch_res)
                    break
                except httpx.HTTPStatusError as exc:
                    print(f"  Batch {i // BATCH_SIZE + 1} failed: {exc}")
                    if exc.response.status_code == 404 and model_idx + 1 < len(models):
                        model_idx += 1
                        print(f"  Retrying with fallback model: {models[model_idx]}...")
                        continue
                    break
                except Exception as exc:
                    print(f"  Batch {i // BATCH_SIZE + 1} failed: {type(exc).__name__}: {exc}")
                    break
            await asyncio.sleep(1.5)

        if composite_items:
            while model_idx < len(models):
                try:
                    bundle_res = await _query_gemini_bundle_components(
                        client, api_key, models[model_idx], composite_items
                    )
                    print(
                        f"  Composite bundles ({models[model_idx]}): verified "
                        f"{len(bundle_res)}/{len(composite_items)} bundles (all components summed)"
                    )
                    all_updates.update(bundle_res)
                    break
                except httpx.HTTPStatusError as exc:
                    print(f"  Composite bundles batch failed: {exc}")
                    if exc.response.status_code == 404 and model_idx + 1 < len(models):
                        model_idx += 1
                        print(f"  Retrying composite bundles with fallback model: {models[model_idx]}...")
                        continue
                    break
                except Exception as exc:
                    print(f"  Composite bundles batch failed: {type(exc).__name__}: {exc}")
                    break

    if all_updates:
        _apply_updates(all_updates, rebuild_snapshot=False)
    else:
        print("No new verified prices returned from Gemini Search Grounding.")


if __name__ == "__main__":
    asyncio.run(run_gemini_price_check())

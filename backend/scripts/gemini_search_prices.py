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
                "gemini-3-flash",
                "gemini-3-flash-preview",
                "gemini-flash-latest",
                "gemini-2.5-flash-preview",
                "gemini-2.5-flash",
                "gemini-2.0-flash",
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


async def _query_gemini_batch(
    client: httpx.AsyncClient,
    api_key: str,
    model_name: str,
    batch: List[Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    lines = []
    for item in batch:
        asin = (item.get("asin_or_sku") or "").split(" ")[0]
        lines.append(
            f"- branch_key: {item['branch_key']} | ASIN: {asin} | Product: {item['title']}"
        )

    prompt = (
        "Use Google Search to check the CURRENT US dollar retail or Amazon price today for each product below.\n"
        "STRICT RULES:\n"
        "1. ONLY include an item if you find a real, verified current USD price in the search results.\n"
        "2. Do NOT guess, estimate, or invent prices. Omit any item without a confirmed current USD price.\n"
        "3. Return ONLY a raw JSON object keyed by branch_key, like:\n"
        '{"branch_key": {"current_price": 229.95, "msrp": 299.95, "clip_coupon_amount": 0.0, "note": "Amazon / retailer deal"}}\n\n'
        "Products:\n" + "\n".join(lines)
    )

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model_name}:generateContent?key={api_key}"
    )
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "tools": [{"google_search": {}}],
        "generationConfig": {"temperature": 0.1},
    }

    resp = await client.post(url, json=payload, timeout=45.0)
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
        parsed = _extract_json_object(text)
    except Exception as exc:
        print(f"Warning: could not parse Gemini JSON for batch: {exc}")
        return {}

    valid: Dict[str, Dict[str, Any]] = {}
    allowed_keys = {item["branch_key"] for item in batch}
    for bk, val in parsed.items():
        if bk not in allowed_keys or not isinstance(val, dict):
            continue
        price = val.get("current_price")
        if isinstance(price, (int, float)) and price > 0:
            val["price_source"] = "antigravity_automation"
            valid[bk] = val
    return valid


async def run_gemini_price_check() -> None:
    api_key = (os.getenv("GEMINI_API_KEY") or "").strip()
    if not api_key:
        print("GEMINI_API_KEY not set — skipping Gemini Google Search grounded price check.")
        return

    if not SNAPSHOT_OUTPUT.is_file():
        await run_export(poll_live=False)

    snap = json.loads(SNAPSHOT_OUTPUT.read_text(encoding="utf-8"))
    tracked: List[Dict[str, Any]] = []
    for m in snap.get("missions", []):
        for o in m.get("options", []):
            if not o.get("is_trap_warning"):
                tracked.append(o)

    all_updates: Dict[str, Dict[str, Any]] = {}

    async with httpx.AsyncClient() as client:
        models = await _resolve_gemini_models(client, api_key)
        model_idx = 0
        print(f"Checking live prices for {len(tracked)} items via {models[model_idx]} + Google Search...")
        for i in range(0, len(tracked), BATCH_SIZE):
            batch = tracked[i : i + BATCH_SIZE]
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
                    print(f"  Batch {i // BATCH_SIZE + 1} failed: {exc}")
                    break
            await asyncio.sleep(1.5)

    if all_updates:
        _apply_updates(all_updates)
    else:
        print("No new verified prices returned from Gemini Search Grounding.")


if __name__ == "__main__":
    asyncio.run(run_gemini_price_check())

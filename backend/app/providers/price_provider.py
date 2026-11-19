import json
import random
import re
from typing import Dict, Any, Optional
import httpx
from app.config import settings
from app.engine.deal_scorer import extract_amazon_asin
from app.models import DealOptionNode

_AMAZON_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


class PriceDataProvider:
    """Pluggable Price & Keepa History Provider.

    Supports:
    - `keepa`: Uses live Keepa API (`https://api.keepa.com/product`) when `KEEPA_API_KEY` is configured.
    - `amazon_direct`: Keyless live Amazon product/search page price & coupon scraper.
    - `mock`: Deterministic Black Friday wave simulation.
    """

    async def refresh_node_price(self, node: DealOptionNode, simulate_drop: bool = False) -> Dict[str, Any]:
        if simulate_drop:
            return self._simulate_price_tick(node, simulate_drop=True)

        mode = settings.active_price_mode
        if mode == "keepa" and settings.keepa_api_key:
            try:
                return await self._fetch_keepa(node)
            except Exception:
                pass

        if mode in ("amazon_direct", "keepa"):
            try:
                live_tick = await self._fetch_amazon_direct(node)
                if live_tick is not None:
                    return live_tick
            except Exception:
                pass

        return self._simulate_price_tick(node, simulate_drop=simulate_drop)

    async def _fetch_amazon_direct(self, node: DealOptionNode) -> Optional[Dict[str, Any]]:
        asin = extract_amazon_asin(node.asin_or_sku)
        url = (
            f"https://www.amazon.com/dp/{asin}"
            if asin
            else f"https://www.amazon.com/s?k={node.amazon_query}"
        )
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True, headers=_AMAZON_HEADERS) as client:
            resp = await client.get(url)
            if resp.status_code != 200:
                return None
            html = resp.text

        # Extract primary buybox or search result price
        price_val: Optional[float] = None
        for pattern in (
            r'class="a-price[^"]*"[^>]*>\s*<span class="a-offscreen">\$([0-9]+(?:\.[0-9]{2})?)</span>',
            r'"priceAmount":\s*([0-9]+(?:\.[0-9]{1,2})?)',
            r'id="priceblock_ourprice"[^>]*>\$([0-9]+(?:\.[0-9]{2})?)',
        ):
            m = re.search(pattern, html)
            if m:
                try:
                    candidate = round(float(m.group(1)), 2)
                    # Sanity check against huge third-party outlier errors (within 0.25x - 2.5x MSRP)
                    if node.msrp * 0.20 <= candidate <= node.msrp * 2.50:
                        price_val = candidate
                        break
                except ValueError:
                    pass

        if price_val is None:
            return None

        # Check for on-page green coupon ("Save $5.00 with coupon" or "Apply $4 coupon")
        coupon_val = node.clip_coupon_amount
        m_coupon = re.search(
            r'(?:Save|Apply)\s+\$([0-9]+(?:\.[0-9]{1,2})?)\s+(?:with\s+)?coupon',
            html,
            re.IGNORECASE,
        )
        if m_coupon:
            try:
                coupon_val = round(float(m_coupon.group(1)), 2)
            except ValueError:
                pass

        try:
            history = json.loads(node.price_history_json or "[]")
            if isinstance(history, list) and len(history) >= 2:
                history[-1] = price_val
                node.price_history_json = json.dumps(history)
        except Exception:
            pass

        return {
            "current_price": price_val,
            "avg_90d_price": node.avg_90d_price,
            "clip_coupon_amount": coupon_val,
            "provider": "amazon_direct_live",
        }

    async def _fetch_keepa(self, node: DealOptionNode) -> Dict[str, Any]:
        asin = extract_amazon_asin(node.asin_or_sku) or node.asin_or_sku
        url = "https://api.keepa.com/product"
        params = {
            "key": settings.keepa_api_key,
            "domain": 1,  # Amazon.com US
            "asin": asin,
            "stats": 90,
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()
            products = data.get("products") or []
            if not products:
                return self._simulate_price_tick(node, simulate_drop=False)
            stats = products[0].get("stats") or {}
            # Keepa stores prices in cents
            curr_cents = (stats.get("current") or [-1])[0]
            avg90_cents = (stats.get("avg90") or [-1])[0]
            new_price = round(curr_cents / 100.0, 2) if curr_cents > 0 else node.current_price
            new_avg = round(avg90_cents / 100.0, 2) if avg90_cents > 0 else node.avg_90d_price
            return {
                "current_price": new_price,
                "avg_90d_price": new_avg,
                "clip_coupon_amount": node.clip_coupon_amount,
                "provider": "keepa_live",
            }

    def _simulate_price_tick(self, node: DealOptionNode, simulate_drop: bool = False) -> Dict[str, Any]:
        if node.is_trap_warning:
            return {
                "current_price": node.current_price,
                "avg_90d_price": node.avg_90d_price,
                "clip_coupon_amount": node.clip_coupon_amount,
                "provider": "mock_keepa",
            }

        if simulate_drop:
            # Simulate a Black Friday lightning deal crossing the strike threshold
            target = round(min(node.current_price, node.strike_price * 0.96), 2)
        else:
            delta = random.choice([-1.50, -0.50, 0.0, 0.50])
            target = round(max(node.all_time_low, node.current_price + delta), 2)

        try:
            history = json.loads(node.price_history_json or "[]")
            if isinstance(history, list) and len(history) >= 2:
                history[-1] = target
                node.price_history_json = json.dumps(history)
        except Exception:
            pass

        return {
            "current_price": target,
            "avg_90d_price": node.avg_90d_price,
            "clip_coupon_amount": node.clip_coupon_amount,
            "provider": "mock_keepa",
        }


price_provider = PriceDataProvider()


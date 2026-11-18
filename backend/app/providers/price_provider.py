import json
import random
from typing import Dict, Any
import httpx
from app.config import settings
from app.models import DealOptionNode


class PriceDataProvider:
    """Pluggable Price & Keepa History Provider.

    Uses live Keepa API (`https://api.keepa.com/product`) when `KEEPA_API_KEY` is configured,
    and falls back to realistic Black Friday wave simulation in local/mock mode.
    """

    async def refresh_node_price(self, node: DealOptionNode, simulate_drop: bool = False) -> Dict[str, Any]:
        if settings.active_price_mode == "keepa" and settings.keepa_api_key:
            try:
                return await self._fetch_keepa(node)
            except Exception:
                pass

        return self._simulate_price_tick(node, simulate_drop=simulate_drop)

    async def _fetch_keepa(self, node: DealOptionNode) -> Dict[str, Any]:
        url = "https://api.keepa.com/product"
        params = {
            "key": settings.keepa_api_key,
            "domain": 1,  # Amazon.com US
            "asin": node.asin_or_sku,
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
                "provider": "keepa_live",
            }

    def _simulate_price_tick(self, node: DealOptionNode, simulate_drop: bool = False) -> Dict[str, Any]:
        if node.is_trap_warning:
            return {
                "current_price": node.current_price,
                "avg_90d_price": node.avg_90d_price,
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
            "provider": "mock_keepa",
        }


price_provider = PriceDataProvider()

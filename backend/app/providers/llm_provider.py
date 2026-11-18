import json
import re
from typing import Optional
import httpx
from app.config import settings
from app.models import MissionNodeType
from app.schemas import GeneratedMissionSpec, GeneratedOptionSpec


SYSTEM_PROMPT = """You are an elite Amazon Black Friday & Deal Strategy Engine.
Given a user's raw shopping intent (which may be a fuzzy category, an exact SKU, a fork-in-the-road 'A or B' trade-off, or a recurring consumable), return a JSON object conforming strictly to GeneratedMissionSpec:
{
  "slug": "kebab-case-slug",
  "title": "Concise Mission Title",
  "node_type": "EXACT_SKU" | "XOR_FORK" | "CATEGORY_FUNNEL" | "CONSUMABLE_STACK",
  "category_tag": "kitchen" | "tools" | "vacuums" | "health" | "consumables" | "games" | "tech",
  "icon": "single emoji",
  "decision_framing": "1-2 sentence L6-grade analytical summary of how to buy this item on Black Friday without falling for fake MSRP or discontinued SKU traps.",
  "options": [
    {
      "branch_key": "path_a",
      "branch_label": "Path A • Primary Recommendation",
      "is_recommended_branch": true,
      "is_trap_warning": false,
      "title": "Exact Brand, Model, and Spec Title",
      "asin_or_sku": "Model/SKU or ASIN",
      "amazon_query": "URL+encoded+search+query",
      "msrp": 99.99,
      "avg_90d_price": 84.99,
      "current_price": 69.99,
      "clip_coupon_amount": 0.0,
      "strike_price": 68.00,
      "all_time_low": 64.99,
      "sns_eligible": false,
      "pg_stockup_eligible": false,
      "b2g1_eligible": false,
      "unit_name": "unit",
      "unit_quantity": 1.0,
      "scout_notes": "Concrete guidance on why this SKU wins and what price to strike at."
    }
  ]
}
Return ONLY valid JSON without markdown fences.
"""


class LLMIntentResolver:
    """Pluggable LLM Intent Resolver with Gemini, OpenAI, and Deterministic Heuristic modes."""

    async def translate_intent(
        self, raw_intent: str, budget_hint: Optional[float] = None
    ) -> GeneratedMissionSpec:
        mode = settings.active_llm_mode
        if mode == "gemini" and settings.gemini_api_key:
            try:
                return await self._call_gemini(raw_intent, budget_hint)
            except Exception:
                pass
        elif mode == "openai" and settings.openai_api_key:
            try:
                return await self._call_openai(raw_intent, budget_hint)
            except Exception:
                pass

        return self._heuristic_resolve(raw_intent, budget_hint)

    async def _call_gemini(
        self, raw_intent: str, budget_hint: Optional[float]
    ) -> GeneratedMissionSpec:
        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
        )
        prompt = f"User shopping intent: {raw_intent}\nBudget hint: {budget_hint or 'None'}"
        payload = {
            "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
        }
        async with httpx.AsyncClient(timeout=20.0) as client:
            resp = await client.post(url, json=payload)
            resp.raise_for_status()
            data = resp.json()
            text = data["candidates"][0]["content"]["parts"][0]["text"]
            return GeneratedMissionSpec.model_validate_json(text)

    async def _call_openai(
        self, raw_intent: str, budget_hint: Optional[float]
    ) -> GeneratedMissionSpec:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {settings.openai_api_key}"}
        prompt = f"User shopping intent: {raw_intent}\nBudget hint: {budget_hint or 'None'}"
        payload = {
            "model": settings.openai_model,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
        }
        async with httpx.AsyncClient(timeout=20.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()
            text = data["choices"][0]["message"]["content"]
            return GeneratedMissionSpec.model_validate_json(text)

    def _heuristic_resolve(
        self, raw_intent: str, budget_hint: Optional[float]
    ) -> GeneratedMissionSpec:
        """Deterministic local intent analyzer that classifies intent into the Polymorphic Mission DAG."""
        cleaned = raw_intent.strip()
        lower = cleaned.lower()
        slug_base = re.sub(r"[^a-z0-9]+", "-", lower).strip("-")[:36] or "custom-mission"
        query_encoded = re.sub(r"\s+", "+", cleaned)

        is_fork = any(tok in lower for tok in [" or ", " vs ", "alternatively", "either", "adapter"])
        is_consumable = any(
            tok in lower
            for tok in ["subscribe", "refill", "protein", "collagen", "paper", "soap", "detergent", "pack", "pods"]
        )
        has_sku = bool(re.search(r"\b[A-Z0-9]{5,12}\b", cleaned))

        base_msrp = round(budget_hint * 1.35, 2) if budget_hint else 79.99
        avg_90 = round(base_msrp * 0.86, 2)
        curr = round(base_msrp * 0.74, 2)
        strike = round(budget_hint if budget_hint else base_msrp * 0.72, 2)
        atl = round(strike * 0.93, 2)

        if is_fork:
            parts = re.split(r"\b(?:or|vs\.?|alternatively)\b", cleaned, maxsplit=1, flags=re.IGNORECASE)
            left_title = parts[0].strip().rstrip(",.")
            right_title = parts[1].strip().rstrip(",.") if len(parts) > 1 else f"Upgraded {left_title} Kit"
            return GeneratedMissionSpec(
                slug=f"{slug_base}-fork",
                title=f"Decision Fork: {left_title[:42]}",
                node_type=MissionNodeType.XOR_FORK,
                category_tag="tech",
                icon="🔀",
                decision_framing=(
                    f"Evaluates whether to buy '{left_title}' standalone or step up to '{right_title}' "
                    "during Black Friday bundle markdowns."
                ),
                options=[
                    GeneratedOptionSpec(
                        branch_key="path_a",
                        branch_label="Path A • Incremental / Modular Route",
                        is_recommended_branch=False,
                        title=left_title,
                        asin_or_sku="MODULAR-OPTION-A",
                        amazon_query=re.sub(r"\s+", "+", left_title),
                        msrp=base_msrp,
                        avg_90d_price=avg_90,
                        current_price=curr,
                        strike_price=strike,
                        all_time_low=atl,
                        scout_notes=f"Lower upfront spend for {left_title}; verify Sold by Amazon.com.",
                    ),
                    GeneratedOptionSpec(
                        branch_key="path_b",
                        branch_label="Path B • Full Bundle / Next-Gen Upgrade",
                        is_recommended_branch=True,
                        title=right_title,
                        asin_or_sku="BUNDLE-OPTION-B",
                        amazon_query=re.sub(r"\s+", "+", right_title),
                        msrp=round(base_msrp * 1.25, 2),
                        avg_90d_price=round(avg_90 * 1.18, 2),
                        current_price=round(curr * 1.12, 2),
                        clip_coupon_amount=round(base_msrp * 0.08, 2),
                        strike_price=round(strike * 1.10, 2),
                        all_time_low=round(atl * 1.08, 2),
                        scout_notes=f"Black Friday bundle pricing on {right_title} narrows the gap to <12%.",
                    ),
                ],
            )

        if is_consumable:
            return GeneratedMissionSpec(
                slug=f"{slug_base}-stack",
                title=cleaned[:55],
                node_type=MissionNodeType.CONSUMABLE_STACK,
                category_tag="consumables",
                icon="📦",
                decision_framing="Stack 15% Subscribe & Save (5+ items) with first-delivery clip coupon.",
                options=[
                    GeneratedOptionSpec(
                        branch_key="sns_primary",
                        branch_label="S&S Stackable SKU",
                        is_recommended_branch=True,
                        title=cleaned,
                        asin_or_sku="SNS-STACK-SKU",
                        amazon_query=query_encoded,
                        msrp=39.99 if not budget_hint else base_msrp,
                        avg_90d_price=34.99 if not budget_hint else avg_90,
                        current_price=29.99 if not budget_hint else curr,
                        clip_coupon_amount=4.00,
                        strike_price=21.50 if not budget_hint else strike,
                        all_time_low=19.99 if not budget_hint else atl,
                        sns_eligible=True,
                        pg_stockup_eligible=True,
                        unit_name="serving",
                        unit_quantity=60.0,
                        scout_notes="Clip coupon + 15% S&S unlocks all-time low unit economics.",
                    )
                ],
            )

        node_type = MissionNodeType.EXACT_SKU if has_sku else MissionNodeType.CATEGORY_FUNNEL
        return GeneratedMissionSpec(
            slug=slug_base,
            title=cleaned[:60],
            node_type=node_type,
            category_tag="general",
            icon="🎯" if has_sku else "🔎",
            decision_framing=(
                "Pinned exact SKU tracker."
                if has_sku
                else "Category funnel resolved into top-rated Black Friday value candidates."
            ),
            options=[
                GeneratedOptionSpec(
                    branch_key="top_pick",
                    branch_label="Top Spec-Matched Pick",
                    is_recommended_branch=True,
                    title=f"{cleaned} (Top-Tier Spec Match)",
                    asin_or_sku="SPEC-MATCH-01",
                    amazon_query=query_encoded,
                    msrp=base_msrp,
                    avg_90d_price=avg_90,
                    current_price=curr,
                    strike_price=strike,
                    all_time_low=atl,
                    scout_notes="Watch for Wave 2/3 lightning deals or clip coupons.",
                )
            ],
        )


llm_resolver = LLMIntentResolver()

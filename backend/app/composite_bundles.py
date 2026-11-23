"""Composite multi-SKU bundle definitions and price sanity guards.

Prevents single-ASIN scrapes or single-component LLM search results (e.g. pricing
only the DeWalt DCA1820 adapter at $39.88 without the DCB205-2C battery kit, or
pricing only Metamucil at $38.99 without Vital Proteins Collagen) from overwriting
combined bundle prices and triggering false strike-price hits.
"""

from __future__ import annotations

from typing import Any, Dict, List, Tuple

COMPOSITE_BUNDLES: Dict[str, List[Dict[str, Any]]] = {
    "path_a_adapter_split": [
        {
            "component_key": "dca1820",
            "sku_or_asin": "B016K1UD0E / DCA1820",
            "title": "DeWalt DCA1820 18V-to-20V MAX Lithium-Ion Battery Adapter (Genuine OEM, adapter only)",
            "min_reasonable_price": 20.0,
            "max_reasonable_price": 120.0,
        },
        {
            "component_key": "dcb205_2c",
            "sku_or_asin": "DCB205-2C",
            "title": "DeWalt DCB205-2C 20V MAX XR 2-Pack 5.0Ah Lithium-Ion Battery & Charger Starter Kit",
            "min_reasonable_price": 80.0,
            "max_reasonable_price": 360.0,
        },
    ],
    "diy_metamucil_vital": [
        {
            "component_key": "metamucil_180",
            "sku_or_asin": "B00K6JUG4K",
            "title": "Metamucil 4-in-1 Psyllium Husk Powder, Sugar-Free Orange Smooth, 180 Servings (36.8 oz)",
            "min_reasonable_price": 18.0,
            "max_reasonable_price": 65.0,
        },
        {
            "component_key": "vital_proteins_20oz",
            "sku_or_asin": "VITAL-20OZ",
            "title": "Vital Proteins Collagen Peptides Powder, Unflavored, 20 oz (567 g)",
            "min_reasonable_price": 22.0,
            "max_reasonable_price": 75.0,
        },
    ],
}


def get_bundle_components(branch_key: str) -> List[Dict[str, Any]]:
    """Return component definitions for a registered composite bundle, or empty list."""
    return list(COMPOSITE_BUNDLES.get(branch_key, []))


def is_composite_bundle(branch_key: str, asin_or_sku: str = "") -> bool:
    """Return True if an option represents a multi-item bundle/stack rather than a single ASIN."""
    if branch_key in COMPOSITE_BUNDLES:
        return True
    return " + " in (asin_or_sku or "")


def bundle_price_bounds(branch_key: str) -> Tuple[float, float]:
    """Return (min_total, max_total) across all components of a registered bundle."""
    comps = COMPOSITE_BUNDLES.get(branch_key)
    if not comps:
        return (0.0, 0.0)
    min_total = round(sum(float(c["min_reasonable_price"]) for c in comps), 2)
    max_total = round(sum(float(c["max_reasonable_price"]) for c in comps), 2)
    return (min_total, max_total)


def validate_component_price(
    component: Dict[str, Any], candidate_price: float
) -> Tuple[bool, str]:
    """Validate an individual bundle component's verified USD price."""
    if not isinstance(candidate_price, (int, float)) or candidate_price <= 0:
        return False, "non-positive price"
    val = float(candidate_price)
    low = float(component.get("min_reasonable_price") or 0.0)
    high = float(component.get("max_reasonable_price") or 0.0)
    if low > 0 and val < low:
        return False, f"${val:.2f} below component floor ${low:.2f}"
    if high > 0 and val > high:
        return False, f"${val:.2f} above component ceiling ${high:.2f}"
    return True, "ok"


def validate_price_update(
    branch_key: str,
    candidate_price: float,
    *,
    prev_price: float = 0.0,
    msrp: float = 0.0,
    strike_price: float = 0.0,
) -> Tuple[bool, str]:
    """Validate a candidate current_price against bundle floors and extreme outlier bounds.

    Allows legitimate Black Friday deals (including deep discounts at or below strike_price),
    while rejecting single-component bundle prices and obvious scrape/LLM mismatches.
    """
    if not isinstance(candidate_price, (int, float)) or candidate_price <= 0:
        return False, "price must be positive"

    val = float(candidate_price)

    # 1. Strict component-sum floor/ceiling for registered composite bundles
    min_bundle, max_bundle = bundle_price_bounds(branch_key)
    if min_bundle > 0 and val < min_bundle:
        return (
            False,
            f"composite bundle {branch_key} price ${val:.2f} is below combined component floor ${min_bundle:.2f} "
            "(likely priced only one component)",
        )
    if max_bundle > 0 and val > max_bundle:
        return (
            False,
            f"composite bundle {branch_key} price ${val:.2f} exceeds ceiling ${max_bundle:.2f}",
        )

    # 2. Extreme single-step drop guard (only blocks when ALSO well below strike target)
    if prev_price > 0:
        if strike_price > 0:
            if val < prev_price * 0.40 and val < strike_price * 0.60:
                return (
                    False,
                    f"${val:.2f} is >60% below previous ${prev_price:.2f} and >40% below strike ${strike_price:.2f}",
                )
        elif val < prev_price * 0.35:
            return (
                False,
                f"${val:.2f} is >65% below previous ${prev_price:.2f}",
            )

    # 3. Extreme upward spike guard (e.g., 3P scalper or multi-pack mismatch)
    ref_high = max(prev_price, msrp, strike_price)
    if ref_high > 0 and val > ref_high * 3.0:
        return (
            False,
            f"${val:.2f} exceeds 3x reference ceiling (${ref_high * 3.0:.2f})",
        )

    return True, "ok"

import json
import re
from typing import List, Optional, Tuple
from app.models import DealOptionNode, ShoppingMission
from app.schemas import (
    AmazonCartBuilderPlan,
    CartChecklistStep,
    CombinatoricStackSummary,
    DealOptionRead,
    ShoppingMissionRead,
)

_ASIN_REGEX = re.compile(r"\b(B0[A-Z0-9]{8})\b")


def extract_amazon_asin(asin_or_sku: str) -> Optional[str]:
    match = _ASIN_REGEX.search(asin_or_sku or "")
    return match.group(1) if match else None


def _build_multi_asin_url(asins: List[str]) -> Optional[str]:
    if not asins:
        return None
    params = []
    for idx, asin in enumerate(asins, start=1):
        params.append(f"ASIN.{idx}={asin}&Quantity.{idx}=1")
    return "https://www.amazon.com/gp/aws/cart/add.html?" + "&".join(params)



def compute_effective_price(node: DealOptionNode, sns_tier_rate: float = 0.15) -> float:
    """Calculates net effective price after clip coupons and Subscribe & Save."""
    sns_discount = node.current_price * sns_tier_rate if node.sns_eligible else 0.0
    net = max(0.0, node.current_price - (node.clip_coupon_amount or 0.0) - sns_discount)
    return round(net, 2)


def enrich_option_node(node: DealOptionNode, sns_tier_rate: float = 0.15) -> DealOptionRead:
    """Converts a DB DealOptionNode into a fully scored DealOptionRead DTO."""
    eff = compute_effective_price(node, sns_tier_rate=sns_tier_rate)
    qty = max(0.001, node.unit_quantity or 1.0)
    unit_eff = round(eff / qty, 2)
    pct_off = int(round(((node.msrp - eff) / node.msrp) * 100)) if node.msrp > 0 else 0

    if node.is_trap_warning or eff > node.msrp * 1.1:
        grade_code = "TRAP"
        grade_label = "⚠️ SCALPER / TRAP — DO NOT BUY"
    elif eff <= node.all_time_low + 0.50:
        grade_code = "ATL"
        grade_label = f"🔥 ALL-TIME LOW ZONE (-{pct_off}%)"
    elif eff <= node.strike_price:
        grade_code = "STRIKE"
        grade_label = f"✅ AT STRIKE TARGET (-{pct_off}%)"
    elif eff <= node.avg_90d_price * 0.94:
        grade_code = "HOLD"
        grade_label = f"⏳ NEAR TARGET (-{pct_off}% • Target ${node.strike_price:.0f})"
    else:
        grade_code = "WAIT"
        grade_label = "⚠️ ABOVE STRIKE (Wait for Next Wave)"

    try:
        history = json.loads(node.price_history_json or "[]")
        if not isinstance(history, list) or not history:
            history = [node.msrp, node.avg_90d_price, eff]
        else:
            history = [float(x) for x in history]
            history[-1] = eff
    except Exception:
        history = [node.msrp, node.avg_90d_price, eff]

    return DealOptionRead(
        id=node.id or 0,
        mission_id=node.mission_id,
        branch_key=node.branch_key,
        branch_label=node.branch_label,
        is_recommended_branch=node.is_recommended_branch,
        is_trap_warning=node.is_trap_warning,
        title=node.title,
        asin_or_sku=node.asin_or_sku,
        amazon_query=node.amazon_query,
        msrp=node.msrp,
        avg_90d_price=node.avg_90d_price,
        current_price=node.current_price,
        clip_coupon_amount=node.clip_coupon_amount,
        strike_price=node.strike_price,
        all_time_low=node.all_time_low,
        sns_eligible=node.sns_eligible,
        pg_stockup_eligible=node.pg_stockup_eligible,
        b2g1_eligible=node.b2g1_eligible,
        selected_in_stack=node.selected_in_stack,
        snagged=node.snagged,
        unit_name=node.unit_name,
        unit_quantity=node.unit_quantity,
        price_history=history,
        scout_notes=node.scout_notes,
        effective_price=eff,
        unit_effective_price=unit_eff,
        discount_pct_off_msrp=pct_off,
        deal_grade_code=grade_code,
        deal_grade_label=grade_label,
        is_below_strike=(eff <= node.strike_price and not node.is_trap_warning),
        amazon_url=(
            f"https://www.amazon.com/dp/{asin}?psc=1"
            if (asin := extract_amazon_asin(node.asin_or_sku))
            else f"https://www.amazon.com/s?k={node.amazon_query}&rh=p_6%3AATVPDKIKX0DER"
        ),
        camel_url=(
            f"https://camelcamelcamel.com/product/{asin}"
            if (asin := extract_amazon_asin(node.asin_or_sku))
            else f"https://camelcamelcamel.com/search?sq={node.amazon_query}"
        ),
    )


def enrich_mission(mission: ShoppingMission, sns_tier_rate: float = 0.15) -> ShoppingMissionRead:
    options_dto = [enrich_option_node(opt, sns_tier_rate=sns_tier_rate) for opt in mission.options]
    return ShoppingMissionRead(
        id=mission.id or 0,
        slug=mission.slug,
        title=mission.title,
        raw_intent=mission.raw_intent,
        node_type=mission.node_type,
        category_tag=mission.category_tag,
        icon=mission.icon,
        decision_framing=mission.decision_framing,
        created_at=mission.created_at,
        options=options_dto,
    )


def solve_combinatoric_stack(all_options: List[DealOptionNode]) -> CombinatoricStackSummary:
    """Computes Subscribe & Save 5-item step function, P&G $100->$25 promo, and 3-for-2 B2G1 math."""
    sns_selected = [o for o in all_options if o.sns_eligible and o.selected_in_stack]
    sns_count = len(sns_selected)
    sns_rate = 0.15 if sns_count >= 5 else (0.05 if sns_count >= 1 else 0.0)

    c_msrp = sum(o.msrp for o in sns_selected)
    c_sale = sum(o.current_price for o in sns_selected)
    c_coupon = sum(o.clip_coupon_amount for o in sns_selected)
    c_sns = sum(o.current_price * sns_rate for o in sns_selected)
    pg_sub = sum(o.current_price for o in sns_selected if o.pg_stockup_eligible)
    pg_credit = 25.0 if pg_sub >= 100.0 else 0.0
    pg_needed = max(0.0, round(100.0 - pg_sub, 2))
    c_net = max(0.0, round(c_sale - c_coupon - c_sns - pg_credit, 2))
    c_eff_pct = int(round(((c_msrp - c_net) / c_msrp) * 100)) if c_msrp > 0 else 0

    # 3-for-2 (Buy 2, Get 1 Free) Board Game & Puzzle Solver
    b2g1_selected = [o for o in all_options if o.b2g1_eligible and o.selected_in_stack]
    b_count = len(b2g1_selected)
    b_msrp = round(sum(o.msrp for o in b2g1_selected), 2)
    b_sale = round(sum(o.current_price for o in b2g1_selected), 2)

    if b_count >= 3:
        sorted_prices = sorted(o.current_price for o in b2g1_selected)
        # Every group of 3 gets 1 free item
        num_free = b_count // 3
        free_deduct = round(sum(sorted_prices[:num_free]), 2)
        spread = sorted_prices[-1] - sorted_prices[0]
        harmony_score = max(40, min(99, int(round(100 - spread * 3.2))))
        if spread <= 4.5:
            harmony_verdict = f"🔥 {harmony_score}/100 Optimal Price Clustering (~32% extra off)"
        elif spread <= 9.5:
            harmony_verdict = f"✅ {harmony_score}/100 Good Bundle Spread (~26% extra off)"
        else:
            harmony_verdict = f"⚠️ {harmony_score}/100 Wide Price Spread (cheapest item drags discount)"
    else:
        free_deduct = 0.0
        harmony_score = 0
        needed = 3 - b_count
        harmony_verdict = f"Select {needed} more 3-for-2 eligible game(s) to unlock 1 FREE"

    b_net = round(b_sale - free_deduct, 2)

    return CombinatoricStackSummary(
        sns_active_count=sns_count,
        sns_tier_rate=sns_rate,
        sns_unlocked_15pct=(sns_count >= 5),
        pg_qualifying_subtotal=round(pg_sub, 2),
        pg_credit_unlocked=pg_credit,
        pg_amount_needed_for_credit=pg_needed,
        consumables_msrp_total=round(c_msrp, 2),
        consumables_sale_total=round(c_sale, 2),
        consumables_coupon_savings=round(c_coupon, 2),
        consumables_sns_savings=round(c_sns, 2),
        consumables_net_out_of_pocket=c_net,
        consumables_effective_discount_pct=c_eff_pct,
        b2g1_selected_count=b_count,
        b2g1_msrp_total=b_msrp,
        b2g1_sale_subtotal=b_sale,
        b2g1_free_item_deduction=free_deduct,
        b2g1_net_total=b_net,
        b2g1_harmony_score=harmony_score,
        b2g1_harmony_verdict=harmony_verdict,
    )


def build_amazon_cart_plan(
    all_options: List[DealOptionNode],
    scope: str = "recommended",
) -> AmazonCartBuilderPlan:
    """Builds a 1-click multi-ASIN Amazon cart URL + step-by-step coupon/promo checkout checklist."""
    sns_selected = [o for o in all_options if o.sns_eligible and o.selected_in_stack]
    sns_rate = 0.15 if len(sns_selected) >= 5 else (0.05 if len(sns_selected) >= 1 else 0.0)

    # Filter candidate nodes according to scope
    selected_nodes: List[DealOptionNode] = []
    seen_mission_xor = set()

    for node in all_options:
        if node.is_trap_warning or node.snagged:
            continue
        eff = compute_effective_price(node, sns_tier_rate=sns_rate)
        is_strike = eff <= node.strike_price

        if scope == "strike_only":
            if not is_strike:
                continue
        elif scope == "stack_only":
            if not node.selected_in_stack:
                continue
        else:
            # Default "recommended": include stack items + recommended branches (1 per XOR mission so we don't buy two vacuums)
            if node.selected_in_stack:
                pass
            elif node.is_recommended_branch:
                # For XOR missions with multiple recommended branches (like Dyson), pick the highest-discount/lowest-price recommended branch
                if node.mission_id in seen_mission_xor and not (node.sns_eligible or node.b2g1_eligible):
                    # Allow multiple recommended items in kitchen funnel, but avoid duplicate vacuums
                    if "dyson" in (node.branch_key or "").lower():
                        continue
                seen_mission_xor.add(node.mission_id)
            else:
                continue
        selected_nodes.append(node)

    direct_items: List[DealOptionRead] = []
    fallback_items: List[DealOptionRead] = []
    all_asins: List[str] = []
    sns_asins: List[str] = []
    b2g1_asins: List[str] = []

    for node in selected_nodes:
        dto = enrich_option_node(node, sns_tier_rate=sns_rate)
        asin = extract_amazon_asin(node.asin_or_sku)
        if asin:
            # Prefer direct product page /dp/{asin} link when a real ASIN is known
            dto.amazon_url = f"https://www.amazon.com/dp/{asin}?psc=1"
            direct_items.append(dto)
            if asin not in all_asins:
                all_asins.append(asin)
            if node.sns_eligible and asin not in sns_asins:
                sns_asins.append(asin)
            if node.b2g1_eligible and asin not in b2g1_asins:
                b2g1_asins.append(asin)
        else:
            fallback_items.append(dto)

    total_msrp = round(sum(o.msrp for o in selected_nodes), 2)
    total_sale = round(sum(o.current_price for o in selected_nodes), 2)
    total_coupons = round(sum(o.clip_coupon_amount or 0.0 for o in selected_nodes), 2)
    total_sns_disc = round(
        sum(o.current_price * sns_rate for o in selected_nodes if o.sns_eligible),
        2,
    )

    pg_sub = round(
        sum(o.current_price for o in selected_nodes if o.sns_eligible and o.pg_stockup_eligible),
        2,
    )
    pg_credit = 25.0 if pg_sub >= 100.0 else 0.0

    b2g1_in_plan = [o for o in selected_nodes if o.b2g1_eligible]
    if len(b2g1_in_plan) >= 3:
        sorted_b2g1 = sorted(o.current_price for o in b2g1_in_plan)
        b2g1_free = round(sum(sorted_b2g1[: len(b2g1_in_plan) // 3]), 2)
    else:
        b2g1_free = 0.0

    net_checkout = max(
        0.0,
        round(total_sale - total_coupons - total_sns_disc - pg_credit - b2g1_free, 2),
    )
    total_savings = max(0.0, round(total_msrp - net_checkout, 2))
    eff_pct = int(round((total_savings / total_msrp) * 100)) if total_msrp > 0 else 0

    # Generate actionable step-by-step checkout checklist
    steps: List[CartChecklistStep] = []
    step_no = 1

    coupon_nodes = [o for o in selected_nodes if (o.clip_coupon_amount or 0) > 0]
    if coupon_nodes:
        names = ", ".join(
            f"{o.title.split('(')[0].strip()} (-${o.clip_coupon_amount:.2f})"
            for o in coupon_nodes
        )
        steps.append(
            CartChecklistStep(
                step_number=step_no,
                title=f"Clip {len(coupon_nodes)} On-Page Green Coupons First (-${total_coupons:.2f})",
                detail=f"Before final checkout, click the on-page coupon checkbox on each product page: {names}.",
                badge=f"SAVE ${total_coupons:.2f}",
                category="coupon",
            )
        )
        step_no += 1

    sns_in_plan = [o for o in selected_nodes if o.sns_eligible]
    if sns_in_plan:
        tier_pct = int(round(sns_rate * 100))
        steps.append(
            CartChecklistStep(
                step_number=step_no,
                title=f"Activate {tier_pct}% Subscribe & Save Tier ({len(sns_in_plan)} Consumables)",
                detail=(
                    f"Group all {len(sns_in_plan)} household & health consumables into your next monthly S&S delivery date "
                    f"to unlock {tier_pct}% off (-${total_sns_disc:.2f}). You can cancel or skip future deliveries after shipment."
                ),
                badge=f"SAVE ${total_sns_disc:.2f}",
                category="sns",
            )
        )
        step_no += 1

    if pg_sub > 0:
        if pg_credit > 0:
            steps.append(
                CartChecklistStep(
                    step_number=step_no,
                    title="Verify $25 P&G Holiday Stock-Up Credit at Checkout",
                    detail=(
                        f"Your P&G qualifying subtotal is ${pg_sub:.2f} (exceeds $100 threshold across Metamucil, Bounty, Charmin, Cascade). "
                        "Confirm the '$25 P&G Holiday Promotional Credit' banner appears on the checkout review screen."
                    ),
                    badge="+$25.00 CREDIT",
                    category="pg",
                )
            )
        else:
            needed = round(100.0 - pg_sub, 2)
            steps.append(
                CartChecklistStep(
                    step_number=step_no,
                    title=f"Add ${needed:.2f} More in P&G Items to Unlock $25 Bonus Credit",
                    detail=f"Current P&G subtotal is ${pg_sub:.2f}/$100.00. Adding ${needed:.2f} more unlocks a $25 Amazon bounceback credit.",
                    badge=f"${needed:.2f} AWAY",
                    category="pg",
                )
            )
        step_no += 1

    if b2g1_in_plan:
        if b2g1_free > 0:
            steps.append(
                CartChecklistStep(
                    step_number=step_no,
                    title=f"Confirm 3-for-2 Board Game Promo Deducts -${b2g1_free:.2f}",
                    detail=(
                        f"Your {len(b2g1_in_plan)} price-clustered games/puzzles ($23.99-$26.49) automatically make the lowest-priced game "
                        f"FREE (-${b2g1_free:.2f}) in standard Amazon Cart checkout."
                    ),
                    badge=f"1 FREE (-${b2g1_free:.2f})",
                    category="b2g1",
                )
            )
        else:
            steps.append(
                CartChecklistStep(
                    step_number=step_no,
                    title=f"Select {3 - len(b2g1_in_plan)} More Game(s) for 3-for-2 Free Game",
                    detail="Amazon's Buy 2 Get 1 Free promo requires 3 qualifying board games or puzzles in the same cart order.",
                    badge="BUNDLE TIP",
                    category="b2g1",
                )
            )
        step_no += 1

    steps.append(
        CartChecklistStep(
            step_number=step_no,
            title="Verify 'Ships from and Sold by Amazon.com' on Hardware & Tools",
            detail=(
                "For DeWalt, Work Sharp, and Dyson items, confirm the seller is Amazon.com (not a 3rd-party reseller) "
                "to ensure full manufacturer warranty coverage and zero scalper markup."
            ),
            badge="WARRANTY CHECK",
            category="safety",
        )
    )

    return AmazonCartBuilderPlan(
        scope=scope,
        cart_add_url=_build_multi_asin_url(all_asins),
        sns_cart_add_url=_build_multi_asin_url(sns_asins),
        b2g1_cart_add_url=_build_multi_asin_url(b2g1_asins),
        direct_asin_count=len(direct_items),
        total_selected_count=len(selected_nodes),
        direct_asin_items=direct_items,
        search_fallback_items=fallback_items,
        total_msrp=total_msrp,
        total_sale_price=total_sale,
        total_coupon_savings=total_coupons,
        total_sns_savings=total_sns_disc,
        pg_credit_savings=pg_credit,
        b2g1_free_savings=b2g1_free,
        net_estimated_checkout=net_checkout,
        total_savings=total_savings,
        effective_discount_pct=eff_pct,
        checklist_steps=steps,
    )


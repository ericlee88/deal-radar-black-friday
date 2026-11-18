import json
from typing import List
from app.models import DealOptionNode, ShoppingMission
from app.schemas import CombinatoricStackSummary, DealOptionRead, ShoppingMissionRead


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
        amazon_url=f"https://www.amazon.com/s?k={node.amazon_query}&rh=p_6%3AATVPDKIKX0DER",
        camel_url=f"https://camelcamelcamel.com/search?sq={node.amazon_query}",
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

from typing import List
from sqlmodel import Session, select
from app.database import engine
from app.engine.deal_scorer import compute_effective_price
from app.models import DealOptionNode, WebhookAlertLog
from app.providers.notifier import webhook_notifier
from app.providers.price_provider import price_provider


async def run_price_poll_cycle(
    session: Session, simulate_drop: bool = False
) -> List[WebhookAlertLog]:
    """Polls price updates across all active DealOptionNodes and dispatches webhook alerts
    whenever an item crosses its strike threshold.
    """
    nodes = session.exec(select(DealOptionNode)).all()
    sns_count = sum(1 for n in nodes if n.sns_eligible and n.selected_in_stack)
    sns_rate = 0.15 if sns_count >= 5 else (0.05 if sns_count >= 1 else 0.0)

    dispatched_alerts: List[WebhookAlertLog] = []
    for node in nodes:
        if node.snagged or node.is_trap_warning:
            continue
        prev_eff = compute_effective_price(node, sns_tier_rate=sns_rate)
        tick = await price_provider.refresh_node_price(node, simulate_drop=simulate_drop)
        node.current_price = tick["current_price"]
        node.avg_90d_price = tick["avg_90d_price"]
        if "clip_coupon_amount" in tick and tick["clip_coupon_amount"] is not None:
            node.clip_coupon_amount = tick["clip_coupon_amount"]
        session.add(node)

        new_eff = compute_effective_price(node, sns_tier_rate=sns_rate)
        # Trigger alert if it newly crossed strike threshold OR if simulate_drop was requested and it's below strike
        if new_eff <= node.strike_price and (prev_eff > node.strike_price or simulate_drop):
            log_entry = await webhook_notifier.send_strike_alert(
                session=session,
                node=node,
                effective_price=new_eff,
                custom_note=f"Provider: {tick['provider']}",
            )
            dispatched_alerts.append(log_entry)

    session.commit()
    return dispatched_alerts


async def scheduled_poll_job() -> None:
    with Session(engine) as session:
        await run_price_poll_cycle(session, simulate_drop=False)

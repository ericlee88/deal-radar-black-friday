"""Export Deal Radar SQLite state to a static JSON snapshot for GitHub Pages.

Usage:
    uv run python scripts/export_snapshot.py          # export current/seeded state
    uv run python scripts/export_snapshot.py --poll   # poll live Amazon prices first, then export
"""

from __future__ import annotations

import argparse
import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

from sqlmodel import Session, select

from app.database import engine, init_db
from app.engine.deal_scorer import enrich_option_node
from app.engine.scheduler import run_price_poll_cycle
from app.models import DealOptionNode, ShoppingMission, WebhookAlertLog
from app.seed import seed_initial_missions

REPO_ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_OUTPUT = REPO_ROOT / "frontend" / "web" / "data" / "deals_snapshot.json"
USER_STATE_FILE = REPO_ROOT / "data" / "user_state.json"
PRODUCT_IMAGES_DIR = REPO_ROOT / "frontend" / "web" / "images" / "products"


def _merge_user_state_if_present(session: Session) -> None:
    """If the user enabled GitHub Repo Sync, merge their overrides & custom missions before polling."""
    if not USER_STATE_FILE.is_file():
        return
    try:
        payload = json.loads(USER_STATE_FILE.read_text(encoding="utf-8"))
    except Exception:
        return

    missions_data = payload.get("missions")
    if not isinstance(missions_data, list):
        return

    existing_missions = {m.slug: m for m in session.exec(select(ShoppingMission)).all()}
    existing_options = {o.id: o for o in session.exec(select(DealOptionNode)).all()}

    for m_data in missions_data:
        slug = m_data.get("slug") or ""
        mission = existing_missions.get(slug)
        if mission is None:
            mission = ShoppingMission(
                slug=slug or f"custom-{int(datetime.now(timezone.utc).timestamp())}",
                title=m_data.get("title", "Custom Mission"),
                raw_intent=m_data.get("raw_intent", ""),
                node_type=m_data.get("node_type", "CATEGORY_FUNNEL"),
                category_tag=m_data.get("category_tag", "general"),
                icon=m_data.get("icon", ""),
                decision_framing=m_data.get("decision_framing", ""),
            )
            session.add(mission)
            session.flush()
            existing_missions[mission.slug] = mission

        for opt_data in m_data.get("options", []):
            opt_id = opt_data.get("id")
            node = existing_options.get(opt_id) if isinstance(opt_id, int) else None
            if node is not None:
                if "strike_price" in opt_data:
                    node.strike_price = float(opt_data["strike_price"])
                if "clip_coupon_amount" in opt_data:
                    node.clip_coupon_amount = float(opt_data["clip_coupon_amount"])
                if "sns_eligible" in opt_data:
                    node.sns_eligible = bool(opt_data["sns_eligible"])
                if "selected_in_stack" in opt_data:
                    node.selected_in_stack = bool(opt_data["selected_in_stack"])
                if "snagged" in opt_data:
                    node.snagged = bool(opt_data["snagged"])
                session.add(node)
            else:
                new_node = DealOptionNode(
                    mission_id=mission.id,
                    branch_key=opt_data.get("branch_key", "custom_item"),
                    branch_label=opt_data.get("branch_label", "User Added"),
                    is_recommended_branch=bool(opt_data.get("is_recommended_branch", True)),
                    is_trap_warning=bool(opt_data.get("is_trap_warning", False)),
                    title=opt_data.get("title", "Custom Amazon Item"),
                    asin_or_sku=opt_data.get("asin_or_sku", ""),
                    amazon_query=opt_data.get("amazon_query", ""),
                    msrp=float(opt_data.get("msrp", opt_data.get("current_price", 50.0))),
                    avg_90d_price=float(opt_data.get("avg_90d_price", opt_data.get("current_price", 45.0))),
                    current_price=float(opt_data.get("current_price", 45.0)),
                    clip_coupon_amount=float(opt_data.get("clip_coupon_amount", 0.0)),
                    strike_price=float(opt_data.get("strike_price", 35.0)),
                    all_time_low=float(opt_data.get("all_time_low", 30.0)),
                    sns_eligible=bool(opt_data.get("sns_eligible", False)),
                    pg_stockup_eligible=bool(opt_data.get("pg_stockup_eligible", False)),
                    b2g1_eligible=bool(opt_data.get("b2g1_eligible", False)),
                    selected_in_stack=bool(opt_data.get("selected_in_stack", False)),
                    snagged=bool(opt_data.get("snagged", False)),
                    unit_name=opt_data.get("unit_name", "item"),
                    unit_quantity=float(opt_data.get("unit_quantity", 1.0)),
                    price_history_json=json.dumps(opt_data.get("price_history", [45.0])),
                    scout_notes=opt_data.get("scout_notes", "Added via GitHub Pages sync."),
                )
                session.add(new_node)
    session.commit()


def _build_snapshot(session: Session) -> Dict[str, Any]:
    all_opts = session.exec(select(DealOptionNode)).all()
    sns_count = sum(1 for o in all_opts if o.sns_eligible and o.selected_in_stack)
    sns_rate = 0.15 if sns_count >= 5 else (0.05 if sns_count >= 1 else 0.0)

    missions = session.exec(select(ShoppingMission).order_by(ShoppingMission.id)).all()
    missions_out: List[Dict[str, Any]] = []
    image_map: Dict[str, str] = {}

    for m in missions:
        opts = session.exec(
            select(DealOptionNode)
            .where(DealOptionNode.mission_id == m.id)
            .order_by(DealOptionNode.id)
        ).all()
        enriched_opts = []
        for o in opts:
            enriched = enrich_option_node(o, sns_tier_rate=sns_rate)
            enriched_opts.append(enriched.model_dump())
            branch_img = PRODUCT_IMAGES_DIR / f"{o.branch_key}.jpg"
            opt_img = PRODUCT_IMAGES_DIR / f"opt_{o.id}.jpg"
            if branch_img.is_file():
                image_map[str(o.id)] = f"images/products/{o.branch_key}.jpg"
                image_map[o.branch_key] = f"images/products/{o.branch_key}.jpg"
            elif opt_img.is_file():
                image_map[str(o.id)] = f"images/products/opt_{o.id}.jpg"

        missions_out.append(
            {
                "id": m.id,
                "slug": m.slug,
                "title": m.title,
                "raw_intent": m.raw_intent,
                "node_type": m.node_type,
                "category_tag": m.category_tag,
                "icon": m.icon,
                "decision_framing": m.decision_framing,
                "options": enriched_opts,
            }
        )

    alerts = session.exec(
        select(WebhookAlertLog).order_by(WebhookAlertLog.id.desc()).limit(30)
    ).all()
    alerts_out = [
        {
            "id": a.id,
            "option_id": a.option_id,
            "option_title": a.option_title,
            "effective_price": a.effective_price,
            "strike_price": a.strike_price,
            "channel": a.channel,
            "status": a.status,
            "created_at": a.created_at.isoformat() if hasattr(a.created_at, "isoformat") else str(a.created_at),
        }
        for a in alerts
    ]

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "missions": missions_out,
        "alerts": alerts_out,
        "image_map": image_map,
    }


async def run_export(poll_live: bool) -> None:
    from app.main import _SEED_ASIN_BACKFILL

    init_db()
    with Session(engine) as session:
        seed_initial_missions(session, force_reset=False)
        for node in session.exec(select(DealOptionNode)).all():
            verified = _SEED_ASIN_BACKFILL.get(node.branch_key)
            if verified and node.asin_or_sku != verified:
                node.asin_or_sku = verified
                session.add(node)
        session.commit()
        _merge_user_state_if_present(session)
        if poll_live:
            alerts = await run_price_poll_cycle(session, simulate_drop=False)
            print(f"Live Amazon poll complete. Dispatched {len(alerts)} strike alerts.")
        snapshot = _build_snapshot(session)

    SNAPSHOT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    SNAPSHOT_OUTPUT.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")
    print(
        f"Wrote static snapshot to {SNAPSHOT_OUTPUT} "
        f"({len(snapshot['missions'])} missions, {len(snapshot['image_map'])} image entries)."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Deal Radar static JSON snapshot.")
    parser.add_argument(
        "--poll",
        action="store_true",
        help="Run a live Amazon price poll cycle before exporting.",
    )
    args = parser.parse_args()
    asyncio.run(run_export(poll_live=args.poll))


if __name__ == "__main__":
    main()

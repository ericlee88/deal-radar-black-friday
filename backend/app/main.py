from contextlib import asynccontextmanager
import json
from typing import Dict, Any, List
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import Session, select

from app.config import settings
from app.database import engine, get_session, init_db
from app.engine.deal_scorer import (
    compute_effective_price,
    enrich_mission,
    enrich_option_node,
    solve_combinatoric_stack,
)
from app.engine.scheduler import run_price_poll_cycle, scheduled_poll_job
from app.models import DealOptionNode, ShoppingMission, WebhookAlertLog
from app.providers.llm_provider import llm_resolver
from app.providers.notifier import webhook_notifier
from app.schemas import (
    CombinatoricStackSummary,
    DealOptionPatch,
    DealOptionRead,
    IntentTranslateRequest,
    ShoppingMissionRead,
    WebhookTestRequest,
)
from app.seed import seed_initial_missions

scheduler = AsyncIOScheduler()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    with Session(engine) as session:
        seed_initial_missions(session, force_reset=False)

    if settings.enable_scheduler:
        scheduler.add_job(
            scheduled_poll_job,
            "interval",
            minutes=settings.poll_interval_minutes,
            id="price_poll_job",
            replace_existing=True,
        )
        scheduler.start()
    yield
    if scheduler.running:
        scheduler.shutdown(wait=False)


from fastapi.middleware.gzip import GZipMiddleware

app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_client_logs: List[Dict[str, Any]] = []


@app.post("/api/client-log")
def record_client_log(payload: Dict[str, Any]) -> Dict[str, str]:
    print(f"[CLIENT-LOG] {json.dumps(payload)}", flush=True)
    _client_logs.append(payload)
    return {"status": "logged"}


@app.get("/api/client-logs")
def get_client_logs() -> List[Dict[str, Any]]:
    return _client_logs



def _current_sns_rate(session: Session) -> float:
    all_opts = session.exec(select(DealOptionNode)).all()
    sns_count = sum(1 for o in all_opts if o.sns_eligible and o.selected_in_stack)
    return 0.15 if sns_count >= 5 else (0.05 if sns_count >= 1 else 0.0)


@app.get("/api/health")
def get_health(session: Session = Depends(get_session)) -> Dict[str, Any]:
    missions_count = len(session.exec(select(ShoppingMission)).all())
    options_count = len(session.exec(select(DealOptionNode)).all())
    return {
        "status": "ok",
        "environment": settings.environment,
        "active_llm_provider": settings.active_llm_mode,
        "active_price_provider": settings.active_price_mode,
        "webhook_provider": settings.webhook_provider,
        "missions_count": missions_count,
        "options_count": options_count,
    }


@app.get("/api/missions", response_model=List[ShoppingMissionRead])
def list_missions(session: Session = Depends(get_session)) -> List[ShoppingMissionRead]:
    sns_rate = _current_sns_rate(session)
    missions = session.exec(select(ShoppingMission).order_by(ShoppingMission.id)).all()
    return [enrich_mission(m, sns_tier_rate=sns_rate) for m in missions]


@app.post("/api/missions/from-intent", response_model=ShoppingMissionRead)
async def create_mission_from_intent(
    req: IntentTranslateRequest,
    session: Session = Depends(get_session),
) -> ShoppingMissionRead:
    """Translates a fuzzy or specific user shopping intent via LLM (or deterministic fallback)
    into a Polymorphic ShoppingMission DAG node and persists it.
    """
    spec = await llm_resolver.translate_intent(req.raw_intent, req.budget_hint)

    # Ensure unique slug
    base_slug = spec.slug
    slug = base_slug
    counter = 1
    while session.exec(select(ShoppingMission).where(ShoppingMission.slug == slug)).first():
        counter += 1
        slug = f"{base_slug}-{counter}"

    mission = ShoppingMission(
        slug=slug,
        title=spec.title,
        raw_intent=req.raw_intent,
        node_type=spec.node_type,
        category_tag=spec.category_tag,
        icon=spec.icon,
        decision_framing=spec.decision_framing,
    )
    session.add(mission)
    session.flush()

    for opt_spec in spec.options:
        history = [
            opt_spec.msrp,
            round((opt_spec.msrp + opt_spec.avg_90d_price) / 2, 2),
            opt_spec.avg_90d_price,
            opt_spec.current_price,
        ]
        opt = DealOptionNode(
            mission_id=mission.id,
            branch_key=opt_spec.branch_key,
            branch_label=opt_spec.branch_label,
            is_recommended_branch=opt_spec.is_recommended_branch,
            is_trap_warning=opt_spec.is_trap_warning,
            title=opt_spec.title,
            asin_or_sku=opt_spec.asin_or_sku,
            amazon_query=opt_spec.amazon_query,
            msrp=opt_spec.msrp,
            avg_90d_price=opt_spec.avg_90d_price,
            current_price=opt_spec.current_price,
            clip_coupon_amount=opt_spec.clip_coupon_amount,
            strike_price=opt_spec.strike_price,
            all_time_low=opt_spec.all_time_low,
            sns_eligible=opt_spec.sns_eligible,
            pg_stockup_eligible=opt_spec.pg_stockup_eligible,
            b2g1_eligible=opt_spec.b2g1_eligible,
            selected_in_stack=opt_spec.sns_eligible or opt_spec.b2g1_eligible,
            unit_name=opt_spec.unit_name,
            unit_quantity=opt_spec.unit_quantity,
            price_history_json=json.dumps(history),
            scout_notes=opt_spec.scout_notes,
        )
        session.add(opt)

    session.commit()
    session.refresh(mission)
    sns_rate = _current_sns_rate(session)
    return enrich_mission(mission, sns_tier_rate=sns_rate)


@app.delete("/api/missions/{mission_id}")
def delete_mission(mission_id: int, session: Session = Depends(get_session)) -> Dict[str, Any]:
    mission = session.get(ShoppingMission, mission_id)
    if not mission:
        raise HTTPException(status_code=404, detail="Mission not found")
    session.delete(mission)
    session.commit()
    return {"deleted": mission_id}


@app.patch("/api/options/{option_id}", response_model=DealOptionRead)
async def update_option_node(
    option_id: int,
    patch: DealOptionPatch,
    session: Session = Depends(get_session),
) -> DealOptionRead:
    node = session.get(DealOptionNode, option_id)
    if not node:
        raise HTTPException(status_code=404, detail="Option node not found")

    sns_rate_before = _current_sns_rate(session)
    prev_eff = compute_effective_price(node, sns_tier_rate=sns_rate_before)

    if patch.current_price is not None:
        node.current_price = patch.current_price
    if patch.clip_coupon_amount is not None:
        node.clip_coupon_amount = patch.clip_coupon_amount
    if patch.strike_price is not None:
        node.strike_price = patch.strike_price
    if patch.sns_eligible is not None:
        node.sns_eligible = patch.sns_eligible
    if patch.selected_in_stack is not None:
        node.selected_in_stack = patch.selected_in_stack
    if patch.snagged is not None:
        node.snagged = patch.snagged

    session.add(node)
    session.commit()
    session.refresh(node)

    sns_rate_after = _current_sns_rate(session)
    new_eff = compute_effective_price(node, sns_tier_rate=sns_rate_after)

    # Fire webhook alert if manual price update crossed below strike threshold
    if (
        not node.is_trap_warning
        and new_eff <= node.strike_price
        and prev_eff > node.strike_price
    ):
        await webhook_notifier.send_strike_alert(
            session=session,
            node=node,
            effective_price=new_eff,
            custom_note="Triggered via Live Price Check",
        )

    return enrich_option_node(node, sns_tier_rate=sns_rate_after)


@app.get("/api/stack-summary", response_model=CombinatoricStackSummary)
def get_combinatoric_stack_summary(
    session: Session = Depends(get_session),
) -> CombinatoricStackSummary:
    all_opts = session.exec(select(DealOptionNode)).all()
    return solve_combinatoric_stack(list(all_opts))


@app.post("/api/poller/trigger")
async def trigger_price_poll(
    simulate_drop: bool = False,
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    alerts = await run_price_poll_cycle(session, simulate_drop=simulate_drop)
    return {
        "polled": True,
        "simulate_drop": simulate_drop,
        "alerts_dispatched": len(alerts),
    }


@app.get("/api/alerts", response_model=List[WebhookAlertLog])
def list_webhook_alerts(session: Session = Depends(get_session)) -> List[WebhookAlertLog]:
    return list(
        session.exec(
            select(WebhookAlertLog).order_by(WebhookAlertLog.id.desc()).limit(30)
        ).all()
    )


@app.post("/api/alerts/test", response_model=WebhookAlertLog)
async def trigger_test_webhook(
    req: WebhookTestRequest,
    session: Session = Depends(get_session),
) -> WebhookAlertLog:
    node = None
    if req.option_id:
        node = session.get(DealOptionNode, req.option_id)
    if not node:
        node = session.exec(select(DealOptionNode)).first()
    if not node:
        raise HTTPException(status_code=404, detail="No option nodes available")

    sns_rate = _current_sns_rate(session)
    eff = compute_effective_price(node, sns_tier_rate=sns_rate)
    return await webhook_notifier.send_strike_alert(
        session=session,
        node=node,
        effective_price=eff,
        custom_note=req.custom_message or "Manual Test Alert from Deal Radar",
    )


@app.post("/api/reset")
def reset_database_seed(session: Session = Depends(get_session)) -> Dict[str, str]:
    seed_initial_missions(session, force_reset=True)
    return {"status": "reset_complete"}


# Serve compiled Flutter Web frontend from the same FastAPI server if present
import os
from pathlib import Path
from fastapi.staticfiles import StaticFiles

_flutter_web_dir = Path(__file__).resolve().parents[2] / "frontend" / "build" / "web"
if _flutter_web_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(_flutter_web_dir), html=True), name="flutter_web")


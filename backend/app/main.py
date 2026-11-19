from contextlib import asynccontextmanager
import json
from pathlib import Path
from typing import Dict, Any, List
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import Session, select

from app.config import settings
from app.database import engine, get_session, init_db
from app.engine.deal_scorer import (
    build_amazon_cart_plan,
    compute_effective_price,
    enrich_mission,
    enrich_option_node,
    extract_amazon_asin,
    solve_combinatoric_stack,
)
from app.engine.scheduler import run_price_poll_cycle, scheduled_poll_job
from app.models import DealOptionNode, ShoppingMission, WebhookAlertLog
from app.providers.llm_provider import llm_resolver
from app.providers.notifier import webhook_notifier
from app.schemas import (
    AmazonCartBuilderPlan,
    CombinatoricStackSummary,
    DealOptionPatch,
    DealOptionRead,
    IntentTranslateRequest,
    ProviderSettingsRead,
    ProviderSettingsUpdate,
    ShoppingMissionRead,
    WebhookTestRequest,
)
from app.seed import seed_initial_missions

scheduler = AsyncIOScheduler()

_SEED_ASIN_BACKFILL = {
    "rice_basin_304": "B089G45BF7 / SUS304-BASIN-2IN1",
    "path_a_adapter_split": "B016K1UD0E / DCA1820 + DCB205-2C",
    "path_b_new_hammer_drill": "B09YY1WTHJ / DCD805D2",
    "dyson_car_boat": "B0C2J7X5WR / DYSON-CAR-BOAT",
    "dyson_v8_convertible": "B0B5HJJ7K7 / DYSON-V8-CYCLONE",
    "dyson_v12_slim": "B0B1V2G7R2 / DYSON-V12-SLIM",
    "diy_metamucil_vital": "B00K6JUG4K / METAMUCIL-180 + VITAL-20OZ",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    with Session(engine) as session:
        seed_initial_missions(session, force_reset=False)
        for node in session.exec(select(DealOptionNode)).all():
            if node.branch_key in _SEED_ASIN_BACKFILL and not extract_amazon_asin(node.asin_or_sku):
                node.asin_or_sku = _SEED_ASIN_BACKFILL[node.branch_key]
                session.add(node)
        session.commit()

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

from fastapi.responses import Response

_client_logs: List[Dict[str, Any]] = []
_CANVASKIT_CHUNK_SIZE = 1_600_000


@app.post("/api/client-log")
def record_client_log(payload: Dict[str, Any]) -> Dict[str, str]:
    print(f"[CLIENT-LOG] {json.dumps(payload)}", flush=True)
    _client_logs.append(payload)
    return {"status": "logged"}


@app.get("/api/client-logs")
def get_client_logs() -> List[Dict[str, Any]]:
    return _client_logs


@app.delete("/api/client-logs")
def clear_client_logs() -> Dict[str, str]:
    _client_logs.clear()
    return {"status": "cleared"}


@app.get("/api/canvaskit/chunk/{chunk_id}")
def get_canvaskit_wasm_chunk(chunk_id: int) -> Response:
    """Serves canvaskit.wasm in 1.6MB slices so preview proxies with a 4MiB response ceiling never truncate WASM."""
    wasm_path = Path(__file__).resolve().parents[2] / "frontend" / "build" / "web" / "canvaskit" / "canvaskit.wasm"
    if not wasm_path.is_file():
        raise HTTPException(status_code=404, detail="canvaskit.wasm not built")
    data = wasm_path.read_bytes()
    start = chunk_id * _CANVASKIT_CHUNK_SIZE
    if start >= len(data) or chunk_id < 0:
        return Response(content=b"", media_type="application/octet-stream")
    end = min(len(data), start + _CANVASKIT_CHUNK_SIZE)
    return Response(
        content=data[start:end],
        media_type="application/octet-stream",
        headers={"Cache-Control": "public, max-age=3600"},
    )


import re as _re
import urllib.request as _urlreq

_PRODUCT_IMAGES_DIR = Path(__file__).resolve().parents[2] / "frontend" / "web" / "images" / "products"
_PRODUCT_IMAGE_CACHE: Dict[int, bytes] = {}


def _fetch_amazon_product_jpeg(node: DealOptionNode) -> bytes:
    """Resolves a real Amazon product photo from bundled cache or live Amazon CDN by ASIN / search query."""
    _PRODUCT_IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    # 1. Check pre-downloaded branch_key file (e.g. spatula_mercer.jpg)
    branch_file = _PRODUCT_IMAGES_DIR / f"{node.branch_key}.jpg"
    if branch_file.is_file() and branch_file.stat().st_size > 1000:
        return branch_file.read_bytes()

    # 2. Check cached option_id file
    opt_file = _PRODUCT_IMAGES_DIR / f"opt_{node.id}.jpg"
    if opt_file.is_file() and opt_file.stat().st_size > 1000:
        return opt_file.read_bytes()

    # 3. Live scrape from Amazon product page or search page
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "en-US,en;q=0.9",
    }
    img_url = None
    asin = extract_amazon_asin(node.asin_or_sku)
    if asin:
        try:
            req = _urlreq.Request(f"https://www.amazon.com/dp/{asin}", headers=headers)
            html = _urlreq.urlopen(req, timeout=7).read().decode("utf-8", errors="ignore")
            m = _re.search(r'id="landingImage"[^>]*src="(https://m\.media-amazon\.com/images/I/[^"]+)"', html)
            if not m:
                m = _re.search(r'"hiRes":"(https://m\.media-amazon\.com/images/I/[^"]+)"', html)
            if m:
                img_url = m.group(1)
        except Exception:
            pass

    if not img_url and node.amazon_query:
        try:
            req = _urlreq.Request(f"https://www.amazon.com/s?k={node.amazon_query}", headers=headers)
            html = _urlreq.urlopen(req, timeout=7).read().decode("utf-8", errors="ignore")
            m = _re.search(r'class="s-image"[^>]*src="(https://m\.media-amazon\.com/images/I/[^"]+\.jpg)"', html)
            if m:
                img_url = m.group(1)
        except Exception:
            pass

    if img_url:
        base_m = _re.match(r"(https://m\.media-amazon\.com/images/I/[A-Za-z0-9%+_-]+?)\.", img_url)
        if base_m:
            img_url = base_m.group(1) + "._AC_SX679_.jpg"
        try:
            img_bytes = _urlreq.urlopen(
                _urlreq.Request(img_url, headers={"User-Agent": "Mozilla/5.0"}),
                timeout=7,
            ).read()
            if len(img_bytes) > 1000:
                opt_file.write_bytes(img_bytes)
                return img_bytes
        except Exception:
            pass

    raise HTTPException(status_code=404, detail="Product image not available")


@app.get("/api/product-image/{option_id}")
def get_product_image(
    option_id: int,
    session: Session = Depends(get_session),
) -> Response:
    if option_id in _PRODUCT_IMAGE_CACHE:
        return Response(
            content=_PRODUCT_IMAGE_CACHE[option_id],
            media_type="image/jpeg",
            headers={"Cache-Control": "public, max-age=86400"},
        )
    node = session.get(DealOptionNode, option_id)
    if not node:
        raise HTTPException(status_code=404, detail="Option not found")
    img_bytes = _fetch_amazon_product_jpeg(node)
    _PRODUCT_IMAGE_CACHE[option_id] = img_bytes
    return Response(
        content=img_bytes,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=86400"},
    )





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


@app.get("/api/cart-plan", response_model=AmazonCartBuilderPlan)
def get_amazon_cart_plan(
    scope: str = "recommended",
    session: Session = Depends(get_session),
) -> AmazonCartBuilderPlan:
    all_opts = session.exec(select(DealOptionNode).order_by(DealOptionNode.id)).all()
    return build_amazon_cart_plan(list(all_opts), scope=scope)


def _mask_secret(secret: Any) -> str:
    if not secret:
        return "Not configured"
    s = str(secret).strip()
    if len(s) <= 6:
        return "***"
    return f"{s[:4]}...{s[-3:]}"


def _build_settings_read() -> ProviderSettingsRead:
    return ProviderSettingsRead(
        llm_provider=settings.llm_provider,
        active_llm_mode=settings.active_llm_mode,
        gemini_api_key_set=bool(settings.gemini_api_key),
        gemini_api_key_preview=_mask_secret(settings.gemini_api_key),
        gemini_model=settings.gemini_model,
        openai_api_key_set=bool(settings.openai_api_key),
        openai_api_key_preview=_mask_secret(settings.openai_api_key),
        openai_model=settings.openai_model,
        price_provider=settings.price_provider,
        active_price_mode=settings.active_price_mode,
        keepa_api_key_set=bool(settings.keepa_api_key),
        keepa_api_key_preview=_mask_secret(settings.keepa_api_key),
        webhook_provider=settings.webhook_provider,
        webhook_url=settings.webhook_url,
        telegram_bot_token_set=bool(settings.telegram_bot_token),
        telegram_chat_id=settings.telegram_chat_id,
        poll_interval_minutes=settings.poll_interval_minutes,
    )


@app.get("/api/settings", response_model=ProviderSettingsRead)
def get_provider_settings() -> ProviderSettingsRead:
    return _build_settings_read()


@app.patch("/api/settings", response_model=ProviderSettingsRead)
def update_provider_settings(patch: ProviderSettingsUpdate) -> ProviderSettingsRead:
    if patch.llm_provider in ("auto", "mock", "gemini", "openai"):
        settings.llm_provider = patch.llm_provider  # type: ignore[assignment]
    if patch.gemini_api_key is not None:
        val = patch.gemini_api_key.strip()
        settings.gemini_api_key = val if val else None
    if patch.gemini_model is not None and patch.gemini_model.strip():
        settings.gemini_model = patch.gemini_model.strip()
    if patch.openai_api_key is not None:
        val = patch.openai_api_key.strip()
        settings.openai_api_key = val if val else None
    if patch.openai_model is not None and patch.openai_model.strip():
        settings.openai_model = patch.openai_model.strip()
    if patch.price_provider in ("auto", "mock", "keepa"):
        settings.price_provider = patch.price_provider  # type: ignore[assignment]
    if patch.keepa_api_key is not None:
        val = patch.keepa_api_key.strip()
        settings.keepa_api_key = val if val else None
    if patch.webhook_provider in ("none", "discord", "slack", "telegram", "ntfy", "generic"):
        settings.webhook_provider = patch.webhook_provider  # type: ignore[assignment]
    if patch.webhook_url is not None:
        val = patch.webhook_url.strip()
        settings.webhook_url = val if val else None
    if patch.telegram_bot_token is not None:
        val = patch.telegram_bot_token.strip()
        settings.telegram_bot_token = val if val else None
    if patch.telegram_chat_id is not None:
        val = patch.telegram_chat_id.strip()
        settings.telegram_chat_id = val if val else None
    if patch.poll_interval_minutes is not None and patch.poll_interval_minutes >= 1:
        settings.poll_interval_minutes = patch.poll_interval_minutes
    return _build_settings_read()



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


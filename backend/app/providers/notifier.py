import json
import httpx
from sqlmodel import Session
from app.config import settings
from app.models import DealOptionNode, WebhookAlertLog


class WebhookNotifier:
    """Dispatches strike-threshold notifications to Telegram, Discord, Slack, ntfy.sh, or Generic Webhook.

    Always records an audit entry in `WebhookAlertLog` so alerts are inspectable in the UI.
    """

    async def send_strike_alert(
        self,
        session: Session,
        node: DealOptionNode,
        effective_price: float,
        custom_note: str = "",
    ) -> WebhookAlertLog:
        pct_off = int(round(((node.msrp - effective_price) / node.msrp) * 100)) if node.msrp > 0 else 0
        amz_url = f"https://www.amazon.com/s?k={node.amazon_query}&rh=p_6%3AATVPDKIKX0DER"
        headline = (
            f"🔥 STRIKE TARGET HIT: {node.title} is now ${effective_price:.2f} "
            f"(Strike: ${node.strike_price:.2f} | MSRP: ${node.msrp:.2f}, -{pct_off}%)"
        )
        if custom_note:
            headline += f" — {custom_note}"

        channel = settings.webhook_provider
        status = "logged_locally"
        payload_dict = {
            "event": "STRIKE_PRICE_CROSSED",
            "title": node.title,
            "sku": node.asin_or_sku,
            "effective_price": effective_price,
            "strike_price": node.strike_price,
            "msrp": node.msrp,
            "discount_pct": pct_off,
            "amazon_url": amz_url,
            "message": headline,
        }

        if channel == "telegram" and settings.telegram_bot_token and settings.telegram_chat_id:
            tg_url = f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage"
            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    resp = await client.post(
                        tg_url,
                        json={
                            "chat_id": settings.telegram_chat_id,
                            "text": f"{headline}\n{amz_url}",
                        },
                    )
                    status = f"sent_http_{resp.status_code}"
            except Exception as exc:
                status = f"error: {type(exc).__name__}"
        elif channel in ("discord", "slack", "ntfy", "generic") and settings.webhook_url:
            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    if channel == "discord":
                        body = {"content": f"{headline}\n<{amz_url}>"}
                    elif channel == "slack":
                        body = {"text": f"{headline}\n<{amz_url}|Open on Amazon>"}
                    elif channel == "ntfy":
                        body = payload_dict
                    else:
                        body = payload_dict
                    resp = await client.post(settings.webhook_url, json=body)
                    status = f"sent_http_{resp.status_code}"
            except Exception as exc:
                status = f"error: {type(exc).__name__}"

        log_entry = WebhookAlertLog(
            option_id=node.id or 0,
            option_title=node.title,
            effective_price=effective_price,
            strike_price=node.strike_price,
            channel=channel if channel != "none" else "local_inbox",
            status=status,
            payload_preview=json.dumps(payload_dict),
        )
        session.add(log_entry)
        session.commit()
        session.refresh(log_entry)
        return log_entry


webhook_notifier = WebhookNotifier()

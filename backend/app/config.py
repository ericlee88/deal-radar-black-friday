from typing import Literal, Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings with pluggable provider configuration.

    Automatically switches from deterministic Local/Seed mode to Live API providers
    when API keys are supplied in `.env` or environment variables.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "Deal Radar — Polymorphic Shopping Mission Engine"
    environment: Literal["local", "staging", "production"] = "local"
    database_url: str = "sqlite:///./deal_radar.db"

    # LLM Intent Resolver Configuration (Pluggable: mock | gemini | openai)
    llm_provider: Literal["auto", "mock", "gemini", "openai"] = "auto"
    gemini_api_key: Optional[str] = None
    gemini_model: str = "gemini-2.5-flash"
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-4o-mini"

    # Price History & ASIN Discovery Configuration (Pluggable: auto | amazon_direct | keepa | mock)
    price_provider: Literal["auto", "amazon_direct", "mock", "keepa"] = "auto"
    keepa_api_key: Optional[str] = None

    # Webhook & Push Alerting Configuration (Telegram, Discord, Slack, ntfy.sh)
    webhook_provider: Literal["none", "discord", "slack", "telegram", "ntfy", "generic"] = "none"
    webhook_url: Optional[str] = None
    telegram_bot_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None

    # Background Price Poller Interval (minutes)
    poll_interval_minutes: int = 30
    enable_scheduler: bool = True

    @property
    def active_llm_mode(self) -> str:
        if self.llm_provider != "auto":
            return self.llm_provider
        if self.gemini_api_key:
            return "gemini"
        if self.openai_api_key:
            return "openai"
        return "mock"

    @property
    def active_price_mode(self) -> str:
        if self.price_provider != "auto":
            return self.price_provider
        if self.keepa_api_key:
            return "keepa"
        return "amazon_direct"


settings = Settings()


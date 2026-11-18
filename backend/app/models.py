from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional
from sqlmodel import Field, Relationship, SQLModel


class MissionNodeType(str, Enum):
    """Polymorphic intent types in the Shopping Mission DAG."""

    EXACT_SKU = "EXACT_SKU"              # Pinned ASIN / Model number (e.g., Work Sharp WSSA0004772)
    XOR_FORK = "XOR_FORK"                # Mutually exclusive trade-off fork (e.g., DeWalt Adapter vs Hammer Drill Kit)
    CATEGORY_FUNNEL = "CATEGORY_FUNNEL"  # Fuzzy category translated into candidate ASINs (e.g., 304 SS Rice Basin, 8+ Board Games)
    CONSUMABLE_STACK = "CONSUMABLE_STACK"  # Buy-Again S&S + $100->$25 P&G stock-up combinatoric items


class ShoppingMission(SQLModel, table=True):
    """Top-level node in the Polymorphic Shopping Mission DAG."""

    __tablename__ = "shopping_missions"

    id: Optional[int] = Field(default=None, primary_key=True)
    slug: str = Field(index=True, unique=True)
    title: str
    raw_intent: str
    node_type: MissionNodeType = Field(default=MissionNodeType.CATEGORY_FUNNEL)
    category_tag: str = Field(default="general")
    icon: str = Field(default="🎯")
    decision_framing: str = Field(default="")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    options: List["DealOptionNode"] = Relationship(
        back_populates="mission",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )


class DealOptionNode(SQLModel, table=True):
    """Concrete candidate SKU or trade-off branch inside a ShoppingMission."""

    __tablename__ = "deal_option_nodes"

    id: Optional[int] = Field(default=None, primary_key=True)
    mission_id: int = Field(foreign_key="shopping_missions.id", index=True)

    branch_key: str = Field(default="primary")
    branch_label: str = Field(default="Candidate Option")
    is_recommended_branch: bool = Field(default=False)
    is_trap_warning: bool = Field(default=False)

    title: str
    asin_or_sku: str = Field(default="ASIN-PENDING")
    amazon_query: str

    msrp: float
    avg_90d_price: float
    current_price: float
    clip_coupon_amount: float = Field(default=0.0)
    strike_price: float
    all_time_low: float

    # Combinatoric & Unit-Economics Metadata
    sns_eligible: bool = Field(default=False)
    pg_stockup_eligible: bool = Field(default=False)
    b2g1_eligible: bool = Field(default=False)
    selected_in_stack: bool = Field(default=False)
    snagged: bool = Field(default=False)

    unit_name: str = Field(default="unit")
    unit_quantity: float = Field(default=1.0)

    # JSON-encoded list of floats representing 90d historical price trajectory
    price_history_json: str = Field(default="[]")
    scout_notes: str = Field(default="")
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    mission: Optional[ShoppingMission] = Relationship(back_populates="options")


class WebhookAlertLog(SQLModel, table=True):
    """Audit log of strike-price alerts sent to Telegram/Discord/Slack/ntfy."""

    __tablename__ = "webhook_alert_logs"

    id: Optional[int] = Field(default=None, primary_key=True)
    option_id: int = Field(index=True)
    option_title: str
    effective_price: float
    strike_price: float
    channel: str
    status: str
    payload_preview: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

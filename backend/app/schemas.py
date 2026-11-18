from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field
from app.models import MissionNodeType


class DealOptionRead(BaseModel):
    id: int
    mission_id: int
    branch_key: str
    branch_label: str
    is_recommended_branch: bool
    is_trap_warning: bool
    title: str
    asin_or_sku: str
    amazon_query: str
    msrp: float
    avg_90d_price: float
    current_price: float
    clip_coupon_amount: float
    strike_price: float
    all_time_low: float
    sns_eligible: bool
    pg_stockup_eligible: bool
    b2g1_eligible: bool
    selected_in_stack: bool
    snagged: bool
    unit_name: str
    unit_quantity: float
    price_history: List[float]
    scout_notes: str

    # Computed fields populated by DealScorer
    effective_price: float
    unit_effective_price: float
    discount_pct_off_msrp: int
    deal_grade_code: str
    deal_grade_label: str
    is_below_strike: bool
    amazon_url: str
    camel_url: str


class ShoppingMissionRead(BaseModel):
    id: int
    slug: str
    title: str
    raw_intent: str
    node_type: MissionNodeType
    category_tag: str
    icon: str
    decision_framing: str
    created_at: datetime
    options: List[DealOptionRead]


class DealOptionPatch(BaseModel):
    current_price: Optional[float] = None
    clip_coupon_amount: Optional[float] = None
    strike_price: Optional[float] = None
    sns_eligible: Optional[bool] = None
    selected_in_stack: Optional[bool] = None
    snagged: Optional[bool] = None


class IntentTranslateRequest(BaseModel):
    raw_intent: str = Field(
        ...,
        description="Fuzzy or specific user shopping intent (e.g. 'Anker 140W GaN charger or Ugreen equivalent')",
    )
    budget_hint: Optional[float] = None


class GeneratedOptionSpec(BaseModel):
    branch_key: str
    branch_label: str
    is_recommended_branch: bool = False
    is_trap_warning: bool = False
    title: str
    asin_or_sku: str
    amazon_query: str
    msrp: float
    avg_90d_price: float
    current_price: float
    clip_coupon_amount: float = 0.0
    strike_price: float
    all_time_low: float
    sns_eligible: bool = False
    pg_stockup_eligible: bool = False
    b2g1_eligible: bool = False
    unit_name: str = "unit"
    unit_quantity: float = 1.0
    scout_notes: str


class GeneratedMissionSpec(BaseModel):
    slug: str
    title: str
    node_type: MissionNodeType
    category_tag: str
    icon: str
    decision_framing: str
    options: List[GeneratedOptionSpec]


class CombinatoricStackSummary(BaseModel):
    # Subscribe & Save + P&G $100->$25 Stack
    sns_active_count: int
    sns_tier_rate: float
    sns_unlocked_15pct: bool
    pg_qualifying_subtotal: float
    pg_credit_unlocked: float
    pg_amount_needed_for_credit: float
    consumables_msrp_total: float
    consumables_sale_total: float
    consumables_coupon_savings: float
    consumables_sns_savings: float
    consumables_net_out_of_pocket: float
    consumables_effective_discount_pct: int

    # Amazon 3-for-2 (Buy 2 Get 1 Free) Board Game Optimizer
    b2g1_selected_count: int
    b2g1_msrp_total: float
    b2g1_sale_subtotal: float
    b2g1_free_item_deduction: float
    b2g1_net_total: float
    b2g1_harmony_score: int
    b2g1_harmony_verdict: str


class WebhookTestRequest(BaseModel):
    option_id: Optional[int] = None
    custom_message: Optional[str] = None

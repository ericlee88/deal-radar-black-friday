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
    product_url: str = ""
    site_name: str = "Amazon"
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
    avg_90d_price: Optional[float] = None
    all_time_low: Optional[float] = None
    clip_coupon_amount: Optional[float] = None
    strike_price: Optional[float] = None
    sns_eligible: Optional[bool] = None
    selected_in_stack: Optional[bool] = None
    snagged: Optional[bool] = None
    asin_or_sku: Optional[str] = None
    product_url: Optional[str] = None
    title: Optional[str] = None


class IntentTranslateRequest(BaseModel):
    raw_intent: str = Field(
        ...,
        description="Fuzzy or specific user shopping intent, or any retailer product URL",
    )
    budget_hint: Optional[float] = None


class CustomProductLinkRequest(BaseModel):
    product_url: str = Field(..., description="Full http(s) product URL from any retail site")
    title: Optional[str] = None
    strike_price: Optional[float] = None
    current_price: Optional[float] = None
    category_tag: str = Field(default="custom")
    scout_notes: Optional[str] = None


class GeneratedOptionSpec(BaseModel):
    branch_key: str
    branch_label: str
    is_recommended_branch: bool = False
    is_trap_warning: bool = False
    title: str
    asin_or_sku: str
    amazon_query: str
    product_url: str = ""
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


class ProviderSettingsRead(BaseModel):
    llm_provider: str
    active_llm_mode: str
    gemini_api_key_set: bool
    gemini_api_key_preview: str
    gemini_model: str
    openai_api_key_set: bool
    openai_api_key_preview: str
    openai_model: str
    price_provider: str
    active_price_mode: str
    keepa_api_key_set: bool
    keepa_api_key_preview: str
    webhook_provider: str
    webhook_url: Optional[str] = None
    telegram_bot_token_set: bool
    telegram_chat_id: Optional[str] = None
    poll_interval_minutes: int


class ProviderSettingsUpdate(BaseModel):
    llm_provider: Optional[str] = None
    gemini_api_key: Optional[str] = None
    gemini_model: Optional[str] = None
    openai_api_key: Optional[str] = None
    openai_model: Optional[str] = None
    price_provider: Optional[str] = None
    keepa_api_key: Optional[str] = None
    webhook_provider: Optional[str] = None
    webhook_url: Optional[str] = None
    telegram_bot_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None
    poll_interval_minutes: Optional[int] = None


class CartChecklistStep(BaseModel):
    step_number: int
    title: str
    detail: str
    badge: str
    category: str = "general"


class AmazonCartBuilderPlan(BaseModel):
    scope: str
    cart_add_url: Optional[str] = None
    sns_cart_add_url: Optional[str] = None
    b2g1_cart_add_url: Optional[str] = None
    direct_asin_count: int
    total_selected_count: int
    direct_asin_items: List[DealOptionRead]
    search_fallback_items: List[DealOptionRead]
    total_msrp: float
    total_sale_price: float
    total_coupon_savings: float
    total_sns_savings: float
    pg_credit_savings: float
    b2g1_free_savings: float
    net_estimated_checkout: float
    total_savings: float
    effective_discount_pct: int
    checklist_steps: List[CartChecklistStep]


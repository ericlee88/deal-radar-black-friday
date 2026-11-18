# Deal Radar — Polymorphic Shopping Mission DAG & Strike-Price Engine

A full-stack **Flutter + Python (FastAPI)** deal-catching command center built for Amazon Black Friday Week. Designed around a **Polymorphic "Shopping Mission" DAG** (`EXACT_SKU`, `XOR_FORK`, `CATEGORY_FUNNEL`, `CONSUMABLE_STACK`) and a **Combinatoric Promo Stacker** (Subscribe & Save 5-item 15% tier step-function + P&G \$100/\$25 credit stacker + Amazon 3-for-2 board game price-clustering optimizer).

---

## Architecture

1. **Backend (`backend/`)** — Python 3.11+ / FastAPI / SQLModel (SQLite & PostgreSQL ready) / APScheduler / Pydantic v2:
   - **Polymorphic Mission Engine (`app/engine/deal_scorer.py`)**: Computes effective post-coupon/post-S&S unit & total prices, strike-price deltas, and solves combinatoric S&S + 3-for-2 bundles.
   - **Pluggable Providers (`app/providers/`)**:
     - `llm_provider.py`: Translates fuzzy shopping intents into structured DAG missions via **Gemini** (`GEMINI_API_KEY`), **OpenAI** (`OPENAI_API_KEY`), or deterministic local heuristic fallback.
     - `price_provider.py`: Polls live Amazon price & 90-day average history via **Keepa API** (`KEEPA_API_KEY`) or deterministic Black Friday simulation mode.
     - `notifier.py`: Dispatches instant strike-price alerts to **Telegram**, **Discord**, **Slack**, or **ntfy.sh** (`WEBHOOK_PROVIDER` + `WEBHOOK_URL`).

2. **Frontend (`frontend/`)** — Flutter (Material 3 Dark UI + `flutter_riverpod`):
   - **7 Pre-Seeded Shopping Missions**:
     1. *Stainless Steel Kitchen Spatulas & 304 Microporous Rice/Vegetable Washing Basins* (`CATEGORY_FUNNEL`)
     2. *Work Sharp Precision Adjust Upgrade Kit (`WSSA0004772`)* (`EXACT_SKU` + Pro/Elite Trap Guard)
     3. *DeWalt 18V-to-20V Adapter (`DCA1820` + `DCB205-2C`) vs. Discontinued `DCA2203C` Trap vs. `DCD805D2` 20V MAX XR Hammer Drill Kit* (`XOR_FORK`)
     4. *Dyson Handheld Vacuum Decision Tree (`Car+Boat` vs. `V8 Cyclone` vs. `V12 Detect Slim`)* (`XOR_FORK`)
     5. *Usual "Buy Again" Household Consumables + 15% S&S Filler Catalyst* (`CONSUMABLE_STACK`)
     6. *Metamucil + Collagen Rejuvenation Blend vs. DIY Bulk Stack ($/g math)* (`XOR_FORK`)
     7. *8+ YO Strategy Board Games & Marble Logic Puzzles (3-for-2 Cluster Optimizer)* (`CATEGORY_FUNNEL`)

---

## Quick Start

### 1. Run Backend & Unified Web Server (`:8080`)
```bash
cd backend
uv sync --extra dev
uv run pytest -v
uv run uvicorn app.main:app --host 0.0.0.0 --port 8080
```

### 2. Build or Run Flutter Frontend
```bash
cd frontend
flutter pub get
flutter test
# Build release web bundle (automatically served by FastAPI at http://localhost:8080)
flutter build web --release --no-web-resources-cdn
```

### 3. Live API Keys & Webhooks (Optional `.env` in `backend/`)
```env
GEMINI_API_KEY=your_gemini_key
KEEPA_API_KEY=your_keepa_key
WEBHOOK_PROVIDER=ntfy
WEBHOOK_URL=https://ntfy.sh/your_black_friday_radar_topic
```

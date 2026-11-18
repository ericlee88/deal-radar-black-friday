#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/home/antigravity/.local/flutter/bin:$PATH"

echo "Building Flutter Web Frontend..."
cd "$ROOT_DIR/frontend"
flutter build web --release

echo "Starting Unified Deal Radar Server (FastAPI + Flutter Web) on :8080..."
cd "$ROOT_DIR/backend"
exec uv run uvicorn app.main:app --host 0.0.0.0 --port 8080

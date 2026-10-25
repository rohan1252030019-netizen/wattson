#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=========================================================="
echo "   WATTSON — Evidence-Based AI Cloud Optimizer"
echo "=========================================================="

mkdir -p .data/logs

export WATTSON_API_TOKEN="${WATTSON_API_TOKEN:-wattson-demo-token}"
export WATTSON_TEMPORAL_HOST="localhost:7233"
export WATTSON_TEMPORAL_TASK_QUEUE="wattson-demo"
export WATTSON_PROVIDER="simulator"
export WATTSON_AI_PROVIDER="none"
export WATTSON_KILL_SWITCH="false"
export WATTSON_DATABASE_URL="sqlite:///./.data/demo.db"
export WATTSON_CORS_ORIGINS="http://localhost:3000"
export WATTSON_API_URL="http://127.0.0.1:8000"

echo "[1/4] Applying migrations..."
uv run alembic upgrade head

if ! nc -z 127.0.0.1 7233 2>/dev/null; then
    echo "[2/4] Starting Temporal dev server..."
    temporal server start-dev --headless --port 7233 --db-filename .data/temporal-demo.db > .data/logs/temporal.out.log 2>&1 &
    sleep 3
fi

echo "[3/4] Starting worker and API..."
uv run python -m wattson.worker > .data/logs/worker.out.log 2>&1 &
uv run uvicorn wattson.api.app:app --host 127.0.0.1 --port 8000 > .data/logs/api.out.log 2>&1 &

echo "[4/4] Starting Next.js frontend..."
cd frontend
[ ! -f .env.local ] && echo -e "WATTSON_API_URL=http://127.0.0.1:8000\nWATTSON_API_TOKEN=${WATTSON_API_TOKEN}" > .env.local
npm run dev -- -p 3000 > ../.data/logs/frontend.out.log 2>&1 &

echo ""
echo "WATTSON is running at http://localhost:3000"

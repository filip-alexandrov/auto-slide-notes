#!/usr/bin/env bash
# Starts the slide relay on all interfaces so the iPad can reach it over Wi-Fi.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi

HOST="${SLIDES_HOST:-0.0.0.0}"
PORT="${SLIDES_PORT:-8000}"
echo "Slide relay on http://$(ipconfig getifaddr en0 2>/dev/null || echo localhost):$PORT"
exec .venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT" --log-level info 2>&1 | tee -a server.log

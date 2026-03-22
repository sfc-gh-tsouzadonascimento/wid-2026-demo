#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Python venv ──────────────────────────────────────────────
if [ ! -d "$DIR/.venv" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$DIR/.venv"
fi

source "$DIR/.venv/bin/activate"
pip install -q -r "$DIR/requirements.txt"

# ── Frontend build ───────────────────────────────────────────
if [ ! -d "$DIR/frontend/node_modules" ]; then
  echo "Installing frontend dependencies..."
  npm --prefix "$DIR/frontend" ci
fi

echo "Building frontend..."
npm --prefix "$DIR/frontend" run build

# ── Start server ─────────────────────────────────────────────
echo ""
echo "Starting FrostBank Operational Intelligence Hub on http://localhost:8080"
echo "Press Ctrl+C to stop."
echo ""
python "$DIR/app.py"

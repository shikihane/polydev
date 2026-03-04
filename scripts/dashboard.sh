#!/bin/bash
# dashboard.sh - Start the polydev dashboard web panel
#
# Usage: dashboard.sh [--dev] [--port PORT]
#
# --dev    Start in development mode (Vite + Express concurrently)
# --port   API server port (default: 3120)

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DASHBOARD_DIR="$SCRIPT_DIR/../dashboard"

# Check dependencies
if ! command -v node &> /dev/null; then
  echo "Error: Node.js is not installed. Please install Node.js (https://nodejs.org/) to run the dashboard."
  exit 1
fi
if ! command -v npm &> /dev/null; then
  echo "Error: npm is not installed. Please install Node.js (https://nodejs.org/) which includes npm."
  exit 1
fi

PORT="${PORT:-3120}"
DEV_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      DEV_MODE=true
      shift
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -d "$DASHBOARD_DIR/node_modules" ]; then
  echo "Installing dashboard dependencies..."
  (cd "$DASHBOARD_DIR" && npm install)
fi

export PORT

if $DEV_MODE; then
  echo "Starting dashboard in dev mode (API :$PORT + Vite :5173)..."
  cd "$DASHBOARD_DIR"
  npx concurrently "node server/index.js" "npx vite"
else
  # Production: build if needed, then serve
  if [ ! -d "$DASHBOARD_DIR/dist" ]; then
    echo "Building dashboard frontend..."
    (cd "$DASHBOARD_DIR" && npx vite build)
  fi
  echo "Starting dashboard on http://localhost:$PORT"
  cd "$DASHBOARD_DIR"
  node server/index.js
fi

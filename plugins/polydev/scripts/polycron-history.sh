#!/bin/bash
# polycron-history.sh [job-id] [--last N]

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

JOB_ID=""
LAST_N=20

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --last)
      LAST_N="$2"
      shift 2
      ;;
    *)
      if [ -z "$JOB_ID" ]; then
        JOB_ID="$1"
        shift
      else
        echo "[E] Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

CRON_DIR="$HOME/.polydev/cron"
HISTORY_FILE="$CRON_DIR/history.jsonl"

if [ ! -f "$HISTORY_FILE" ]; then
  echo "[I] No history found"
  exit 0
fi

echo "[I] event=listing_history,job_id=${JOB_ID:-all},limit=$LAST_N"

# Read and filter history
echo "history{job_id,triggered_at,pane_id,status}:"

$PYTHON -c "
import sys, json

job_filter = '$JOB_ID'
limit = int('$LAST_N')

entries = []
with open('$HISTORY_FILE') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            # Apply job filter if specified
            if job_filter and entry.get('job_id') != job_filter:
                continue
            entries.append(entry)
        except json.JSONDecodeError:
            continue

# Sort by triggered_at descending (most recent first)
entries.sort(key=lambda x: x.get('triggered_at', ''), reverse=True)

# Limit output
entries = entries[:limit]

for entry in entries:
    job_id = entry.get('job_id', '')
    triggered_at = entry.get('triggered_at', '')
    pane_id = entry.get('pane_id', '')
    status = entry.get('status', '')
    print(f'  {job_id},{triggered_at},{pane_id},{status}')
"

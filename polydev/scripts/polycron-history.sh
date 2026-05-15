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

# Extract fields from JSONL using shell
_jsonl_val() { echo "$1" | sed "s/.*\"$2\":\"\([^\"]*\)\".*/\1/"; }

# Read, filter, and format entries
{
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    j_id=$(_jsonl_val "$line" job_id)
    # Apply job filter
    if [ -n "$JOB_ID" ] && [ "$j_id" != "$JOB_ID" ]; then
      continue
    fi
    j_at=$(_jsonl_val "$line" triggered_at)
    j_pane=$(_jsonl_val "$line" pane_id)
    j_status=$(_jsonl_val "$line" status)
    echo "  ${j_at}|${j_id},${j_at},${j_pane},${j_status}"
  done < "$HISTORY_FILE"
} | sort -t'|' -k1 -r | head -n "$LAST_N" | sed 's/^[^|]*|//'

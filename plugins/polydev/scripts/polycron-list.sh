#!/bin/bash
# polycron-list.sh [--all|--enabled|--disabled]

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

FILTER="all"

# Parse arguments
if [ $# -gt 0 ]; then
  case "$1" in
    --all)
      FILTER="all"
      ;;
    --enabled)
      FILTER="enabled"
      ;;
    --disabled)
      FILTER="disabled"
      ;;
    *)
      echo "[E] Usage: polycron-list.sh [--all|--enabled|--disabled]" >&2
      exit 1
      ;;
  esac
fi

CRON_DIR="$HOME/.polydev/cron"
JOBS_DIR="$CRON_DIR/jobs"

if [ ! -d "$JOBS_DIR" ]; then
  echo "[I] No jobs found"
  exit 0
fi

# Count jobs
JOB_COUNT=$(find "$JOBS_DIR" -name "*.json" 2>/dev/null | wc -l)

if [ "$JOB_COUNT" -eq 0 ]; then
  echo "[I] No jobs found"
  exit 0
fi

echo "[I] event=listing_jobs,filter=$FILTER,count=$JOB_COUNT"

# List jobs in TOON format
echo "jobs{id,schedule,type,enabled,prompt_summary,cwd}:"

for job_file in "$JOBS_DIR"/*.json; do
  if [ ! -f "$job_file" ]; then
    continue
  fi

  # Extract job data
  JOB_DATA=$($PYTHON -c "
import sys, json
with open('$job_file') as f:
    data = json.load(f)
    enabled = data.get('enabled', False)
    filter_type = '$FILTER'

    # Apply filter
    if filter_type == 'enabled' and not enabled:
        sys.exit(0)
    if filter_type == 'disabled' and enabled:
        sys.exit(0)

    # Truncate prompt for summary
    prompt = data.get('prompt', '')
    prompt_summary = prompt[:50] + '...' if len(prompt) > 50 else prompt
    prompt_summary = prompt_summary.replace(',', ';')  # Avoid TOON delimiter issues

    print(f\"{data.get('id', '')},{data.get('schedule', '')},{data.get('type', '')},{enabled},{prompt_summary},{data.get('cwd', '')}\")
" 2>/dev/null || true)

  if [ -n "$JOB_DATA" ]; then
    echo "  $JOB_DATA"
  fi
done

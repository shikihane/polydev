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

  # Extract job data using shell
  _jv() { grep "\"$1\"" "$job_file" | head -1 | sed 's/.*: *"\(.*\)".*/\1/'; }
  _jb() { grep "\"$1\"" "$job_file" | head -1 | sed 's/.*: *\(true\|false\).*/\1/'; }

  j_enabled=$(_jb enabled)

  # Apply filter
  if [ "$FILTER" = "enabled" ] && [ "$j_enabled" != "true" ]; then
    continue
  fi
  if [ "$FILTER" = "disabled" ] && [ "$j_enabled" = "true" ]; then
    continue
  fi

  j_id=$(_jv id)
  j_schedule=$(_jv schedule)
  j_type=$(_jv type)
  j_cwd=$(_jv cwd)
  j_prompt=$(_jv prompt)
  # Truncate prompt and replace commas
  j_prompt=$(printf '%.50s' "$j_prompt")
  j_prompt=$(echo "$j_prompt" | tr ',' ';')
  [ ${#j_prompt} -ge 50 ] 2>/dev/null && j_prompt="${j_prompt}..."

  JOB_DATA="${j_id},${j_schedule},${j_type},${j_enabled},${j_prompt},${j_cwd}"

  if [ -n "$JOB_DATA" ]; then
    echo "  $JOB_DATA"
  fi
done

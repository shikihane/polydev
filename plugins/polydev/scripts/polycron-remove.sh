#!/bin/bash
# polycron-remove.sh <job-id>

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

JOB_ID="$1"

if [ -z "$JOB_ID" ]; then
  echo "[E] Usage: polycron-remove.sh <job-id>" >&2
  exit 1
fi

CRON_DIR="$HOME/.polydev/cron"
JOB_FILE="$CRON_DIR/jobs/$JOB_ID.json"

if [ ! -f "$JOB_FILE" ]; then
  echo "[E] Job not found: $JOB_ID" >&2
  exit 1
fi

echo "[I] event=job_removing,job_id=$JOB_ID"

# Remove from OS scheduler
PLATFORM=$(uname)

if [[ "$PLATFORM" =~ MINGW|MSYS ]]; then
  # Windows - use schtasks
  TASK_NAME="polydev-$JOB_ID"
  schtasks /Delete /TN "$TASK_NAME" /F 2>/dev/null || true
  echo "[I] event=scheduler_unregistered,platform=windows,task=$TASK_NAME"
else
  # Linux/macOS - use crontab
  TRIGGER_SCRIPT="$SCRIPT_DIR/polycron-trigger.sh"
  crontab -l 2>/dev/null | grep -v "polycron-trigger.sh $JOB_ID" | crontab - || true
  echo "[I] event=scheduler_unregistered,platform=unix"
fi

# Delete job file
rm -f "$JOB_FILE"

echo "[I] event=job_removed,job_id=$JOB_ID"

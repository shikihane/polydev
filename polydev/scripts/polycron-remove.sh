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

# Extract pane_id from job file
PANE_ID=$(grep '"pane_id"' "$JOB_FILE" | head -1 | sed 's/.*: *"\(.*\)".*/\1/')

# Kill the agent pane if it exists
if [ -n "$PANE_ID" ]; then
  tmux -S "$TB_SOCKET" kill-pane -t "$PANE_ID" 2>/dev/null && echo "[I] event=pane_killed,pane_id=$PANE_ID" || true
fi

# Remove from OS scheduler
PLATFORM=$(uname)

if [[ "$PLATFORM" =~ MINGW|MSYS ]]; then
  # Windows - use schtasks
  TASK_NAME="polydev-$JOB_ID"
  schtasks /Delete /TN "$TASK_NAME" /F 2>/dev/null || true
  echo "[I] event=scheduler_unregistered,platform=windows,task=$TASK_NAME"
else
  # Linux/macOS - use crontab
  # Remove any line containing polycron-trigger.sh and the job ID
  crontab -l 2>/dev/null | grep -v "polycron-trigger.sh.*$JOB_ID" | crontab - || true
  echo "[I] event=scheduler_unregistered,platform=unix"
fi

# Delete job file
rm -f "$JOB_FILE"

echo "[I] event=job_removed,job_id=$JOB_ID"

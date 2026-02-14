#!/bin/bash
# polycron-add.sh <job-id> --schedule "0 9 * * *" --prompt "..." --cwd /path [--type cron|once] [--model sonnet] [--report <path>]
# polycron-add.sh <job-id> --at "2026-02-15 10:00" --prompt "..." --cwd /path [--type once]

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

JOB_ID=""
SCHEDULE=""
AT_TIME=""
PROMPT=""
CWD=""
TYPE="cron"
MODEL="sonnet"
REPORT_PATH=""

# Parse arguments
if [ $# -lt 1 ]; then
  echo "[E] Usage: polycron-add.sh <job-id> --schedule \"...\" --prompt \"...\" --cwd /path [options]" >&2
  exit 1
fi

JOB_ID="$1"
shift

while [ $# -gt 0 ]; do
  case "$1" in
    --schedule)
      SCHEDULE="$2"
      shift 2
      ;;
    --at)
      AT_TIME="$2"
      shift 2
      ;;
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    --cwd)
      CWD="$2"
      shift 2
      ;;
    --type)
      TYPE="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --report)
      REPORT_PATH="$2"
      shift 2
      ;;
    *)
      echo "[E] Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$PROMPT" ] || [ -z "$CWD" ]; then
  echo "[E] --prompt and --cwd are required" >&2
  exit 1
fi

if [ -z "$SCHEDULE" ] && [ -z "$AT_TIME" ]; then
  echo "[E] Either --schedule or --at is required" >&2
  exit 1
fi

# Convert --at to schedule if provided
if [ -n "$AT_TIME" ]; then
  TYPE="once"
  # Parse "YYYY-MM-DD HH:MM" to cron schedule
  SCHEDULE=$(echo "$AT_TIME" | $PYTHON -c "
import sys
from datetime import datetime
at_str = sys.stdin.read().strip()
dt = datetime.strptime(at_str, '%Y-%m-%d %H:%M')
print(f'{dt.minute} {dt.hour} {dt.day} {dt.month} *')
")
fi

# Set default report path if not provided
if [ -z "$REPORT_PATH" ]; then
  REPORT_PATH="$HOME/.polydev/cron/reports/$JOB_ID.md"
fi

CRON_DIR="$HOME/.polydev/cron"
JOB_FILE="$CRON_DIR/jobs/$JOB_ID.json"
CREATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create directories
mkdir -p "$CRON_DIR/jobs"
mkdir -p "$(dirname "$REPORT_PATH")"

# Generate job JSON
cat > "$JOB_FILE" <<EOF
{
  "id": "$JOB_ID",
  "schedule": "$SCHEDULE",
  "type": "$TYPE",
  "prompt": "$PROMPT",
  "report_path": "$REPORT_PATH",
  "cwd": "$CWD",
  "model": "$MODEL",
  "created": "$CREATED",
  "enabled": true
}
EOF

echo "[I] event=job_created,job_id=$JOB_ID,type=$TYPE,schedule=$SCHEDULE"

# Register to OS scheduler
TRIGGER_SCRIPT="$SCRIPT_DIR/polycron-trigger.sh"
PLATFORM=$(uname)

if [[ "$PLATFORM" =~ MINGW|MSYS ]]; then
  # Windows - use schtasks
  TASK_NAME="polydev-$JOB_ID"

  # Convert cron schedule to schtasks format
  # For simplicity, we'll use a basic conversion
  # Full cron parsing would be more complex

  if [ "$TYPE" = "once" ]; then
    # Single run - parse schedule for date/time
    SCHED_TIME=$(echo "$SCHEDULE" | $PYTHON -c "
import sys
parts = sys.stdin.read().strip().split()
minute, hour, day, month = parts[0], parts[1], parts[2], parts[3]
print(f'/SC ONCE /ST {hour}:{minute} /SD {month}/{day}/2026')
")
    schtasks /Create /TN "$TASK_NAME" /TR "bash \"$TRIGGER_SCRIPT\" $JOB_ID" $SCHED_TIME /F
  else
    # Recurring - basic daily schedule
    # Note: Full cron syntax conversion is complex, this is simplified
    HOUR=$(echo "$SCHEDULE" | cut -d' ' -f2)
    MINUTE=$(echo "$SCHEDULE" | cut -d' ' -f1)
    schtasks /Create /TN "$TASK_NAME" /TR "bash \"$TRIGGER_SCRIPT\" $JOB_ID" /SC DAILY /ST "$HOUR:$MINUTE" /F
  fi

  echo "[I] event=scheduler_registered,platform=windows,task=$TASK_NAME"
else
  # Linux/macOS - use crontab
  CRON_ENTRY="$SCHEDULE bash \"$TRIGGER_SCRIPT\" $JOB_ID"

  # Add to crontab
  (crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab -

  echo "[I] event=scheduler_registered,platform=unix,schedule=$SCHEDULE"
fi

echo "[I] event=job_added,job_id=$JOB_ID"


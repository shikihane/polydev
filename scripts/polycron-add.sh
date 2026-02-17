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
  # Parse "YYYY-MM-DD HH:MM" to cron schedule: "minute hour day month *"
  AT_DATE="${AT_TIME% *}"
  AT_HM="${AT_TIME#* }"
  AT_MONTH=$(echo "$AT_DATE" | cut -d'-' -f2 | sed 's/^0//')
  AT_DAY=$(echo "$AT_DATE" | cut -d'-' -f3 | sed 's/^0//')
  AT_HOUR=$(echo "$AT_HM" | cut -d':' -f1 | sed 's/^0//')
  AT_MINUTE=$(echo "$AT_HM" | cut -d':' -f2 | sed 's/^0//')
  SCHEDULE="$AT_MINUTE ${AT_HOUR:-0} $AT_DAY $AT_MONTH *"
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

# Pre-create agent pane with Claude ready
echo "[I] event=creating_agent_pane,job_id=$JOB_ID"

# Find claude binary
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
if [ -z "$CLAUDE_BIN" ]; then
  for candidate in "$HOME/.nvm/versions/node"/*/bin/claude "$HOME/.local/bin/claude" /usr/local/bin/claude; do
    if [ -x "$candidate" ]; then
      CLAUDE_BIN="$candidate"
      break
    fi
  done
fi
if [ -z "$CLAUDE_BIN" ]; then
  echo "[E] claude binary not found" >&2
  exit 1
fi

# Create tmux pane and start Claude
PANE_ID=$(tmux -S "$TB_SOCKET" new-session -d -s "polycron-agents" -n "$JOB_ID" -c "$CWD" -P -F "#{pane_id}" bash 2>/dev/null || \
          tmux -S "$TB_SOCKET" new-window -t "polycron-agents:" -n "$JOB_ID" -c "$CWD" -P -F "#{pane_id}" bash)

# Start Claude in the pane
tmux -S "$TB_SOCKET" send-keys -t "$PANE_ID" -l "CLAUDECODE= $CLAUDE_BIN --dangerously-skip-permissions --model $MODEL"
tmux -S "$TB_SOCKET" send-keys -t "$PANE_ID" C-m

echo "[I] event=agent_pane_created,pane_id=$PANE_ID"

# Wait for Claude to start and check if permission prompt appears
sleep 3
PANE_CONTENT=$(tmux -S "$TB_SOCKET" capture-pane -t "$PANE_ID" -p 2>/dev/null || true)

# If permission prompt appears, accept it
if echo "$PANE_CONTENT" | grep -q "Yes, I accept"; then
  echo "[I] event=accepting_bypass_permissions"
  tmux -S "$TB_SOCKET" send-keys -t "$PANE_ID" Down
  sleep 0.5
  tmux -S "$TB_SOCKET" send-keys -t "$PANE_ID" C-m
  sleep 4
  PANE_CONTENT=$(tmux -S "$TB_SOCKET" capture-pane -t "$PANE_ID" -p 2>/dev/null || true)
fi

# Verify Claude is running (check for prompt or typical Claude output)
if ! echo "$PANE_CONTENT" | grep -qE '(>|Tips for|╭|╰)'; then
  # Claude not running - check if it exited
  if echo "$PANE_CONTENT" | grep -qE '(bash:|shiyu@|^\$)'; then
    echo "[E] Claude failed to start or exited prematurely" >&2
    echo "[E] Pane content:" >&2
    echo "$PANE_CONTENT" | tail -10 >&2
    tmux -S "$TB_SOCKET" kill-pane -t "$PANE_ID" 2>/dev/null || true
    exit 1
  fi
fi

echo "[I] event=claude_ready,pane_id=$PANE_ID"

# Generate job JSON with pane_id
cat > "$JOB_FILE" <<EOF
{
  "id": "$JOB_ID",
  "schedule": "$SCHEDULE",
  "type": "$TYPE",
  "prompt": "$PROMPT",
  "report_path": "$REPORT_PATH",
  "cwd": "$CWD",
  "model": "$MODEL",
  "pane_id": "$PANE_ID",
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
    SCHED_MINUTE=$(echo "$SCHEDULE" | cut -d' ' -f1)
    SCHED_HOUR=$(echo "$SCHEDULE" | cut -d' ' -f2)
    SCHED_DAY=$(echo "$SCHEDULE" | cut -d' ' -f3)
    SCHED_MONTH=$(echo "$SCHEDULE" | cut -d' ' -f4)
    SCHED_YEAR=$(date +%Y)
    SCHED_TIME="/SC ONCE /ST ${SCHED_HOUR}:${SCHED_MINUTE} /SD ${SCHED_MONTH}/${SCHED_DAY}/${SCHED_YEAR}"
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


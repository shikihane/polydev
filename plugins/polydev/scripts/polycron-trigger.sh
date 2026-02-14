#!/bin/bash
# polycron-trigger.sh <job-id>
# OS scheduler calls this script when a job is due

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

JOB_ID="$1"

if [ -z "$JOB_ID" ]; then
  echo "[E] Usage: polycron-trigger.sh <job-id>" >&2
  exit 1
fi

CRON_DIR="$HOME/.polydev/cron"
JOB_FILE="$CRON_DIR/jobs/$JOB_ID.json"
HISTORY_FILE="$CRON_DIR/history.jsonl"

if [ ! -f "$JOB_FILE" ]; then
  echo "[E] Job not found: $JOB_ID" >&2
  exit 1
fi

# Read job configuration
ENABLED=$(cat "$JOB_FILE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin).get('enabled', False))")
if [ "$ENABLED" != "True" ]; then
  echo "[W] Job $JOB_ID is disabled, skipping" >&2
  exit 0
fi

JOB_TYPE=$(cat "$JOB_FILE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin).get('type', 'cron'))")
PROMPT=$(cat "$JOB_FILE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin).get('prompt', ''))")
REPORT_PATH=$(cat "$JOB_FILE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin).get('report_path', ''))")
CWD=$(cat "$JOB_FILE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin).get('cwd', ''))")
MODEL=$(cat "$JOB_FILE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin).get('model', 'sonnet'))")

# Spawn agent
echo "[I] event=polycron_triggered,job_id=$JOB_ID,type=$JOB_TYPE"

PANE_ID=$("$SCRIPT_DIR/spawn-agent.sh" "$JOB_ID" \
  --prompt "$PROMPT" \
  --report "$REPORT_PATH" \
  --cwd "$CWD" \
  --model "$MODEL" | tail -1)

TRIGGERED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Log to history
mkdir -p "$CRON_DIR"
echo "{\"job_id\":\"$JOB_ID\",\"triggered_at\":\"$TRIGGERED_AT\",\"pane_id\":\"$PANE_ID\",\"status\":\"started\"}" >> "$HISTORY_FILE"

echo "[I] event=agent_spawned,job_id=$JOB_ID,pane_id=$PANE_ID"

# Disable single-run jobs
if [ "$JOB_TYPE" = "once" ]; then
  cat "$JOB_FILE" | $PYTHON -c "
import sys, json
data = json.load(sys.stdin)
data['enabled'] = False
print(json.dumps(data, indent=2))
" > "$JOB_FILE.tmp"
  mv "$JOB_FILE.tmp" "$JOB_FILE"
  echo "[I] event=job_disabled,job_id=$JOB_ID,reason=single_run_completed"
fi

echo "[I] event=polycron_completed,job_id=$JOB_ID"

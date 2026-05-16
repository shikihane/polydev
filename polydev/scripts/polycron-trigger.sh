#!/bin/bash
# polycron-trigger.sh <job-id>
# Sends prompt to pre-created agent pane

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

# Helper: extract JSON values
_json_val() {
  grep "\"$1\"" "$JOB_FILE" | head -1 | sed 's/.*: *"\(.*\)".*/\1/'
}
_json_bool() {
  grep "\"$1\"" "$JOB_FILE" | head -1 | sed 's/.*: *\(true\|false\).*/\1/'
}

# Read job configuration
ENABLED=$(_json_bool enabled)
if [ "$ENABLED" != "true" ]; then
  echo "[W] Job $JOB_ID is disabled, skipping" >&2
  exit 0
fi

JOB_TYPE=$(_json_val type)
PROMPT=$(_json_val prompt)
REPORT_PATH=$(_json_val report_path)
PANE_ID=$(_json_val pane_id)

[ -z "$JOB_TYPE" ] && JOB_TYPE="cron"

if [ -z "$PANE_ID" ]; then
  echo "[E] No pane_id in job file" >&2
  exit 1
fi

echo "[I] event=polycron_triggered,job_id=$JOB_ID,type=$JOB_TYPE,pane_id=$PANE_ID"

# Build agent prompt. Polycron sends work and returns; completion is observed by
# capture/report inspection instead of a hidden marker protocol.
AGENT_PROMPT="You are an investigation agent. Your task:

$PROMPT

## Requirements

1. Investigate thoroughly using available tools
2. If a report path is provided, write your findings to: $REPORT_PATH
3. When complete, leave the terminal idle with a concise visible summary.

Start now."

# Send prompt to agent pane
TMPFILE="/tmp/polycron_prompt_$$"
printf '%s' "$AGENT_PROMPT" > "$TMPFILE"
"$SCRIPT_DIR/send-prompt.sh" "$PANE_ID" --file "$TMPFILE"
rm -f "$TMPFILE"

TRIGGERED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Log to history
mkdir -p "$CRON_DIR"
echo "{\"job_id\":\"$JOB_ID\",\"triggered_at\":\"$TRIGGERED_AT\",\"pane_id\":\"$PANE_ID\",\"status\":\"started\"}" >> "$HISTORY_FILE"

echo "[I] event=prompt_sent,job_id=$JOB_ID,pane_id=$PANE_ID"

# Disable single-run jobs
if [ "$JOB_TYPE" = "once" ]; then
  sed 's/"enabled": *true/"enabled": false/' "$JOB_FILE" > "$JOB_FILE.tmp"
  mv "$JOB_FILE.tmp" "$JOB_FILE"
  echo "[I] event=job_disabled,job_id=$JOB_ID,reason=single_run_completed"
fi

echo "[I] event=polycron_completed,job_id=$JOB_ID"

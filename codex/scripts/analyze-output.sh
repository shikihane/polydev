#!/bin/bash
# analyze-output.sh - Analyze terminal output status
#
# Usage: analyze-output.sh <session_id> [--lines N] [--json]
#
# Supports both bg: and wo: prefixed session IDs
#
# Output (JSON when --json):
# {
#   "status": "running|idle|success|failed|done",
#   "idle_seconds": 30,
#   "last_lines": ["...", "..."],
#   "detected": {
#     "agent_done": false,
#     "report_path": null,
#     "errors": [],
#     "success_markers": []
#   }
# }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

# Defaults
SESSION_ID=""
LINES=20
JSON_OUTPUT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines)
      LINES="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      if [ -z "$SESSION_ID" ]; then
        SESSION_ID="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$SESSION_ID" ]; then
  echo "Usage: analyze-output.sh <session_id> [--lines N] [--json]" >&2
  exit 1
fi

# Normalize session_id: convert bg: or ag: to wo: for backend calls
BACKEND_SESSION_ID="${SESSION_ID/bg:/wo:}"
BACKEND_SESSION_ID="${BACKEND_SESSION_ID/ag:/wo:}"

# Check if session is alive
if ! tb_is_session_alive "$BACKEND_SESSION_ID"; then
  if [ "$JSON_OUTPUT" = true ]; then
    echo '{"status":"dead","idle_seconds":null,"last_lines":[],"detected":{"agent_done":false,"report_path":null,"errors":[],"success_markers":[]}}'
  else
    echo "Status: dead (session not found)"
  fi
  exit 0
fi

# Capture screen content
_capture_content() {
  local session_id="$1"
  local lines="$2"

  _parse_session_id "$session_id"

  case "$TB_BACKEND" in
    tmux)
      _tmux capture-pane -t "$SESSION:$WINDOW.$PANE" -p -S -"$lines" 2>/dev/null || echo ""
      ;;
    wezterm)
      local pane_id
      pane_id=$(_wezterm_get_pane_id "$session_id")
      if [ -n "$pane_id" ]; then
        wezterm cli get-text --pane-id "$pane_id" --start-line -"$lines" 2>/dev/null || echo ""
      fi
      ;;
  esac
}

# Get the content
CONTENT=$(_capture_content "$BACKEND_SESSION_ID" "$LINES")

# Analyze the content
STATUS="running"
IDLE_SECONDS=0
AGENT_DONE=false
REPORT_PATH=""
ERRORS=()
SUCCESS_MARKERS=()

# Check for [AGENT_DONE] marker
if echo "$CONTENT" | grep -q '\[AGENT_DONE\]'; then
  AGENT_DONE=true
  STATUS="done"
  # Extract report path
  REPORT_PATH=$(echo "$CONTENT" | grep -A1 '\[AGENT_DONE\]' | grep 'report:' | sed 's/.*report: *//' | tr -d ' ')
fi

# Check for common error patterns
while IFS= read -r line; do
  if [ -n "$line" ]; then
    ERRORS+=("$line")
    STATUS="failed"
  fi
done < <(echo "$CONTENT" | grep -iE '(error|ERR!|failed|panic|exception|fatal)' | tail -5)

# Check for common success patterns
while IFS= read -r line; do
  if [ -n "$line" ]; then
    SUCCESS_MARKERS+=("$line")
    if [ "$STATUS" = "running" ]; then
      STATUS="success"
    fi
  fi
done < <(echo "$CONTENT" | grep -iE '(completed|finished|done|passed|success|built)' | tail -5)

# Check for idle (prompt visible, no recent activity indicators)
# This is a heuristic - look for shell prompts at the end
LAST_LINE=$(echo "$CONTENT" | tail -1)
if echo "$LAST_LINE" | grep -qE '(\$|#|>)\s*$'; then
  if [ "$STATUS" = "running" ]; then
    STATUS="idle"
  fi
fi

# Build JSON output
if [ "$JSON_OUTPUT" = true ]; then
  # Escape content for JSON
  ESCAPED_LINES=$(echo "$CONTENT" | tail -"$LINES" | $TB_PYTHON -c '
import sys, json
lines = sys.stdin.read().split("\n")
print(json.dumps(lines[-20:] if len(lines) > 20 else lines))
')

  ESCAPED_ERRORS=$(printf '%s\n' "${ERRORS[@]}" | $TB_PYTHON -c '
import sys, json
lines = [l for l in sys.stdin.read().split("\n") if l]
print(json.dumps(lines))
')

  ESCAPED_SUCCESS=$(printf '%s\n' "${SUCCESS_MARKERS[@]}" | $TB_PYTHON -c '
import sys, json
lines = [l for l in sys.stdin.read().split("\n") if l]
print(json.dumps(lines))
')

  REPORT_JSON="null"
  if [ -n "$REPORT_PATH" ]; then
    REPORT_JSON="\"$REPORT_PATH\""
  fi

  cat <<EOF
{
  "status": "$STATUS",
  "idle_seconds": $IDLE_SECONDS,
  "last_lines": $ESCAPED_LINES,
  "detected": {
    "agent_done": $AGENT_DONE,
    "report_path": $REPORT_JSON,
    "errors": $ESCAPED_ERRORS,
    "success_markers": $ESCAPED_SUCCESS
  }
}
EOF
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Output Analysis: $SESSION_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Status: $STATUS"

  if [ "$AGENT_DONE" = true ]; then
    echo "Agent Done: ✅ Yes"
    [ -n "$REPORT_PATH" ] && echo "Report: $REPORT_PATH"
  fi

  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Errors detected:"
    for err in "${ERRORS[@]}"; do
      echo "   $err"
    done
  fi

  if [ ${#SUCCESS_MARKERS[@]} -gt 0 ]; then
    echo ""
    echo "✅ Success markers:"
    for succ in "${SUCCESS_MARKERS[@]}"; do
      echo "   $succ"
    done
  fi

  echo ""
  echo "📜 Last $LINES lines:"
  echo "───────────────────────────────────────"
  echo "$CONTENT" | tail -"$LINES"
  echo "───────────────────────────────────────"
fi

#!/bin/bash
# wait-for-pattern.sh - Wait for terminal output to match a pattern
#
# Usage: wait-for-pattern.sh <session_id> \
#          --success <pattern> [--fail <pattern>] \
#          [--timeout <sec>] [--interval <sec>] [--lines <N>]
#
# Returns:
#   0 = success pattern matched
#   1 = fail pattern matched
#   2 = timeout
#   3 = session died
#
# Output (JSON):
# { "result": "success|fail|timeout|dead", "matched_line": "...", "elapsed": 45 }
#
# Examples:
#   ./scripts/wait-for-pattern.sh bg:myproj:build.0 --success "Build completed" --fail "Error"
#   ./scripts/wait-for-pattern.sh ag:myproj:research.0 --success "\[AGENT_DONE\]" --timeout 300

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

# Defaults
SESSION_ID=""
SUCCESS_PATTERN=""
FAIL_PATTERN=""
TIMEOUT=300
INTERVAL=5
LINES=30

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --success)
      SUCCESS_PATTERN="$2"
      shift 2
      ;;
    --fail)
      FAIL_PATTERN="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --lines)
      LINES="$2"
      shift 2
      ;;
    *)
      if [ -z "$SESSION_ID" ]; then
        SESSION_ID="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$SESSION_ID" ] || [ -z "$SUCCESS_PATTERN" ]; then
  echo "Usage: wait-for-pattern.sh <session_id> --success <pattern> [--fail <pattern>] [--timeout <sec>]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  ./scripts/wait-for-pattern.sh bg:myproj:build.0 --success \"Build completed\"" >&2
  echo "  ./scripts/wait-for-pattern.sh ag:myproj:research.0 --success \"\\[AGENT_DONE\\]\" --timeout 600" >&2
  exit 1
fi

# Normalize session_id for backend calls
BACKEND_SESSION_ID="${SESSION_ID/bg:/wo:}"
BACKEND_SESSION_ID="${BACKEND_SESSION_ID/ag:/wo:}"

# Capture function
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

# Output result
_output_result() {
  local result="$1"
  local matched_line="$2"
  local elapsed="$3"

  # Escape for JSON
  matched_line=$(echo "$matched_line" | $TB_PYTHON -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')

  echo "{"
  echo "  \"result\": \"$result\","
  echo "  \"matched_line\": $matched_line,"
  echo "  \"elapsed\": $elapsed"
  echo "}"
}

echo "⏳ Waiting for pattern (timeout: ${TIMEOUT}s, interval: ${INTERVAL}s)..." >&2
echo "   Success pattern: $SUCCESS_PATTERN" >&2
[ -n "$FAIL_PATTERN" ] && echo "   Fail pattern: $FAIL_PATTERN" >&2
echo "" >&2

START_TIME=$(date +%s)
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
  # Check if session is alive
  if ! tb_is_session_alive "$BACKEND_SESSION_ID"; then
    echo "❌ Session died" >&2
    _output_result "dead" "" "$ELAPSED"
    exit 3
  fi

  # Capture content
  CONTENT=$(_capture_content "$BACKEND_SESSION_ID" "$LINES")

  # Check for success pattern
  MATCHED_LINE=$(echo "$CONTENT" | grep -E "$SUCCESS_PATTERN" | tail -1 || true)
  if [ -n "$MATCHED_LINE" ]; then
    echo "✅ Success pattern matched!" >&2
    _output_result "success" "$MATCHED_LINE" "$ELAPSED"
    exit 0
  fi

  # Check for fail pattern
  if [ -n "$FAIL_PATTERN" ]; then
    MATCHED_LINE=$(echo "$CONTENT" | grep -E "$FAIL_PATTERN" | tail -1 || true)
    if [ -n "$MATCHED_LINE" ]; then
      echo "❌ Fail pattern matched!" >&2
      _output_result "fail" "$MATCHED_LINE" "$ELAPSED"
      exit 1
    fi
  fi

  # Wait and update elapsed
  sleep "$INTERVAL"
  ELAPSED=$(( $(date +%s) - START_TIME ))

  # Progress indicator
  echo -n "." >&2
done

echo "" >&2
echo "⏰ Timeout reached after ${TIMEOUT}s" >&2
_output_result "timeout" "" "$ELAPSED"
exit 2

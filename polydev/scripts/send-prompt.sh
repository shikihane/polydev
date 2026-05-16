#!/bin/bash
# send-prompt.sh - Send a prompt to an already-ready agent pane.

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

PANE_ID=""
TEXT=""
FILE_PATH=""
PEEK_DELAY=""

usage() {
  echo "Usage: send-prompt.sh <pane_id> (--text <prompt> | --file <path>) [--peek N]" >&2
}

toon_log() {
  local event="$1"
  shift
  echo "[I] event=${event}${*:+,$*}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) TEXT="$2"; shift 2 ;;
    --file) FILE_PATH="$2"; shift 2 ;;
    --peek) PEEK_DELAY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [ -z "$PANE_ID" ]; then PANE_ID="$1"; else echo "[E] error=unexpected argument: $1" >&2; usage; exit 2; fi
      shift
      ;;
  esac
done

if [ -z "$PANE_ID" ] || { [ -z "$TEXT" ] && [ -z "$FILE_PATH" ]; }; then
  echo "[E] error=Missing required pane_id and prompt source" >&2
  usage
  exit 2
fi

if [ -n "$TEXT" ] && [ -n "$FILE_PATH" ]; then
  echo "[E] error=Use either --text or --file, not both" >&2
  exit 2
fi

if ! tb_is_session_alive "$PANE_ID" 2>/dev/null; then
  echo "[E] error=Session not alive: $PANE_ID" >&2
  exit 1
fi

if [ -n "$FILE_PATH" ]; then
  if [ ! -f "$FILE_PATH" ]; then
    echo "[E] error=Prompt file not found: $FILE_PATH" >&2
    exit 1
  fi
  PROMPT_PATH="$(cd "$(dirname "$FILE_PATH")" && pwd)/$(basename "$FILE_PATH")"
  AGENT_PATH="$(tb_path_to_agent "$PROMPT_PATH")"
  COMMAND="Read $AGENT_PATH and follow all instructions in it."
  SOURCE_INFO="path=$PROMPT_PATH"
else
  COMMAND="$TEXT"
  SOURCE_INFO="length=${#TEXT}"
fi

if ! POLYDEV_PREPARE_CWD=0 tb_send_command "$PANE_ID" "$COMMAND" "true" "${POLYDEV_PROMPT_ENTER_DELAY:-1}"; then
  echo "[E] error=Failed to send prompt" >&2
  exit 1
fi

toon_log "prompt_sent" "pane_id=$PANE_ID,$SOURCE_INFO"
if [ -n "$PEEK_DELAY" ]; then
  tb_peek "$PANE_ID" "$PEEK_DELAY"
fi

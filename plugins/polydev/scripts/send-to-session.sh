#!/bin/bash
# send-to-session.sh - Send command directly to a terminal session by pane_id
#
# Usage: send-to-session.sh <pane_id> <command> [--no-enter]
#
# Output (TOON):
#   [I] event=command_sent,pane_id=...,command=...,executed=true
#
# Example:
#   send-to-session.sh 5 "docker ps"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

PANE_ID=""
COMMAND=""
EXECUTE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-enter)
      EXECUTE="false"
      shift
      ;;
    *)
      if [ -z "$PANE_ID" ]; then
        PANE_ID="$1"
      elif [ -z "$COMMAND" ]; then
        COMMAND="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$PANE_ID" ] || [ -z "$COMMAND" ]; then
  echo "error=Missing pane_id or command" >&2
  echo "Usage: send-to-session.sh <pane_id> <command> [--no-enter]" >&2
  exit 1
fi

if ! tb_is_session_alive "$PANE_ID" 2>/dev/null; then
  echo "error=Session not alive: $PANE_ID" >&2
  exit 1
fi

if tb_send_command "$PANE_ID" "$COMMAND" "$EXECUTE"; then
  echo "[I] event=command_sent,pane_id=$PANE_ID,command=${COMMAND:0:50},executed=$EXECUTE"
else
  echo "[E] error=Failed to send command,pane_id=$PANE_ID" >&2
  exit 1
fi

#!/bin/bash
# wo-send-command.sh - Send command to an existing worktree session
#
# Usage: wo-send-command.sh <worktree_path> <command> [--no-enter]
#
# Output (TOON):
#   [I] event=command_sent,pane_id=...,command=...,executed=true
#
# Example:
#   wo-send-command.sh .worktrees/feature-auth "npm test"

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

WORKTREE_PATH=""
COMMAND=""
EXECUTE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-enter)
      EXECUTE="false"
      shift
      ;;
    *)
      if [ -z "$WORKTREE_PATH" ]; then
        WORKTREE_PATH="$1"
      elif [ -z "$COMMAND" ]; then
        COMMAND="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$WORKTREE_PATH" ] || [ -z "$COMMAND" ]; then
  echo "error=Missing worktree_path or command" >&2
  echo "Usage: wo-send-command.sh <worktree_path> <command> [--no-enter]" >&2
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "error=Worktree not found: $WORKTREE_PATH" >&2
  exit 1
fi

WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd)
TASK_FILE="$WORKTREE_PATH/task.toon"

if [ ! -f "$TASK_FILE" ]; then
  echo "error=task.toon not found in $WORKTREE_PATH" >&2
  exit 1
fi

meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
PANE_ID=$(echo "$meta_line" | cut -d',' -f3)

if [ -z "$PANE_ID" ] || [ "$PANE_ID" = "PENDING_PANE_ID" ]; then
  echo "error=No valid pane_id in task.toon" >&2
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

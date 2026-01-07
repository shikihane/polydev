#!/bin/bash
# wo-send-command.sh - Send command to an existing worktree session
#
# Usage: wo-send-command.sh <worktree_path> <command> [--no-enter]
#
# This script sends a command to an idle/active Codex session.
# By default, it appends Enter to execute the command immediately.
#
# Options:
#   --no-enter    Don't append Enter (just type the text)
#
# Examples:
#   wo-send-command.sh .worktrees/feature-auth "npm test"
#   wo-send-command.sh .worktrees/feature-auth "git status" --no-enter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

# Parse arguments
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

# Validation
if [ -z "$WORKTREE_PATH" ] || [ -z "$COMMAND" ]; then
  echo "Usage: wo-send-command.sh <worktree_path> <command> [--no-enter]"
  echo ""
  echo "Options:"
  echo "  --no-enter    Don't append Enter (just type the text)"
  echo ""
  echo "Examples:"
  echo "  wo-send-command.sh .worktrees/feature-auth \"npm test\""
  echo "  wo-send-command.sh .worktrees/feature-auth \"git status\" --no-enter"
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Error: Worktree path does not exist: $WORKTREE_PATH"
  exit 1
fi

WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd)  # Absolute path
TASK_FILE="$WORKTREE_PATH/task.toon"

# Check task.toon exists
if [ ! -f "$TASK_FILE" ]; then
  echo "Error: task.toon not found in $WORKTREE_PATH"
  echo "Hint: Use restore-session.sh first if session was lost"
  exit 1
fi

# Parse session_id from task.toon
meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
session_id=$(echo "$meta_line" | cut -d',' -f3)

if [ -z "$session_id" ] || [ "$session_id" = "PENDING_PANE_ID" ]; then
  echo "Error: No valid session_id in task.toon"
  echo "Session ID: $session_id"
  echo "Hint: Use restore-session.sh to create a new session"
  exit 1
fi

# Check if session is alive
if ! tb_is_session_alive "$session_id"; then
  echo "Error: Session is not alive: $session_id"
  echo "Hint: Use restore-session.sh to restore the session first"
  exit 1
fi

# Send the command
echo "Sending command to session: $session_id"
echo "Command: $COMMAND"
echo "Execute (Enter): $EXECUTE"
echo ""

if tb_send_command "$session_id" "$COMMAND" "$EXECUTE"; then
  if [ "$EXECUTE" = "true" ]; then
    echo "Sent and executed"
  else
    echo "Sent (no Enter)"
  fi
else
  echo "Error: Failed to send command"
  exit 1
fi

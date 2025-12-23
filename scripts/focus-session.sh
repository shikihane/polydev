#!/bin/bash
# focus-session.sh - Quickly activate a worktree's terminal session
#
# Usage: focus-session.sh <worktree-path>
# Supports both tmux (Linux/macOS) and wezterm (Windows) via terminal-backend.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

WORKTREE="$1"

if [ -z "$WORKTREE" ]; then
  echo "Usage: focus-session.sh <worktree-path>"
  exit 1
fi

TASK_FILE="$WORKTREE/task.toon"

if [ ! -f "$TASK_FILE" ]; then
  echo "Error: task.toon not found in $WORKTREE"
  exit 1
fi

# Parse session_id from meta line
meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
SESSION_ID=$(echo "$meta_line" | cut -d',' -f3)

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "PENDING_PANE_ID" ]; then
  echo "Error: session_id not found or pending in $TASK_FILE"
  exit 1
fi

# Activate the session using abstraction layer
tb_focus_session "$SESSION_ID"
echo "Focused on session $SESSION_ID ($WORKTREE) [backend: $(tb_get_backend)]"

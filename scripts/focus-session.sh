#!/bin/bash
# focus-session.sh - Activate a terminal session
#
# Usage:
#   focus-session.sh <session_id>        # Direct session ID (bg:, ag:, wo:)
#   focus-session.sh <worktree-path>     # Worktree path (reads session_id from task.toon)
#
# Examples:
#   focus-session.sh bg:bg-myproject:build.0
#   focus-session.sh ag:ag-myproject:research.0
#   focus-session.sh wo:myproject:feature-auth.0
#   focus-session.sh .worktrees/feature-auth

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

INPUT="$1"

if [ -z "$INPUT" ]; then
  echo "Usage: focus-session.sh <session_id | worktree-path>"
  echo ""
  echo "Examples:"
  echo "  focus-session.sh bg:bg-myproject:build.0"
  echo "  focus-session.sh ag:ag-myproject:research.0"
  echo "  focus-session.sh .worktrees/feature-auth"
  exit 1
fi

# Check if input is a session_id (has prefix wo:, bg:, or ag:)
if [[ "$INPUT" =~ ^(wo|bg|ag): ]]; then
  SESSION_ID="$INPUT"
else
  # Treat as worktree path
  WORKTREE="$INPUT"
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
fi

# Normalize to wo: for backend calls
BACKEND_SESSION_ID="${SESSION_ID/bg:/wo:}"
BACKEND_SESSION_ID="${BACKEND_SESSION_ID/ag:/wo:}"

# Activate the session using abstraction layer
tb_focus_session "$BACKEND_SESSION_ID"
echo "Focused on session $SESSION_ID [backend: $(tb_get_backend)]"

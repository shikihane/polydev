#!/bin/bash
# close-session.sh - Close/terminate a worktree session
#
# Usage: close-session.sh <worktree_path>  # By worktree path
#        close-session.sh --pane-id <pane_id>  # By pane_id
#
# Output (TOON):
#   [I] event=session_closed,pane_id=5
#
# Example:
#   close-session.sh .worktrees/feature-auth
#   close-session.sh --pane-id 5

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

PANE_ID=""
WORKTREE_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane-id)
      PANE_ID="$2"
      shift 2
      ;;
    *)
      WORKTREE_PATH="$1"
      shift
      ;;
  esac
done

# Get pane_id from worktree if not provided directly
if [ -z "$PANE_ID" ] && [ -n "$WORKTREE_PATH" ]; then
  if [ ! -d "$WORKTREE_PATH" ]; then
    echo "error=Worktree not found: $WORKTREE_PATH" >&2
    exit 1
  fi

  TASK_FILE="$WORKTREE_PATH/task.toon"
  if [ ! -f "$TASK_FILE" ]; then
    echo "error=task.toon not found in $WORKTREE_PATH" >&2
    exit 1
  fi

  meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
  PANE_ID=$(echo "$meta_line" | cut -d',' -f3)
  BRANCH=$(echo "$meta_line" | cut -d',' -f2)

  echo "[D] pane_id=$PANE_ID worktree=$WORKTREE_PATH branch=$BRANCH" >&2
fi

if [ -z "$PANE_ID" ]; then
  echo "error=Missing pane_id" >&2
  echo "Usage: close-session.sh <worktree_path>" >&2
  echo "       close-session.sh --pane-id <pane_id>" >&2
  exit 1
fi

# Check if session exists
if ! tb_is_session_alive "$PANE_ID" 2>/dev/null; then
  echo "[W] event=session_already_closed,pane_id=$PANE_ID"
  exit 0
fi

# Close the session
tb_cleanup_session "$PANE_ID"

echo "[I] event=session_closed,pane_id=$PANE_ID"

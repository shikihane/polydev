#!/bin/bash
# capture-screen.sh - Capture current terminal screen content
#
# Usage:
#   capture-screen.sh <worktree_path>           # By worktree path
#   capture-screen.sh --session <session_id>   # By session ID
#   capture-screen.sh <worktree_path> --lines 100  # Last N lines
#
# Examples:
#   capture-screen.sh .worktrees/feature-auth
#   capture-screen.sh --session wo:myproject:feature-auth.0
#   capture-screen.sh .worktrees/feature-auth --lines 50

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

SESSION_ID=""
WORKTREE_PATH=""
LINES_TO_CAPTURE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)
      SESSION_ID="$2"
      shift 2
      ;;
    --lines)
      LINES_TO_CAPTURE="$2"
      shift 2
      ;;
    *)
      if [ -z "$WORKTREE_PATH" ]; then
        WORKTREE_PATH="$1"
      fi
      shift
      ;;
  esac
done

# Get session_id from worktree if not provided directly
if [ -z "$SESSION_ID" ] && [ -n "$WORKTREE_PATH" ]; then
  if [ ! -d "$WORKTREE_PATH" ]; then
    echo "Error: Worktree not found: $WORKTREE_PATH" >&2
    exit 1
  fi

  TASK_FILE="$WORKTREE_PATH/task.toon"
  if [ ! -f "$TASK_FILE" ]; then
    echo "Error: task.toon not found in $WORKTREE_PATH" >&2
    exit 1
  fi

  # Extract session_id from task.toon
  meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
  SESSION_ID=$(echo "$meta_line" | cut -d',' -f3)
fi

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "PENDING_PANE_ID" ]; then
  echo "Error: No valid session ID found" >&2
  echo ""
  echo "Usage:"
  echo "  capture-screen.sh <worktree_path>"
  echo "  capture-screen.sh --session <session_id>"
  exit 1
fi

# Check if session is alive
if ! tb_is_session_alive "$SESSION_ID"; then
  echo "Error: Session is not alive: $SESSION_ID" >&2
  exit 1
fi

# Capture screen content based on backend
_capture_tmux() {
  local session_id="$1"
  local lines="$2"

  _parse_session_id "$session_id"

  if [ -n "$lines" ]; then
    # Capture scrollback + visible, then take last N lines
    _tmux capture-pane -t "$SESSION:$WINDOW.$PANE" -p -S -"$lines"
  else
    # Capture just the visible screen
    _tmux capture-pane -t "$SESSION:$WINDOW.$PANE" -p
  fi
}

_capture_wezterm() {
  local session_id="$1"
  local lines="$2"

  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -z "$pane_id" ]; then
    echo "Error: Could not find pane for session: $session_id" >&2
    return 1
  fi

  if [ -n "$lines" ]; then
    # Capture with scrollback
    wezterm cli get-text --pane-id "$pane_id" --start-line -"$lines"
  else
    # Capture visible screen (default)
    wezterm cli get-text --pane-id "$pane_id"
  fi
}

# Print header
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📺 Screen Capture: $SESSION_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

case "$TB_BACKEND" in
  tmux)
    _capture_tmux "$SESSION_ID" "$LINES_TO_CAPTURE"
    ;;
  wezterm)
    _capture_wezterm "$SESSION_ID" "$LINES_TO_CAPTURE"
    ;;
  *)
    echo "Error: Unknown backend: $TB_BACKEND" >&2
    exit 1
    ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

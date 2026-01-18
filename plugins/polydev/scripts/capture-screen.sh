#!/bin/bash
# capture-screen.sh - Capture current terminal screen content
#
# Usage:
#   capture-screen.sh <worktree_path>           # By worktree path
#   capture-screen.sh --pane-id <pane_id>       # By pane_id directly
#   capture-screen.sh <worktree_path> --lines 100  # Last N lines
#
# Output: Terminal screen content
# Stderr: Session info for human debugging (pane_id, worktree, branch)

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

PANE_ID=""
WORKTREE_PATH=""
LINES_TO_CAPTURE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane-id)
      PANE_ID="$2"
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

# Get pane_id and session info from worktree if not provided directly
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

if [ -z "$PANE_ID" ] || [ "$PANE_ID" = "PENDING_PANE_ID" ]; then
  echo "error=No valid pane_id found" >&2
  exit 1
fi

# Check if session is alive
if ! tb_is_session_alive "$PANE_ID" 2>/dev/null; then
  echo "error=Pane is not alive: $PANE_ID" >&2
  exit 1
fi

# Capture screen content
_capture_tmux() {
  local pane_id="$1"
  local lines="$2"

  if [ -n "$lines" ]; then
    _tmux capture-pane -t "$pane_id" -p -S -"$lines"
  else
    _tmux capture-pane -t "$pane_id" -p
  fi
}

_capture_wezterm() {
  local pane_id="$1"
  local lines="$2"

  if [ -n "$lines" ]; then
    # Get last N lines from scrollback
    wezterm cli get-text --pane-id "$pane_id" --start-line -"$lines" 2>/dev/null
  else
    # Default: get last 100 lines (visible area + some scrollback)
    # Note: without --start-line, wezterm only returns visible area
    # which may miss bottom status line
    wezterm cli get-text --pane-id "$pane_id" --start-line -100 2>/dev/null
  fi
}

case "$TB_BACKEND" in
  tmux)
    _capture_tmux "$PANE_ID" "$LINES_TO_CAPTURE"
    ;;
  wezterm)
    _capture_wezterm "$PANE_ID" "$LINES_TO_CAPTURE"
    ;;
  *)
    echo "error=Unknown backend: $TB_BACKEND" >&2
    exit 1
    ;;
esac

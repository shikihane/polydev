#!/bin/bash
# run-background.sh - Start a background command in terminal (no Claude)
#
# Usage: run-background.sh <name> "<command>" [--cwd <dir>] [--workspace <ws>] [--verbose]
#
# Output (TOON by default):
#   [I] event=bg_starting,name=...,workspace=...,cwd=...
#   [I] event=terminal_session_created,pane_id=...,backend=...
#   [I] event=command_sent,command=...
#   [I] event=bg_ready,pane_id=...
#   5  (pane_id on last line for scripting)
#
# Use --verbose for human-readable output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

NAME=""
COMMAND=""
CWD="$(pwd)"
WORKSPACE="$(basename "$(pwd)")"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)
      CWD="$2"
      shift 2
      ;;
    --workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      if [ -z "$NAME" ]; then
        NAME="$1"
      elif [ -z "$COMMAND" ]; then
        COMMAND="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$NAME" ] || [ -z "$COMMAND" ]; then
  echo "error=Missing name or command" >&2
  echo "Usage: run-background.sh <name> \"<command>\" [--cwd <dir>] [--workspace <ws>] [--verbose]" >&2
  exit 1
fi

if [ ! -d "$CWD" ]; then
  echo "error=Directory not found: $CWD" >&2
  exit 1
fi

CWD="$(cd "$CWD" && pwd)"

if $VERBOSE; then
  echo "Starting Background Task"
  echo "Name: $NAME"
  echo "Command: $COMMAND"
  echo "Directory: $CWD"
  echo "Workspace: $WORKSPACE"
  echo "Backend: $(tb_get_backend)"
  echo ""
fi

toon_log() {
  local event="$1"
  shift
  local pairs="$*"
  echo "[I] event=${event}${pairs:+,${pairs}}"
}

toon_log "bg_starting" "name=$NAME,workspace=$WORKSPACE,cwd=$CWD"

# Create session
bg_workspace="bg-${WORKSPACE}"
pane_id=$(tb_create_worktree_session "$bg_workspace" "$NAME" "$CWD" "")

toon_log "terminal_session_created" "pane_id=$pane_id,backend=$(tb_get_backend)"

sleep 0.5

# Send command
if tb_send_command "$pane_id" "$COMMAND" "true"; then
  toon_log "command_sent" "command=${COMMAND:0:50}"
else
  echo "[E] error=Failed to send command" >&2
  exit 1
fi

toon_log "bg_ready" "pane_id=$pane_id"

if $VERBOSE; then
  echo ""
  echo "Background task started: pane_id=$pane_id"
  echo "Monitor: capture-screen.sh --pane-id $pane_id --lines 50"
fi

echo "$pane_id"

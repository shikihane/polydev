#!/bin/bash
# run-background.sh - Start a background command in terminal (no Codex agent)
#
# Usage: run-background.sh <name> "<command>" [--cwd <dir>] [--workspace <ws>]
#
# Returns: session_id (format: bg:<workspace>:<name>.0)
#
# Examples:
#   ./scripts/run-background.sh build "npm run build"
#   ./scripts/run-background.sh dev "npm run dev" --cwd ./frontend
#   ./scripts/run-background.sh test "pytest" --workspace myproject
#
# Note on Enter/newline handling:
#   This script uses tb_send_command which properly handles Enter key:
#   - tmux: uses send-keys C-m (Ctrl-M)
#   - wezterm: uses printf + pipe (not command line args)
#   See: https://github.com/wezterm/wezterm/discussions/4950

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

# Defaults
NAME=""
COMMAND=""
CWD="$(pwd)"
WORKSPACE="$(basename "$(pwd)")"

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
  echo "Usage: run-background.sh <name> \"<command>\" [--cwd <dir>] [--workspace <ws>]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  ./scripts/run-background.sh build \"npm run build\"" >&2
  echo "  ./scripts/run-background.sh dev \"npm run dev\" --cwd ./frontend" >&2
  exit 1
fi

# Validate CWD
if [ ! -d "$CWD" ]; then
  echo "Error: Directory not found: $CWD" >&2
  exit 1
fi

# Convert to absolute path
CWD="$(cd "$CWD" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Starting Background Task"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Name:      $NAME"
echo "Command:   $COMMAND"
echo "Directory: $CWD"
echo "Workspace: $WORKSPACE"
echo "Backend:   $(tb_get_backend)"
echo ""

# Create session using terminal backend
# Use "bg-" prefix for workspace to distinguish from worktree sessions
bg_workspace="bg-${WORKSPACE}"

echo "🖥️  Creating terminal session..."

# tb_create_worktree_session returns wo: prefixed session_id
# We keep the internal wo: format for backend compatibility
internal_session_id=$(tb_create_worktree_session "$bg_workspace" "$NAME" "$CWD" "")

# External session_id uses bg: prefix for clarity
external_session_id="${internal_session_id/wo:/bg:}"

echo "   ✅ Session created: $external_session_id"

# Wait a moment for the shell to be ready
sleep 0.5

# Send the command using tb_send_command
# This properly handles Enter key for both tmux and wezterm
echo ""
echo "📤 Sending command..."
if tb_send_command "$internal_session_id" "$COMMAND" "true"; then
  echo "   ✅ Command sent and executed"
else
  echo "   ❌ Failed to send command" >&2
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Background task started!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Session ID: $external_session_id"
echo ""
echo "💡 Monitor with:"
echo "   ./scripts/analyze-output.sh $external_session_id --lines 20"
echo ""
echo "💡 Wait for completion:"
echo "   ./scripts/wait-for-pattern.sh $external_session_id --success \"Done\" --fail \"Error\""
echo ""
echo "💡 View output:"
echo "   ./scripts/capture-screen.sh --session $internal_session_id --lines 50"
echo ""

# Output only the session_id for scripting (last line)
echo "$external_session_id"

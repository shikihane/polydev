#!/bin/bash
# close-session.sh - Close/terminate a worktree session
#
# Usage: close-session.sh <session_id>
#
# Example:
#   close-session.sh wo:myproject:feature-auth.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

SESSION_ID="$1"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: close-session.sh <session_id>"
  echo ""
  echo "Example:"
  echo "  close-session.sh wo:myproject:feature-auth.0"
  echo ""
  echo "Use list-sessions.sh to see active sessions."
  exit 1
fi

# Validate session_id format
if [[ ! "$SESSION_ID" =~ ^wo: ]]; then
  echo "Error: Invalid session_id format."
  echo "Expected format: wo:workspace:window.pane"
  exit 1
fi

# Check if session exists
if ! tb_is_session_alive "$SESSION_ID"; then
  echo "Session not found or already closed: $SESSION_ID"
  exit 0
fi

# Get session info before closing
info=$(tb_get_session_info "$SESSION_ID")
echo "Closing session: $SESSION_ID"
echo "  Info: $info"

# Close the session
tb_cleanup_session "$SESSION_ID"

echo "Session closed successfully."

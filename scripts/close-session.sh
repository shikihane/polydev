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
  echo "Examples:"
  echo "  close-session.sh wo:myproject:feature-auth.0"
  echo "  close-session.sh bg:myproject:build.0"
  echo "  close-session.sh ag:myproject:research.0"
  echo ""
  echo "Use list-sessions.sh to see active sessions."
  exit 1
fi

# Validate session_id format (supports wo:, bg:, ag: prefixes)
if [[ ! "$SESSION_ID" =~ ^(wo|bg|ag): ]]; then
  echo "Error: Invalid session_id format."
  echo "Expected format: wo:|bg:|ag:workspace:window.pane"
  exit 1
fi

# Normalize to wo: for backend calls
BACKEND_SESSION_ID="${SESSION_ID/bg:/wo:}"
BACKEND_SESSION_ID="${BACKEND_SESSION_ID/ag:/wo:}"

# Check if session exists
if ! tb_is_session_alive "$BACKEND_SESSION_ID"; then
  echo "Session not found or already closed: $SESSION_ID"
  exit 0
fi

# Get session info before closing
info=$(tb_get_session_info "$BACKEND_SESSION_ID")
echo "Closing session: $SESSION_ID"
echo "  Info: $info"

# Close the session
tb_cleanup_session "$BACKEND_SESSION_ID"

echo "Session closed successfully."

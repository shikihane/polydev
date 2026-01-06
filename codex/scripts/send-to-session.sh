#!/bin/bash
# send-to-session.sh - Send command directly to a terminal session by session ID
#
# SCENARIO: Use when you have a session_id (bg:xxx, wo:xxx, ag:xxx) and want to
#           send commands to it. This is for INTERACTIVE sessions like SSH, REPL, etc.
#
# DO NOT USE FOR:
#   - Worktree sessions with task.toon (use send-command.sh with worktree path instead)
#   - Starting new background tasks (use run-background.sh instead)
#
# Usage: send-to-session.sh <session_id> <command> [--no-enter]
#
# Parameters:
#   session_id  - The session ID in format: bg:<workspace>:<name>.0 or wo:<workspace>:<name>.0
#   command     - The command/text to send
#   --no-enter  - Don't press Enter after sending (just type the text)
#
# Examples:
#   send-to-session.sh bg:bg-polydev:ssh-remote.0 "docker ps"
#   send-to-session.sh bg:bg-polydev:ssh-remote.0 "password123" --no-enter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

# Parse arguments
SESSION_ID=""
COMMAND=""
EXECUTE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-enter)
      EXECUTE="false"
      shift
      ;;
    *)
      if [ -z "$SESSION_ID" ]; then
        SESSION_ID="$1"
      elif [ -z "$COMMAND" ]; then
        COMMAND="$1"
      fi
      shift
      ;;
  esac
done

# Validation
if [ -z "$SESSION_ID" ] || [ -z "$COMMAND" ]; then
  echo "Usage: send-to-session.sh <session_id> <command> [--no-enter]"
  echo ""
  echo "SCENARIO: Send commands to interactive terminal sessions (SSH, REPL, etc.)"
  echo ""
  echo "Parameters:"
  echo "  session_id  - Session ID (bg:xxx, wo:xxx, ag:xxx format)"
  echo "  command     - Command or text to send"
  echo "  --no-enter  - Don't press Enter (just type the text)"
  echo ""
  echo "Examples:"
  echo "  send-to-session.sh bg:bg-polydev:ssh-remote.0 \"docker ps\""
  echo "  send-to-session.sh bg:bg-polydev:ssh-remote.0 \"password\" --no-enter"
  exit 1
fi

# Validate session ID format
if [[ ! "$SESSION_ID" =~ ^(bg|wo|ag): ]]; then
  echo "Error: Invalid session_id format: $SESSION_ID"
  echo "Expected format: bg:<workspace>:<name>.0 or wo:<workspace>:<name>.0"
  exit 1
fi

# Convert bg:/ag: prefix to wo: for internal use (terminal-backend uses wo: internally)
INTERNAL_ID="${SESSION_ID/bg:/wo:}"
INTERNAL_ID="${INTERNAL_ID/ag:/wo:}"

# Check if session is alive
if ! tb_is_session_alive "$INTERNAL_ID"; then
  echo "Error: Session is not alive: $SESSION_ID"
  echo ""
  echo "Check active sessions with:"
  echo "  \$POLYDEV_SCRIPTS/list-sessions.sh"
  exit 1
fi

# Send the command
echo "Sending to session: $SESSION_ID"
echo "Command: $COMMAND"
echo "Execute (Enter): $EXECUTE"
echo ""

if tb_send_command "$INTERNAL_ID" "$COMMAND" "$EXECUTE"; then
  if [ "$EXECUTE" = "true" ]; then
    echo "Sent and executed"
  else
    echo "Sent (no Enter)"
  fi
else
  echo "Error: Failed to send command"
  exit 1
fi

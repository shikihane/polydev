#!/bin/bash
# restore-session.sh - Manage worktree sessions (restore/restart/attach)
#
# Usage: restore-session.sh <worktree_path> [--force]
#
# This script handles multiple scenarios:
# 1. Session crashed → Restore from backup and restart
# 2. Session idle (stopped) → Restart with existing task.toon
# 3. Session active but want restart → Kill and restart (with --force)
# 4. task.toon missing → Restore from backup
#
# Options:
#   --force    Force restart even if session is alive

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/terminal-backend.sh"

WORKTREE_PATH="$1"
FORCE_RESTART=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE_RESTART=true
      shift
      ;;
    *)
      if [ -z "$WORKTREE_PATH" ]; then
        WORKTREE_PATH="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  echo "error=Missing or invalid worktree_path" >&2
  echo "Usage: restore-session.sh <worktree_path> [--force]" >&2
  exit 1
fi

WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd)
TASK_FILE="$WORKTREE_PATH/task.toon"
PLAN_FILE="$WORKTREE_PATH/PLAN.md"
BACKUP_DIR="$WORKTREE_PATH/.task_backups"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Worktree Session Recovery"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Worktree: $WORKTREE_PATH"
echo ""

# Step 1: Check for task.toon
if [ ! -f "$TASK_FILE" ]; then
  echo "task.toon not found!"

  if [ -d "$BACKUP_DIR" ]; then
    latest_backup=$(ls -t "$BACKUP_DIR"/task.toon.*.bak 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
      echo "Found backup: $(basename "$latest_backup")"
      cp "$latest_backup" "$TASK_FILE"
      echo "Restored task.toon from backup"
    else
      echo "No backups found in $BACKUP_DIR"
      exit 1
    fi
  else
    echo "No backup directory found"
    exit 1
  fi
fi

# Step 2: Parse task.toon metadata
echo ""
echo "Reading task.toon metadata..."
meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
branch=$(echo "$meta_line" | cut -d',' -f2)
old_pane_id=$(echo "$meta_line" | cut -d',' -f3)
workspace=$(echo "$meta_line" | cut -d',' -f1)

echo "  Branch: $branch"
echo "  Workspace: $workspace"
echo "  Old Pane ID: $old_pane_id"

# Step 3: Check if session is alive and determine action
SESSION_ALIVE=false
if [ "$old_pane_id" != "PENDING_PANE_ID" ]; then
  if tb_is_session_alive "$old_pane_id"; then
    SESSION_ALIVE=true
    echo "  Status: ACTIVE"
  else
    echo "  Status: DEAD"
  fi
else
  echo "  Status: NEVER STARTED"
fi

# Step 4: Handle active session
if [ "$SESSION_ALIVE" = "true" ]; then
  if [ "$FORCE_RESTART" = "true" ]; then
    echo ""
    echo "Force killing active session..."
    tb_cleanup_session "$old_pane_id"
    echo "Session terminated"
  else
    echo ""
    echo "ERROR: Session is still ACTIVE"
    echo ""
    echo "Pane ID: $old_pane_id"
    echo "Use --force to kill and restart: restore-session.sh $WORKTREE_PATH --force"
    echo "Or use wezterm/tmux directly to focus the session"
    exit 2
  fi
fi

# Step 5: Auto restart
echo ""
echo "Auto-restarting session..."

# Step 6: Create new session
echo "Creating new terminal session..."

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "workspace")")
WORKSPACE="${PROJECT_NAME}-parallel"

if [ ! -f "$PLAN_FILE" ]; then
  echo "Warning: PLAN.md not found in worktree"
  PLAN_FILE=""
fi

new_pane_id=$(tb_create_worktree_session "$WORKSPACE" "$branch" "$WORKTREE_PATH" "$PLAN_FILE")
echo "Created: pane_id=$new_pane_id"

# Step 7: Update task.toon with new pane_id
echo ""
echo "Updating task.toon..."

if [ -f "$TASK_FILE" ]; then
  mkdir -p "$BACKUP_DIR"
  timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$TASK_FILE" "$BACKUP_DIR/task.toon.${timestamp}.bak"
fi

tmp_file="${TASK_FILE}.tmp.$$"
if [ "$old_pane_id" = "PENDING_PANE_ID" ]; then
  sed "s|PENDING_PANE_ID|$new_pane_id|" "$TASK_FILE" > "$tmp_file"
else
  sed "s|$old_pane_id|$new_pane_id|g" "$TASK_FILE" > "$tmp_file"
fi
mv "$tmp_file" "$TASK_FILE"

echo "Updated pane_id to: $new_pane_id"

# Step 8: Start Claude
echo ""
echo "Starting Claude..."

# Capture terminal state before starting Claude (for change detection)
initial_content=$(tb_capture_content "$new_pane_id")

if ! tb_send_command "$new_pane_id" "claude --dangerously-skip-permissions"; then
  echo "Failed to start Claude"
  echo "Pane ID: $new_pane_id"
  exit 1
fi

# Wait for Claude to start (detects terminal content change, max 15s)
tb_wait_for_claude "$new_pane_id" 15 "$initial_content"

# Send the agent prompt
if [ -f "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md" ]; then
  echo ""
  echo "Sending agent prompt..."
  prompt=$(cat "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md")

  if tb_send_multiline_text "$new_pane_id" "$prompt" "true"; then
    echo "Prompt sent successfully"
  else
    echo "Warning: Prompt may not have been sent"
  fi
else
  echo "Warning: Agent prompt file not found"
fi

echo "Claude started and configured"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Recovery complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pane ID: $new_pane_id"
echo "Workspace: $workspace"
echo "Branch: $branch"
echo "Backend: $(tb_get_backend)"

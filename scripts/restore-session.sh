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

# Source terminal backend abstraction
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
  echo "Usage: restore-session.sh <worktree_path> [--force]"
  echo ""
  echo "Examples:"
  echo "  restore-session.sh .worktrees/feature-auth           # Restore/restart session"
  echo "  restore-session.sh .worktrees/feature-auth --force   # Force restart active session"
  exit 1
fi

WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd)  # Absolute path
TASK_FILE="$WORKTREE_PATH/task.toon"
PLAN_FILE="$WORKTREE_PATH/PLAN.md"
BACKUP_DIR="$WORKTREE_PATH/.task_backups"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Worktree Session Recovery"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Worktree: $WORKTREE_PATH"
echo ""

# Step 1: Check for task.toon
if [ ! -f "$TASK_FILE" ]; then
  echo "❌ task.toon not found!"
  echo ""

  # Try to restore from backup
  if [ -d "$BACKUP_DIR" ]; then
    latest_backup=$(ls -t "$BACKUP_DIR"/task.toon.*.bak 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
      echo "📦 Found backup: $(basename "$latest_backup")"
      echo -n "Restore from backup? [y/N] "
      read -r response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        cp "$latest_backup" "$TASK_FILE"
        echo "✅ Restored task.toon from backup"
      else
        echo "❌ Cannot proceed without task.toon"
        exit 1
      fi
    else
      echo "❌ No backups found in $BACKUP_DIR"
      exit 1
    fi
  else
    echo "❌ No backup directory found"
    exit 1
  fi
fi

# Step 2: Parse task.toon metadata
echo ""
echo "📋 Reading task.toon metadata..."
meta_line=$(grep -A1 "^meta{" "$TASK_FILE" | tail -1 | tr -d ' ')
branch=$(echo "$meta_line" | cut -d',' -f2)
old_session_id=$(echo "$meta_line" | cut -d',' -f3)

echo "  Branch: $branch"
echo "  Old Session ID: $old_session_id"

# Step 3: Check if session is alive and determine action
SESSION_ALIVE=false
if [ "$old_session_id" != "PENDING_PANE_ID" ]; then
  if tb_is_session_alive "$old_session_id"; then
    SESSION_ALIVE=true
    echo "  Status: ✅ ACTIVE"
  else
    echo "  Status: 💀 DEAD"
  fi
else
  echo "  Status: ⏳ NEVER STARTED"
fi

# Step 4: Handle active session
if [ "$SESSION_ALIVE" = "true" ]; then
  if [ "$FORCE_RESTART" = "true" ]; then
    echo ""
    echo "⚠️  Forcing restart of active session (--force flag)"
    echo ""
    echo "This will:"
    echo "  1. Kill the current session"
    echo "  2. Create a new session"
    echo "  3. Restart Claude"
    echo ""
    echo -n "Continue? [y/N] "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      exit 0
    fi

    # Kill existing session
    echo ""
    echo "🔪 Killing existing session..."
    tb_cleanup_session "$old_session_id"
    echo "   ✅ Session terminated"
  else
    # Session is alive and no --force flag
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Session is currently active"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "What would you like to do?"
    echo "  [1] Attach to existing session (focus-session.sh)"
    echo "  [2] Kill and restart session"
    echo "  [3] Cancel"
    echo ""
    echo -n "Choose [1-3]: "
    read -r choice

    case "$choice" in
      1)
        echo ""
        echo "📍 Focusing session..."
        tb_focus_session "$old_session_id"
        echo "   ✅ Session focused"
        echo ""
        echo "Alternatively, run:"
        echo "  ./scripts/focus-session.sh $WORKTREE_PATH"
        exit 0
        ;;
      2)
        echo ""
        echo "🔪 Killing existing session..."
        tb_cleanup_session "$old_session_id"
        echo "   ✅ Session terminated"
        # Continue to restart
        ;;
      *)
        echo "Cancelled."
        exit 0
        ;;
    esac
  fi
fi

# Step 5: Prompt user for restart action (session is dead or killed)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Session restart options:"
echo "  [1] Create new session and restart Claude (recommended)"
echo "  [2] Just create session (manual Claude start)"
echo "  [3] Cancel"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -n "Choose [1-3]: "
read -r choice

case "$choice" in
  1|2)
    ;;
  *)
    echo "Cancelled."
    exit 0
    ;;
esac

# Step 6: Create new session
echo ""
echo "🔨 Creating new terminal session..."

# Extract workspace from worktree path
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "workspace")")
WORKSPACE="${PROJECT_NAME}-parallel"

# Check if PLAN.md exists
if [ ! -f "$PLAN_FILE" ]; then
  echo "⚠️  Warning: PLAN.md not found in worktree"
  echo "   Recovery will proceed without plan file"
  echo "   You may need to restore PLAN.md manually"
  PLAN_FILE=""
fi

new_session_id=$(tb_create_worktree_session "$WORKSPACE" "$branch" "$WORKTREE_PATH" "$PLAN_FILE")
echo "✅ Created: $new_session_id"

# Step 7: Update task.toon with new session_id
echo ""
echo "📝 Updating task.toon..."

# Backup before modification
if [ -f "$TASK_FILE" ]; then
  mkdir -p "$BACKUP_DIR"
  timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$TASK_FILE" "$BACKUP_DIR/task.toon.${timestamp}.bak"
fi

# Replace old session_id with new one
# Use | delimiter which is safe for session_id format (wo:workspace:branch.N)
tmp_file="${TASK_FILE}.tmp.$$"
if [ "$old_session_id" = "PENDING_PANE_ID" ]; then
  sed "s|PENDING_PANE_ID|$new_session_id|" "$TASK_FILE" > "$tmp_file"
else
  # No escaping needed - session_id never contains | character
  sed "s|$old_session_id|$new_session_id|g" "$TASK_FILE" > "$tmp_file"
fi
mv "$tmp_file" "$TASK_FILE"

echo "✅ Updated session_id to: $new_session_id"

# Step 8: Start Claude if requested
if [ "$choice" = "1" ]; then
  echo ""
  echo "🤖 Starting Claude..."
  tb_send_command "$new_session_id" "claude --dangerously-skip-permissions"

  # Wait and send prompt
  (
    sleep 4
    if [ -f "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md" ]; then
      prompt=$(cat "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md")
      tb_send_command "$new_session_id" "$prompt"
    fi
  ) &

  echo "✅ Claude started"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Recovery complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Session ID: $new_session_id"
echo "Backend: $(tb_get_backend)"
echo ""
echo "Next steps:"
echo "  - Use focus-session.sh to attach: ./scripts/focus-session.sh $WORKTREE_PATH"
echo "  - Or manually attach to: $new_session_id"

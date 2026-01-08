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
      cp "$latest_backup" "$TASK_FILE"
      echo "✅ Auto-restored task.toon from backup"
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
    # --force: 直接执行，不询问
    echo ""
    echo "🔪 Force killing active session..."
    tb_cleanup_session "$old_session_id"
    echo "   ✅ Session terminated"
  else
    # Session is alive and no --force flag → 报错退出
    echo ""
    echo "❌ ERROR: Session is still ACTIVE"
    echo ""
    echo "Session ID: $old_session_id"
    echo "Use --force to kill and restart: ./scripts/restore-session.sh $WORKTREE_PATH --force"
    echo "Or focus the session: ./scripts/focus-session.sh $WORKTREE_PATH"
    exit 2  # Exit code 2 = session still active
  fi
fi

# Step 5: Auto restart (session is dead or killed)
# 自动选择选项 1：创建会话并启动 Claude
choice=1
echo ""
echo "🔄 Auto-restarting session with Claude..."

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

  # Start Claude
  if ! tb_send_command "$new_session_id" "claude --dangerously-skip-permissions"; then
    echo "❌ Failed to start Claude"
    echo "   Session ID: $new_session_id"
    echo "   Try manually: ./scripts/focus-session.sh $WORKTREE_PATH"
    exit 1
  fi

  # Wait for Claude to start (with visual feedback)
  tb_wait_for_claude "$new_session_id" 15

  # Send the agent prompt
  if [ -f "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md" ]; then
    echo ""
    echo "📤 Sending agent prompt..."
    prompt=$(cat "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md")

    if tb_send_multiline_text "$new_session_id" "$prompt" "true"; then
      echo "   ✅ Prompt sent successfully"
    else
      echo "   ⚠️  Warning: Prompt may not have been sent"
      echo "   You can manually send it by attaching to the session"
    fi
  else
    echo "⚠️  Warning: Agent prompt file not found"
    echo "   Claude started without initial prompt"
  fi

  echo "✅ Claude started and configured"
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

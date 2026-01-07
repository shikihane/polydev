#!/bin/bash
# cleanup-worktree.sh - Clean up worktree
#
# Usage: cleanup-worktree.sh <worktree_path>

set -e

WORKTREE_PATH="$1"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Usage: cleanup-worktree.sh <worktree_path>"
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "❌ Directory not found: $WORKTREE_PATH"
  exit 1
fi

WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd)
TASK_FILE="$WORKTREE_PATH/task.toon"

echo "🧹 Cleaning: $WORKTREE_PATH"

# Backup task.toon
if [ -f "$TASK_FILE" ]; then
  backup_dir="$WORKTREE_PATH/.task_backups"
  mkdir -p "$backup_dir"
  cp "$TASK_FILE" "$backup_dir/task.toon.$(date +%Y%m%d_%H%M%S).bak"
fi

# Delete files and remove worktree
rm -rf "$WORKTREE_PATH"
git worktree prune 2>/dev/null || true

echo "✅ Done"

#!/bin/bash
# cleanup-worktree.sh - Safely clean up worktree files
#
# Usage: cleanup-worktree.sh <worktree_path>
#
# This script provides safe cleanup with multiple confirmations
# and automatic backup of important files before deletion.

set -e

WORKTREE_PATH="$1"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Usage: cleanup-worktree.sh <worktree_path>"
  echo "Example: cleanup-worktree.sh .worktrees/feature-auth"
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "❌ Error: Directory not found: $WORKTREE_PATH"
  exit 1
fi

WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd)  # Absolute path
TASK_FILE="$WORKTREE_PATH/task.toon"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 Safe Worktree Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  SAFETY CHECK"
echo ""
echo "Current directory: $(pwd)"
echo "Target directory:  $WORKTREE_PATH"
echo ""

# Safety check 1: Confirm directory
if [ "$(pwd)" = "$WORKTREE_PATH" ]; then
  echo "⚠️  WARNING: You are currently IN the target directory!"
  echo "   It's safer to run this from the parent directory."
  echo ""
fi

# Safety check 2: Check if it's a git worktree
if ! git -C "$WORKTREE_PATH" rev-parse --git-dir &>/dev/null; then
  echo "⚠️  WARNING: This doesn't appear to be a Git worktree!"
  echo ""
fi

# Safety check 3: Show what will be deleted
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Files/directories that will be deleted:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# List key files
declare -a files_to_check=(
  "task.toon"
  "PLAN.md"
  ".claude/"
  "src/"
  "tests/"
  "pyproject.toml"
  "package.json"
  "uv.lock"
  "package-lock.json"
)

found_files=()
for file in "${files_to_check[@]}"; do
  if [ -e "$WORKTREE_PATH/$file" ]; then
    if [ -d "$WORKTREE_PATH/$file" ]; then
      size=$(du -sh "$WORKTREE_PATH/$file" 2>/dev/null | cut -f1)
      echo "  📁 $file/ ($size)"
    else
      size=$(du -h "$WORKTREE_PATH/$file" 2>/dev/null | cut -f1)
      echo "  📄 $file ($size)"
    fi
    found_files+=("$file")
  fi
done

if [ ${#found_files[@]} -eq 0 ]; then
  echo "  (No significant files found)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Backup task.toon if it exists
if [ -f "$TASK_FILE" ]; then
  echo "📦 Backing up task.toon..."
  backup_dir="$WORKTREE_PATH/.task_backups"
  mkdir -p "$backup_dir"
  timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$TASK_FILE" "$backup_dir/task.toon.${timestamp}.bak"
  echo "   ✅ Saved to: $backup_dir/task.toon.${timestamp}.bak"
  echo ""
fi

# Final confirmation
echo "⚠️  FINAL CONFIRMATION"
echo ""
echo "This will permanently delete all files in:"
echo "  $WORKTREE_PATH"
echo ""
echo "Type the worktree name to confirm deletion: $(basename "$WORKTREE_PATH")"
echo -n "> "
read -r confirmation

if [ "$confirmation" != "$(basename "$WORKTREE_PATH")" ]; then
  echo ""
  echo "❌ Confirmation failed. Cleanup cancelled."
  echo "   You typed: '$confirmation'"
  echo "   Expected: '$(basename "$WORKTREE_PATH")'"
  exit 1
fi

echo ""
echo "🗑️  Deleting files..."

# Delete everything except backups
if ! find "$WORKTREE_PATH" -mindepth 1 -maxdepth 1 ! -name '.task_backups' -exec rm -rf {} + 2>&1; then
  echo ""
  echo "⚠️  Warning: Some files could not be deleted"
  echo "   This may be due to permission issues or files in use"
  echo "   You may need to manually remove remaining files"
  echo ""
  echo "Remaining files:"
  ls -la "$WORKTREE_PATH" 2>/dev/null || true
  echo ""
else
  echo "✅ Cleanup complete!"
fi
echo ""
echo "Backups preserved at: $WORKTREE_PATH/.task_backups"
echo ""
echo "To remove the worktree from git:"
echo "  git worktree remove \"$WORKTREE_PATH\""

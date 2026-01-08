#!/bin/bash
# git-info.sh - Read-only Git status checks
#
# Usage: git-info.sh <action> <worktree-path>
#
# Actions:
#   diff      - Show commits ahead of main
#   conflicts - Show files that might conflict with main
#   status    - Show working directory status

ACTION="$1"
WORKTREE="$2"

if [ -z "$ACTION" ] || [ -z "$WORKTREE" ]; then
  echo "Usage: git-info.sh <diff|conflicts|status> <worktree-path>"
  exit 1
fi

if [ ! -d "$WORKTREE" ]; then
  echo "Error: Worktree directory not found: $WORKTREE"
  exit 1
fi

cd "$WORKTREE" || exit 1

case "$ACTION" in
  diff)
    # Show commits ahead of main
    git log --oneline main..HEAD
    ;;
  conflicts)
    # Show files changed in both branches (potential conflicts)
    git diff --name-only main...HEAD
    ;;
  status)
    # Show working directory status
    git status --short
    ;;
  *)
    echo "Unknown action: $ACTION"
    echo "Usage: git-info.sh <diff|conflicts|status> <worktree-path>"
    exit 1
    ;;
esac

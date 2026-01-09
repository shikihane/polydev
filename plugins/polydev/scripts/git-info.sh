#!/bin/bash
# git-info.sh - Read-only Git status checks
#
# Usage: git-info.sh <action> <worktree-path>
#
# Actions:
#   diff      - Show commits ahead of main
#   conflicts - Show files that might conflict with main
#   status    - Show working directory status
#
# Output (TOON):
#   action=diff,commits="<list of commits>"
#   action=conflicts,files="<list of files>"
#   action=status,files="<list of files>"

ACTION="$1"
WORKTREE="$2"

if [ -z "$ACTION" ] || [ -z "$WORKTREE" ]; then
  echo "error=Missing action or worktree" >&2
  echo "Usage: git-info.sh <diff|conflicts|status> <worktree-path>" >&2
  exit 1
fi

if [ ! -d "$WORKTREE" ]; then
  echo "error=Worktree not found: $WORKTREE" >&2
  exit 1
fi

cd "$WORKTREE" || exit 1

case "$ACTION" in
  diff)
    commits=$(git log --oneline main..HEAD 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    echo "action=diff,commits=${commits:-none}"
    ;;
  conflicts)
    files=$(git diff --name-only main...HEAD 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    echo "action=conflicts,files=${files:-none}"
    ;;
  status)
    files=$(git status --short 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    echo "action=status,files=${files:-none}"
    ;;
  *)
    echo "error=Unknown action: $ACTION" >&2
    exit 1
    ;;
esac

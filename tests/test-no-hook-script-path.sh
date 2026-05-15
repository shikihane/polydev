#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

scan_paths=(
  "$ROOT_DIR/README.md"
  "$ROOT_DIR/CLAUDE.md"
  "$ROOT_DIR/AGENTS.md"
  "$ROOT_DIR/polydev"
)

reject_pattern() {
  local pattern="$1"
  local label="$2"

  if rg -n -S --glob '!**/dashboard/server/shell.test.js' "$pattern" "${scan_paths[@]}"; then
    echo "forbidden ${label}: ${pattern}" >&2
    failures=$((failures + 1))
  fi
}

reject_pattern 'SessionStart|CLAUDE_PLUGIN_ROOT|hook-written|path discovery|路径发现|注入' 'path or lifecycle dependency'
reject_pattern '[A-Z]:\\Users\\[^<]|/c/Users/[^<]|@[[:alnum:]_.-]+\.com' 'local or personal path'
reject_pattern '\.claude/hooks|hooks/' 'runtime lifecycle installation'

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "no hook script path tests passed"

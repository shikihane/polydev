#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "failed: $*" >&2
  exit 1
}

require_text() {
  local file="$1"
  local text="$2"

  grep -Fq -- "$text" "$ROOT_DIR/$file" || fail "$file missing required text: $text"
}

reject_text() {
  local file="$1"
  local text="$2"

  if grep -Fq -- "$text" "$ROOT_DIR/$file"; then
    fail "$file contains stale script root guidance: $text"
  fi
}

for file in AGENTS.md CLAUDE.md README.md polydev/references/architecture.md; do
  require_text "$file" ".claude/skills/polydev/scripts"
  reject_text "$file" ".claude-plugin"
  reject_text "$file" "marketplace"
  reject_text "$file" ".claude/plugins/cache/polydev-marketplace"
  reject_text "$file" "plugins/cache/polydev-marketplace"
  reject_text "$file" 'POLYDEV_SCRIPTS='
done

echo "script root cache guidance tests passed"

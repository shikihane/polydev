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

  grep -Fq "$text" "$ROOT_DIR/$file" || fail "$file missing required text: $text"
}

reject_text() {
  local file="$1"
  local text="$2"

  if grep -Fq "$text" "$ROOT_DIR/$file"; then
    fail "$file contains stale script path guidance: $text"
  fi
}

require_text AGENTS.md "every script call must hard-code the full absolute script path"
require_text CLAUDE.md "Every script call after the first resolution must hard-code the full absolute script path"
require_text README.md "Every script command must then use the full absolute script path"
require_text README.md 'D2 and D4 must resolve to `.claude/skills/polydev/scripts`'

for file in \
  skills/using-polydev/SKILL.md \
  skills/polydev/SKILL.md \
  skills/terminal-task-runner/SKILL.md \
  skills/polycron/SKILL.md \
  skills/writing-plans/SKILL.md \
  skills/agent-investigator/SKILL.md \
  skills/worktree-executor/SKILL.md
do
  require_text "$file" "/c/Users/<user>/.claude/skills/polydev/scripts"
  require_text "$file" "installed Claude skill directory"
  reject_text "$file" '"$POLYDEV_SCRIPTS/'
  reject_text "$file" '"$env:POLYDEV_SCRIPTS\'
  reject_text "$file" "SCRIPT_DIR="
  reject_text "$file" "/e/Heyang3/polydev/scripts"
  reject_text "$file" "/home/<user>/polydev/scripts"
  reject_text "$file" ".claudecode/skills/polydev/scripts"
  reject_text "$file" ".claude/plugins/cache/polydev-marketplace"
done

for file in README.md AGENTS.md CLAUDE.md skills/polydev/references/architecture.md; do
  require_text "$file" "/c/Users/<user>/.claude/skills/polydev/scripts"
  reject_text "$file" "/path/to/polydev/scripts"
  reject_text "$file" "POLYDEV_SCRIPTS="
  reject_text "$file" "SCRIPT_DIR="
  reject_text "$file" "/e/Heyang3/polydev/scripts"
  reject_text "$file" "/home/<user>/polydev/scripts"
  reject_text "$file" ".claudecode/skills/polydev/scripts"
  reject_text "$file" ".claude/plugins/cache/polydev-marketplace"
done

echo "absolute script path guidance tests passed"

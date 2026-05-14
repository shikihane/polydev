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

for file in \
  skills/using-polydev/SKILL.md \
  skills/polydev/SKILL.md \
  skills/polydev/references/architecture.md
do
  require_text "$file" "-CallerCwd"
  require_text "$file" 'Bash-launched PowerShell'
  require_text "$file" 'relative paths'
done

echo "windows Codex caller cwd guidance tests passed"

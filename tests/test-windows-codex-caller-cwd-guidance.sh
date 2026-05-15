#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "failed: $*" >&2
  exit 1
}

reject_text() {
  local file="$1"
  local text="$2"

  if grep -Fq -- "$text" "$ROOT_DIR/$file"; then
    fail "$file contains stale text: $text"
  fi
}

for file in \
  skills/polydev/references/using-polydev.md \
  skills/polydev/SKILL.md \
  skills/polydev/references/architecture.md
do
  reject_text "$file" "-CallerCwd"
  reject_text "$file" 'Bash-launched PowerShell adapters resolve relative paths'
done

echo "windows Codex caller cwd stale guidance tests passed"

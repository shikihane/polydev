#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_text() {
  local file="$1"
  local text="$2"

  grep -Fq -- "$text" "$ROOT_DIR/$file" || {
    echo "missing required smoke guidance in $file: $text" >&2
    exit 1
  }
}

require_text "polydev/SKILL.md" "Do not invent usernames or home directories"
require_text "polydev/SKILL.md" "Do not execute \`terminal-backend.sh\`"
require_text "polydev/SKILL.md" "Safe smoke test"
require_text "polydev/references/using-polydev.md" "Do not run internal implementation files"
require_text "polydev/references/architecture.md" "internal implementation files"

echo "polydev skill smoke guidance tests passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_files="$(mktemp)"
trap 'rm -f "$tmp_files"' EXIT

failures=0

find "$ROOT_DIR/polydev" -path '*/agents/openai.yaml' -print > "$tmp_files"

while IFS= read -r file; do
  if grep -nE 'default_prompt:.*\$[A-Za-z0-9_-]+' "$file"; then
    echo "default_prompt must not use explicit \$skill mentions: ${file#$ROOT_DIR/}" >&2
    failures=$((failures + 1))
  fi
done < "$tmp_files"

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "openai agent prompt tests passed"

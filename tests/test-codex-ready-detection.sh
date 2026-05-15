#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/polydev/scripts/terminal-backend.sh"

SCREEN_CONTENT=""

tb_is_session_alive() {
  [ "$1" = "42" ]
}

_tb_capture_pane() {
  printf '%s\n' "$SCREEN_CONTENT"
}

assert_codex_ready() {
  local name="$1"

  if ! tb_wait_for_codex 42 1; then
    echo "expected Codex to be ready: $name" >&2
    exit 1
  fi
}

SCREEN_CONTENT='C:\work\polydev> codex --dangerously-bypass-approvals-and-sandbox
╭──────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.130.0)                   │
│                                              │
│ model:       gpt-5.5 high   /model to change │
│ directory:   C:\work\polydev                 │
│ permissions: YOLO mode                       │
╰──────────────────────────────────────────────╯
› Find and fix a bug in @filename
  gpt-5.5 high · C:\work\polydev'
assert_codex_ready "banner and prompt marker visible"

SCREEN_CONTENT='│ Missing skill file: C:\Users\me\.codex\skills\a\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\b\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\c\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\d\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\a\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\b\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\c\SKILL.md │
│ Missing skill file: C:\Users\me\.codex\skills\d\SKILL.md │
›
  gpt-5.5 high · C:\work\polydev'
assert_codex_ready "prompt marker visible after banner scrolls out"

SCREEN_CONTENT='context left'
assert_codex_ready "legacy context marker visible"

SCREEN_CONTENT='C:\work\polydev> codex --dangerously-bypass-approvals-and-sandbox'
if tb_wait_for_codex 42 1 2>/dev/null; then
  echo "expected Codex not to be ready without a prompt marker" >&2
  exit 1
fi

echo "codex ready detection tests passed"

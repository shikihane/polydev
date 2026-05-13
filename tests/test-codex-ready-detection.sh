#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/terminal-backend.sh"

tb_is_session_alive() {
  [ "$1" = "42" ]
}

_tb_capture_pane() {
  cat <<'SCREEN'
E:\Heyang3\polydev> codex --dangerously-bypass-approvals-and-sandbox
╭──────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.130.0)                   │
│                                              │
│ model:       gpt-5.5 high   /model to change │
│ directory:   E:\Heyang3\polydev              │
│ permissions: YOLO mode                       │
╰──────────────────────────────────────────────╯

› Find and fix a bug in @filename

  gpt-5.5 high · E:\Heyang3\polydev
SCREEN
}

tb_wait_for_codex 42 1

echo "codex ready detection tests passed"

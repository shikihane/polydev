#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STATE_DIR="$TMP_DIR/state"
mkdir -p "$STATE_DIR"

cat > "$TMP_DIR/terminal-backend.sh" <<'STUB'
tb_get_backend() {
  echo "stub"
}

tb_create_worktree_session() {
  echo "pane-7"
}

tb_send_command() {
  printf '%s\n' "$2" > "$TEST_STATE_DIR/codex_cmd"
}

tb_wait_for_codex() {
  local attempts_file="$TEST_STATE_DIR/wait_attempts"
  local attempts=0
  if [ -f "$attempts_file" ]; then
    attempts="$(cat "$attempts_file")"
  fi
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" > "$attempts_file"

  if [ "$attempts" -eq 1 ]; then
    return 1
  fi
  return 0
}

tb_is_session_alive() {
  return 0
}

tb_send_multiline_text() {
  printf '%s\n' "$2" > "$TEST_STATE_DIR/prompt"
}
STUB

TEST_STATE_DIR="$STATE_DIR" SCRIPT_DIR="$TMP_DIR" \
  "$ROOT_DIR/polydev/scripts/spawn-codex.sh" recovery-test \
  --prompt "Investigate timeout recovery" \
  --cwd "$ROOT_DIR" > "$STATE_DIR/stdout"

if [ "$(cat "$STATE_DIR/wait_attempts")" != "2" ]; then
  echo "expected spawn-codex to retry Codex wait after an alive-session timeout" >&2
  exit 1
fi

if ! grep -q "Investigate timeout recovery" "$STATE_DIR/prompt"; then
  echo "expected prompt to be sent after timeout recovery" >&2
  exit 1
fi

if ! grep -q "event=codex_wait_timeout" "$STATE_DIR/stdout"; then
  echo "expected timeout recovery event in output" >&2
  exit 1
fi

if ! tail -n 1 "$STATE_DIR/stdout" | grep -q "pane-7"; then
  echo "expected pane id on final output line" >&2
  exit 1
fi

echo "spawn-codex timeout recovery tests passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_fake_bin() {
  local dir="$1"
  mkdir -p "$dir"

  cat > "$dir/python3" <<'SH'
#!/usr/bin/env bash
echo "python3 must not be used" >&2
exit 49
SH
  chmod +x "$dir/python3"

  cat > "$dir/python" <<'SH'
#!/usr/bin/env bash
echo "python must not be used" >&2
exit 49
SH
  chmod +x "$dir/python"

  cat > "$dir/wezterm" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "cli" ] && [ "${2:-}" = "list" ]; then
  cat <<'JSON'
[
  {
    "workspace": "demo",
    "tab_title": "feature-a [101]",
    "title": "pwsh.exe",
    "cwd": "E:/repo/.worktrees/feature-a",
    "pane_id": 101,
    "window_id": 7
  },
  {
    "workspace": "ag-demo",
    "tab_title": "research [102]",
    "title": "bash",
    "cwd": "E:/repo",
    "pane_id": 102,
    "window_id": 8
  }
]
JSON
  exit 0
fi

echo "unexpected wezterm call: $*" >&2
exit 2
SH
  chmod +x "$dir/wezterm"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$actual" != "$expected" ]; then
    echo "failed: $label" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    return 1
  fi
}

test_list_sessions_does_not_call_python() {
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  make_fake_bin "$tmp/bin"

  output="$(PATH="$tmp/bin:$PATH" "$ROOT_DIR/scripts/list-sessions.sh" demo)"

  assert_eq "session_id=wo:demo:feature-a [101].0,status=alive,cwd=E:/repo/.worktrees/feature-a,pane_id=101" "$output" "list-sessions"
}

test_get_pane_id_does_not_call_python() {
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  make_fake_bin "$tmp/bin"

  output="$(PATH="$tmp/bin:$PATH" "$ROOT_DIR/scripts/get-pane-id.sh" "wo:demo:feature-a.0")"

  assert_eq "101" "$output" "get-pane-id"
}

test_prune_dead_sessions_does_not_call_python() {
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  make_fake_bin "$tmp/bin"

  output="$(PATH="$tmp/bin:$PATH" "$ROOT_DIR/scripts/prune-dead-sessions.sh")"

  assert_eq "session_id=ag:ag-demo:research [102].0,status=alive,pane_id=102,cwd=E:/repo" "$output" "prune-dead-sessions"
}

test_terminal_backend_helpers_do_not_call_python() {
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  make_fake_bin "$tmp/bin"

  output="$(PATH="$tmp/bin:$PATH" bash -c 'source "$1"; _wezterm_get_session_info 101; tb_poll_sessions demo' _ "$ROOT_DIR/scripts/terminal-backend.sh")"

  assert_eq $'101|active|pwsh.exe|E:/repo/.worktrees/feature-a\n101|active' "$output" "terminal-backend helpers"
}

test_list_sessions_does_not_call_python
test_get_pane_id_does_not_call_python
test_prune_dead_sessions_does_not_call_python
test_terminal_backend_helpers_do_not_call_python
echo "no-python runtime tests passed"

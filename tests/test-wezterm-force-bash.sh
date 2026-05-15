#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/wezterm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WEZTERM_LOG"

if [ "${1:-}" = "cli" ] && [ "${2:-}" = "list" ]; then
  printf '[]\n'
  exit 0
fi

if [ "${1:-}" = "cli" ] && [ "${2:-}" = "spawn" ]; then
  printf '77\n'
  exit 0
fi

if [ "${1:-}" = "cli" ] && [ "${2:-}" = "set-tab-title" ]; then
  exit 0
fi

if [ "${1:-}" = "cli" ] && [ "${2:-}" = "send-text" ]; then
  exit 0
fi

echo "unexpected wezterm call: $*" >&2
exit 2
SH
chmod +x "$tmp/bin/wezterm"

PATH="$tmp/bin:$PATH" \
TB_BACKEND=wezterm \
POLYDEV_PANE_SHELL=bash \
WEZTERM_LOG="$tmp/wezterm.log" \
bash -c '
  source "$1"
  sleep() { :; }
  _wezterm_create_session "demo" "background" "/e/repo" >/dev/null
' _ "$ROOT_DIR/polydev/scripts/terminal-backend.sh"

if ! grep -Eq '^cli spawn .* -- .*bash(\.exe)?([[:space:]]|$)' "$tmp/wezterm.log"; then
  echo "expected wezterm spawn to force a bash program" >&2
  echo "wezterm calls:" >&2
  cat "$tmp/wezterm.log" >&2
  exit 1
fi

echo "wezterm force bash tests passed"

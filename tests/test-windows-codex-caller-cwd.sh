#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "skipping: pwsh not found"
  exit 0
fi

if [ ! -d /e ]; then
  echo "skipping: Git Bash /e drive path not available"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" /e/polydev-caller-cwd-test
printf 'test plan\n' > /e/polydev-caller-cwd-test/plan.md

cat > "$tmp/bin/wezterm" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "cli" ] && [ "${2:-}" = "list" ]; then
  echo '[]'
  exit 0
fi

echo "unexpected wezterm call: $*" >&2
exit 2
SH
chmod +x "$tmp/bin/wezterm"

cat > "$tmp/bin/codex" <<'SH'
#!/usr/bin/env bash
echo "codex stub should not be executed" >&2
exit 2
SH
chmod +x "$tmp/bin/codex"

investigation_output="$(
  PATH="$tmp/bin:$PATH" PWD=/e/polydev-caller-cwd-test pwsh -NoProfile -File "$ROOT_DIR/scripts/start-codex-investigation.ps1" smoke \
    -Prompt "Inspect repository only." \
    -Cwd . \
    -WhatIf
)"

if ! grep -Fq "cwd=E:\\polydev-caller-cwd-test" <<<"$investigation_output"; then
  echo "failed: -Cwd . did not resolve relative to caller PWD" >&2
  echo "$investigation_output" >&2
  exit 1
fi

if grep -Fq "cwd=C:\\Users" <<<"$investigation_output"; then
  echo "failed: -Cwd . resolved relative to PowerShell home" >&2
  echo "$investigation_output" >&2
  exit 1
fi

worktree_output="$(
  PATH="$tmp/bin:$PATH" PWD=/e/polydev-caller-cwd-test pwsh -NoProfile -File "$ROOT_DIR/scripts/start-codex-worktree.ps1" smoke codex-cwd .worktrees/codex-cwd plan.md \
    -WhatIf
)"

if ! grep -Fq "worktree=E:\\polydev-caller-cwd-test\\.worktrees\\codex-cwd" <<<"$worktree_output"; then
  echo "failed: worktree path did not resolve relative to caller PWD" >&2
  echo "$worktree_output" >&2
  exit 1
fi

if ! grep -Fq "git worktree add E:\\polydev-caller-cwd-test\\.worktrees\\codex-cwd" <<<"$worktree_output"; then
  echo "failed: worktree command did not use caller PWD" >&2
  echo "$worktree_output" >&2
  exit 1
fi

echo "windows Codex caller cwd tests passed"

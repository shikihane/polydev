#!/bin/bash
# on-session-start.sh - Hook called when Claude session starts
#
# Updates agent_status to 'active'

# Portable sed -i (works on GNU and BSD/macOS)
sed_inplace() {
  local expr="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Convert Windows path to Unix path for Git Bash
to_unix_path() {
  local path="$1"
  # E:\foo\bar -> /e/foo/bar
  if [[ "$path" =~ ^([A-Za-z]):\\ ]]; then
    local drive="${BASH_REMATCH[1]}"
    path="/${drive,,}${path:2}"
    path="${path//\\//}"
  fi
  echo "$path"
}

# 写入 scripts 路径到固定位置，供后续快速引用
PLUGIN_ROOT="$(to_unix_path "$CLAUDE_PLUGIN_ROOT")"
POLYDEV_HOME="$HOME/.polydev"
mkdir -p "$POLYDEV_HOME"
echo "${PLUGIN_ROOT}/scripts" > "$POLYDEV_HOME/scripts-path"

PROJECT_DIR="$(to_unix_path "$CLAUDE_PROJECT_DIR")"
TASK_FILE="$PROJECT_DIR/task.toon"

if [ ! -f "$TASK_FILE" ]; then
  exit 0
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sed_inplace "s/^agent_status: .*/agent_status: active/" "$TASK_FILE"
sed_inplace "s/^last_update: .*/last_update: $TIMESTAMP/" "$TASK_FILE"

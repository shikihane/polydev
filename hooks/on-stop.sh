#!/bin/bash
# on-stop.sh - Hook called when Claude session stops
#
# Updates agent_status to 'idle' if task is not completed or waiting for human

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

PROJECT_DIR="$(to_unix_path "$CLAUDE_PROJECT_DIR")"
TASK_FILE="$PROJECT_DIR/task.toon"

if [ ! -f "$TASK_FILE" ]; then
  exit 0
fi

# Read current overall_status
status=$(grep "^overall_status:" "$TASK_FILE" | cut -d' ' -f2)

# Only mark as idle if not in a terminal state
if [ "$status" != "completed" ] && [ "$status" != "hil" ] && [ "$status" != "blocked" ] && [ "$status" != "merged" ] && [ "$status" != "cleanup_pending" ]; then
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed_inplace "s/^agent_status: .*/agent_status: idle/" "$TASK_FILE"
  sed_inplace "s/^last_update: .*/last_update: $TIMESTAMP/" "$TASK_FILE"
fi

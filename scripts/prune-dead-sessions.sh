#!/bin/bash
# prune-dead-sessions.sh - Remove dead session mappings from wezterm map file
#
# Usage: prune-dead-sessions.sh
#
# This script checks all sessions in the map file and removes any that no longer exist.
# Useful for cleaning up after wezterm windows are closed directly (not via close-session.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

if [ "$TB_BACKEND" != "wezterm" ]; then
  echo "This script is only needed for wezterm backend."
  echo "Current backend: $TB_BACKEND"
  exit 0
fi

echo "Checking for dead sessions in map file..."
echo ""

# Read all session IDs from map
_wezterm_init_map
map_file_py="${WO_MAP_FILE_WIN:-$WO_MAP_FILE}"

dead_count=0
alive_count=0

# Get all session IDs using environment variable to avoid escaping issues
session_ids=$(MAP_FILE_PATH="$map_file_py" $TB_PYTHON -c "
import json
import os

map_file = os.environ.get('MAP_FILE_PATH', '')
with open(map_file, 'r') as f:
    data = json.load(f)
for sid in data.values():
    print(sid)
" 2>/dev/null)

if [ -z "$session_ids" ]; then
  echo "No sessions in map file."
  exit 0
fi

# Check each session
while IFS= read -r session_id; do
  [ -z "$session_id" ] && continue

  if tb_is_session_alive "$session_id"; then
    echo "  ✅ ALIVE: $session_id"
    ((alive_count++))
  else
    echo "  💀 DEAD:  $session_id (removed from map)"
    ((dead_count++))
  fi
done <<< "$session_ids"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary: $alive_count alive, $dead_count dead (cleaned up)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

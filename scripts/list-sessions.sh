#!/bin/bash
# list-sessions.sh - List all worktree-orchestrator sessions
#
# Usage: list-sessions.sh [workspace]
#
# Examples:
#   list-sessions.sh              # List all sessions
#   list-sessions.sh myproject    # List sessions in 'myproject' workspace

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

WORKSPACE_FILTER="$1"

echo "Backend: $TB_BACKEND"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

_list_tmux_sessions() {
  local filter="$1"
  local found=0

  # List all sessions with wo: prefix
  if ! _tmux list-sessions -F "#{session_name}" 2>/dev/null | while read -r session; do
    # Get all windows in this session
    _tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | while read -r window; do
      local session_id
      session_id=$(_build_session_id "$session" "$window" "0")

      # Apply workspace filter if specified
      if [ -n "$filter" ] && [ "$session" != "$filter" ]; then
        continue
      fi

      # Get pane info
      local info
      info=$(_tmux list-panes -t "$session:$window" -F "#{pane_current_command}|#{pane_current_path}" 2>/dev/null | head -n1)
      local cmd="${info%%|*}"
      local cwd="${info#*|}"

      printf "%-45s  %-10s  %s\n" "$session_id" "$cmd" "$cwd"
      found=1
    done
  done; then
    # No sessions found
    :
  fi

  if [ "$found" -eq 0 ]; then
    echo "(No sessions found)"
  fi
}

_list_wezterm_sessions() {
  local filter="$1"
  local found=0

  _wezterm_init_map

  # Use Windows path for Python on MSYS/MinGW
  local map_file_py="${WO_MAP_FILE_WIN:-$WO_MAP_FILE}"

  # Get all panes from wezterm
  local panes_json
  panes_json=$(wezterm cli list --format json 2>/dev/null) || panes_json="[]"

  # Process map file and check against live panes
  $TB_PYTHON -c "
import json
import sys

# Load mapping
try:
    with open(r'$map_file_py', 'r') as f:
        mapping = json.load(f)
except:
    mapping = {}

# Load live panes
try:
    panes = json.loads('''$panes_json''')
except:
    panes = []

# Build pane lookup
live_panes = {p['pane_id']: p for p in panes}

# Filter by workspace if specified
filter_ws = '$filter'

found = False
for pane_id_str, session_id in mapping.items():
    pane_id = int(pane_id_str)

    # Extract workspace from session_id (wo:workspace:window.pane)
    parts = session_id.split(':')
    if len(parts) >= 2:
        workspace = parts[1]
    else:
        workspace = ''

    # Apply filter
    if filter_ws and workspace != filter_ws:
        continue

    # Check if alive
    if pane_id in live_panes:
        p = live_panes[pane_id]
        status = 'alive'
        cwd = p.get('cwd', '')
        title = p.get('title', '')
        print(f'{session_id:<45}  {status:<10}  {cwd}')
        found = True
    else:
        print(f'{session_id:<45}  dead')
        found = True

if not found:
    print('(No sessions found)')
"
}

# Print header
printf "%-45s  %-10s  %s\n" "SESSION_ID" "STATUS" "CWD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$TB_BACKEND" in
  tmux)
    _list_tmux_sessions "$WORKSPACE_FILTER"
    ;;
  wezterm)
    _list_wezterm_sessions "$WORKSPACE_FILTER"
    ;;
esac

echo ""
echo "Commands:"
echo "  close-session.sh <session_id>   - Close a session"
echo "  focus-session.sh <session_id>   - Focus/activate a session"
echo "  send-command.sh <session_id> <cmd> - Send command to session"

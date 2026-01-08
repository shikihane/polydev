#!/bin/bash
# list-sessions.sh - List all polydev sessions
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

  # Get all panes from wezterm directly (no map file needed)
  local panes_json
  panes_json=$(wezterm cli list --format json 2>/dev/null) || panes_json="[]"

  # Process live panes and build session list
  FILTER="$filter" PANES_JSON="$panes_json" $TB_PYTHON -c "
import json
import os

filter_ws = os.environ.get('FILTER', '')
panes_json = os.environ.get('PANES_JSON', '[]')

try:
    panes = json.loads(panes_json)
except:
    panes = []

found = False
for p in panes:
    workspace = p.get('workspace', '')
    tab_title = p.get('tab_title', '')
    cwd = p.get('cwd', '')
    pane_id = p.get('pane_id', '')

    # Skip if no workspace or tab_title
    if not workspace or not tab_title:
        continue

    # Determine prefix based on workspace pattern
    if workspace.startswith('ag-'):
        prefix = 'ag'
    elif workspace.startswith('bg-'):
        prefix = 'bg'
    else:
        prefix = 'wo'

    # Apply workspace filter
    if filter_ws and workspace != filter_ws:
        continue

    session_id = f'{prefix}:{workspace}:{tab_title}.0'
    status = 'alive'
    print(f'{session_id:<45}  {status:<10}  {cwd}')
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
echo "  wo-send-command.sh <worktree-path> <cmd> - Send to worktree session"
echo "  send-to-session.sh <session_id> <cmd> - Send to any session"

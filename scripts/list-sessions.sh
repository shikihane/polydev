#!/bin/bash
# list-sessions.sh - List all polydev sessions
#
# Usage: list-sessions.sh [workspace]
#
# Output (TOON):
#   session_id=wo:workspace:branch.0,status=alive,cwd=/path/to/cwd,pane_id=123
#   session_id=bg:workspace:name.0,status=alive,cwd=/path/to/cwd,pane_id=124

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

WORKSPACE_FILTER="$1"

_list_tmux_sessions() {
  local filter="$1"
  local found=0

  if ! _tmux list-sessions -F "#{session_name}" 2>/dev/null | while read -r session; do
    _tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | while read -r window; do
      local session_id
      session_id=$(_build_session_id "$session" "$window" "0")

      if [ -n "$filter" ] && [ "$session" != "$filter" ]; then
        continue
      fi

      local info pane_info
      pane_info=$(_tmux list-panes -t "$session:$window" -F "#{pane_id}|#{pane_current_command}|#{pane_current_path}" 2>/dev/null | head -n1)
      local pane_id="${pane_info%%|*}"
      info="${pane_info#*|}"
      local cmd="${info%%|*}"
      local cwd="${info#*|}"

      echo "session_id=${session_id},status=alive,cwd=${cwd},pane_id=${pane_id}"
      found=1
    done
  done; then
    :
  fi
}

_list_wezterm_sessions() {
  local filter="$1"
  local panes_json
  panes_json=$(wezterm cli list --format json 2>/dev/null) || panes_json="[]"

  FILTER="$filter" PANES_JSON="$panes_json" $TB_PYTHON -c "
import json
import os

filter_ws = os.environ.get('FILTER', '')
panes_json = os.environ.get('PANES_JSON', '[]')

try:
    panes = json.loads(panes_json)
except:
    panes = []

for p in panes:
    workspace = p.get('workspace', '')
    tab_title = p.get('tab_title', '')
    cwd = p.get('cwd', '')
    pane_id = p.get('pane_id', '')

    if not workspace or not tab_title:
        continue

    if filter_ws and workspace != filter_ws:
        continue

    # Determine prefix
    if workspace.startswith('ag-'):
        prefix = 'ag'
    elif workspace.startswith('bg-'):
        prefix = 'bg'
    else:
        prefix = 'wo'

    session_id = f'{prefix}:{workspace}:{tab_title}.0'
    print(f'session_id={session_id},status=alive,cwd={cwd},pane_id={pane_id}')
"
}

output=""
case "$TB_BACKEND" in
  tmux)
    output=$(_list_tmux_sessions "$WORKSPACE_FILTER")
    ;;
  wezterm)
    output=$(_list_wezterm_sessions "$WORKSPACE_FILTER")
    ;;
esac

if [ -n "$output" ]; then
  echo "$output"
else
  echo "(No sessions found)" >&2
fi

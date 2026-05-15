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

  printf '%s' "$panes_json" | _wezterm_json_rows | awk -F '\t' -v filter="$filter" '
    $2 == "workspace" { workspace_by_index[$1] = $3 }
    $2 == "tab_title" { tab_by_index[$1] = $3 }
    $2 == "cwd" { cwd_by_index[$1] = $3 }
    $2 == "pane_id" { pane_by_index[$1] = $3 }
    END {
      for (i = 0; i <= 10000; i++) {
        workspace = workspace_by_index[i]
        tab_title = tab_by_index[i]
        cwd = cwd_by_index[i]
        pane_id = pane_by_index[i]

        if (workspace == "" || tab_title == "") {
          continue
        }

        if (filter != "" && workspace != filter) {
          continue
        }

        if (workspace ~ /^ag-/) {
          prefix = "ag"
        } else if (workspace ~ /^bg-/) {
          prefix = "bg"
        } else {
          prefix = "wo"
        }

        print "session_id=" prefix ":" workspace ":" tab_title ".0,status=alive,cwd=" cwd ",pane_id=" pane_id
      }
    }
  '
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
  echo "(No sessions found)"
fi

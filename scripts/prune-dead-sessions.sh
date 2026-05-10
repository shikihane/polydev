#!/bin/bash
# prune-dead-sessions.sh - Check and display all polydev sessions status
#
# Usage: prune-dead-sessions.sh
#
# Output (TOON):
#   session_id=ag:ag-polydev:research.0,status=alive,pane_id=1,cwd=/path
#   session_id=bg:bg-polydev:build.0,status=alive,pane_id=2,cwd=/path

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

if [ "$TB_BACKEND" != "wezterm" ]; then
  echo "[W] backend=$TB_BACKEND,msg=This script is only needed for wezterm"
  exit 0
fi

# Get all panes from wezterm
panes_json=$(wezterm cli list --format json 2>/dev/null) || panes_json="[]"

# Process and output TOON
printf '%s' "$panes_json" | _wezterm_json_rows | awk -F '\t' '
  $2 == "workspace" { workspace_by_index[$1] = $3 }
  $2 == "tab_title" { tab_by_index[$1] = $3 }
  $2 == "cwd" { cwd_by_index[$1] = $3 }
  $2 == "pane_id" { pane_by_index[$1] = $3 }
  END {
    count = 0
    for (i = 0; i <= 10000; i++) {
      workspace = workspace_by_index[i]
      tab_title = tab_by_index[i]
      cwd = cwd_by_index[i]
      pane_id = pane_by_index[i]

      if (workspace == "") {
        continue
      }

      if (workspace ~ /^ag-/) {
        prefix = "ag"
      } else if (workspace ~ /^bg-/) {
        prefix = "bg"
      } else if (workspace ~ /-parallel/ || workspace ~ /^wo-/) {
        prefix = "wo"
      } else {
        continue
      }

      count += 1
      print "session_id=" prefix ":" workspace ":" tab_title ".0,status=alive,pane_id=" pane_id ",cwd=" cwd
    }

    if (count == 0) {
      print "status=no sessions found"
    }
  }
'

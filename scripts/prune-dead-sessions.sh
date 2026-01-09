#!/bin/bash
# prune-dead-sessions.sh - Check and display all polydev sessions status
#
# Usage: prune-dead-sessions.sh
#
# Output (TOON):
#   session_id=ag:ag-polydev:research.0,status=alive,pane_id=1,cwd=/path
#   session_id=bg:bg-polydev:build.0,status=alive,pane_id=2,cwd=/path

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

if [ "$TB_BACKEND" != "wezterm" ]; then
  echo "[W] backend=$TB_BACKEND,msg=This script is only needed for wezterm"
  exit 0
fi

# Get all panes from wezterm
panes_json=$(wezterm cli list --format json 2>/dev/null) || panes_json="[]"

# Process and output TOON
PANES_JSON="$panes_json" $TB_PYTHON -c "
import json, os

panes_json = os.environ.get('PANES_JSON', '[]')

try:
    panes = json.loads(panes_json)
except:
    panes = []

count = 0
for p in panes:
    workspace = p.get('workspace', '')
    tab_title = p.get('tab_title', '')
    pane_id = str(p.get('pane_id', ''))
    cwd = p.get('cwd', '')

    if not workspace:
        continue

    # Determine prefix
    if workspace.startswith('ag-'):
        prefix = 'ag'
    elif workspace.startswith('bg-'):
        prefix = 'bg'
    elif '-parallel' in workspace or workspace.startswith('wo-'):
        prefix = 'wo'
    else:
        continue

    count += 1
    session_id = f'{prefix}:{workspace}:{tab_title}.0'
    print(f'session_id={session_id},status=alive,pane_id={pane_id},cwd={cwd}')

if count == 0:
    print('status=no sessions found')
"

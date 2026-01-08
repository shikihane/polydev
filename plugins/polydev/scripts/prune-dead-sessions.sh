#!/bin/bash
# prune-dead-sessions.sh - Check and display all polydev sessions status
#
# Usage: prune-dead-sessions.sh
#
# This script lists all wezterm sessions and their status.
# Since map files are no longer used, this script now only displays status.
# Use close-session.sh to manually close dead/stale sessions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/terminal-backend.sh"

if [ "$TB_BACKEND" != "wezterm" ]; then
  echo "This script is only needed for wezterm backend."
  echo "Current backend: $TB_BACKEND"
  exit 0
fi

echo "Checking polydev sessions..."
echo ""

# Get all panes from wezterm
panes_json=$(wezterm cli list --format json 2>/dev/null) || panes_json="[]"

# Process and display
PANES_JSON="$panes_json" $TB_PYTHON -c "
import json
import os

panes_json = os.environ.get('PANES_JSON', '[]')

try:
    panes = json.loads(panes_json)
except:
    panes = []

alive_count = 0
polydev_count = 0

for p in panes:
    workspace = p.get('workspace', '')
    tab_title = p.get('tab_title', '')
    pane_id = p.get('pane_id', '')
    cwd = p.get('cwd', '')

    # Skip if not a polydev session (no workspace or tab_title)
    if not workspace:
        continue

    # Determine prefix based on workspace pattern
    if workspace.startswith('ag-'):
        prefix = 'ag'
    elif workspace.startswith('bg-'):
        prefix = 'bg'
    elif '-parallel' in workspace or workspace.startswith('wo-'):
        prefix = 'wo'
    else:
        # Not a polydev session
        continue

    polydev_count += 1
    session_id = f'{prefix}:{workspace}:{tab_title}.0'
    print(f'  ✅ ALIVE: {session_id}')
    print(f'           pane_id={pane_id} cwd={cwd}')
    alive_count += 1

if polydev_count == 0:
    print('(No polydev sessions found)')
else:
    print('')
    print('━' * 50)
    print(f'Summary: {alive_count} alive polydev sessions')
    print('━' * 50)
    print('')
    print('To close a session:')
    print('  close-session.sh <session_id>')
"

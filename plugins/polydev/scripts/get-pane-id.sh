#!/bin/bash
# get-pane-id.sh - Get terminal pane identifier from session_id
#
# Cross-platform: works with both tmux and wezterm backends.
# For wezterm: returns numeric pane_id with robust lookup.
# For tmux: returns target string (session:window.pane).
#
# Wezterm lookup strategy (handles tab_title changes by Claude):
#   1. Exact match: workspace + tab_title
#   2. Fallback: workspace only (if single pane)
#   3. Fallback: partial match on tab_title
#
# Usage: get-pane-id.sh <session_id>
#
# Returns: pane identifier (exit 0) or error (exit 1)
#
# Examples:
#   get-pane-id.sh wo:myproject:feature-auth.0
#   get-pane-id.sh ag:ag-polydev:research.0
#   get-pane-id.sh bg:bg-polydev:build.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect backend
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*|Windows*)
    BACKEND="wezterm"
    ;;
  *)
    BACKEND="tmux"
    ;;
esac

# Detect Python (for wezterm)
detect_python() {
  if command -v python3 &>/dev/null; then
    echo "python3"
  elif command -v python &>/dev/null; then
    echo "python"
  else
    echo ""
  fi
}

SESSION_ID="$1"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: get-pane-id.sh <session_id>" >&2
  echo "Example: get-pane-id.sh wo:myproject:feature-auth.0" >&2
  exit 1
fi

# Parse session_id: remove prefix and extract components
# Input: wo:workspace:window.pane or bg:workspace:name.pane or ag:workspace:name.pane
# Output: sets WORKSPACE, WINDOW, PANE variables
parse_session_id() {
  local id="$1"
  # Remove prefix (wo:, bg:, ag:)
  id="${id#wo:}"
  id="${id#bg:}"
  id="${id#ag:}"
  # Extract components
  WORKSPACE="${id%%:*}"
  local rest="${id#*:}"
  WINDOW="${rest%.*}"
  PANE="${rest##*.}"
}

parse_session_id "$SESSION_ID"

# =============================================================================
# tmux backend
# =============================================================================
get_tmux_pane() {
  local target="$WORKSPACE:$WINDOW.$PANE"
  # Verify pane exists
  if tmux -S /tmp/polydev.sock list-panes -t "$target" &>/dev/null; then
    echo "$target"
    return 0
  fi
  return 1
}

# =============================================================================
# wezterm backend
# =============================================================================
get_wezterm_pane() {
  local PYTHON
  PYTHON=$(detect_python)
  if [ -z "$PYTHON" ]; then
    echo "Error: Python not found" >&2
    return 1
  fi

  # Query wezterm
  local panes_json
  panes_json=$(wezterm cli list --format json 2>/dev/null) || {
    echo "Error: Failed to query wezterm" >&2
    return 1
  }

  # Find pane_id using Python
  local result
  result=$(WORKSPACE="$WORKSPACE" TAB_TITLE="$WINDOW" PANES_JSON="$panes_json" $PYTHON -c "
import json, os, sys

workspace = os.environ.get('WORKSPACE', '')
tab_title = os.environ.get('TAB_TITLE', '')
panes_json = os.environ.get('PANES_JSON', '[]')

try:
    data = json.loads(panes_json)
except:
    sys.exit(1)

# Filter by workspace
ws_panes = [p for p in data if p.get('workspace') == workspace]
if not ws_panes:
    sys.exit(1)

# Strategy 1: exact match
for p in ws_panes:
    if p.get('tab_title') == tab_title:
        print(p['pane_id'])
        sys.exit(0)

# Strategy 2: single pane in workspace
if len(ws_panes) == 1:
    print(ws_panes[0]['pane_id'])
    sys.exit(0)

# Strategy 3: partial match
for p in ws_panes:
    t = p.get('tab_title', '')
    if tab_title in t or t in tab_title:
        print(p['pane_id'])
        sys.exit(0)

sys.exit(1)
" 2>/dev/null)

  if [ -n "$result" ]; then
    echo "$result"
    return 0
  fi
  return 1
}

# =============================================================================
# Main
# =============================================================================
case "$BACKEND" in
  tmux)
    if get_tmux_pane; then
      exit 0
    fi
    ;;
  wezterm)
    if get_wezterm_pane; then
      exit 0
    fi
    ;;
esac

echo "Error: Pane not found for session: $SESSION_ID" >&2
echo "  Backend: $BACKEND" >&2
echo "  Workspace: $WORKSPACE" >&2
echo "  Window/Title: $WINDOW" >&2
exit 1

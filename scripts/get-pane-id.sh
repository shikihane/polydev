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

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

# Detect backend
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*|Windows*)
    BACKEND="wezterm"
    ;;
  *)
    BACKEND="tmux"
    ;;
esac

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
  # Query wezterm
  local panes_json
  panes_json=$(wezterm cli list --format json 2>/dev/null) || {
    echo "Error: Failed to query wezterm" >&2
    return 1
  }

  # Find pane_id using the vendored shell JSON parser.
  local result
  result=$(printf '%s' "$panes_json" | _wezterm_json_rows | awk -F '\t' -v ws="$WORKSPACE" -v title="$WINDOW" '
    $2 == "workspace" { workspace_by_index[$1] = $3 }
    $2 == "tab_title" { tab_by_index[$1] = $3 }
    $2 == "pane_id" { pane_by_index[$1] = $3 }
    END {
      count = 0
      for (i = 0; i <= 10000; i++) {
        if (workspace_by_index[i] == ws) {
          count += 1
          indexes[count] = i
        }
      }

      if (count == 0) {
        exit 1
      }

      for (n = 1; n <= count; n++) {
        i = indexes[n]
        if (tab_by_index[i] == title) {
          print pane_by_index[i]
          exit 0
        }
      }

      if (count == 1) {
        print pane_by_index[indexes[1]]
        exit 0
      }

      for (n = 1; n <= count; n++) {
        i = indexes[n]
        tab = tab_by_index[i]
        if (index(tab, title) > 0 || index(title, tab) > 0) {
          print pane_by_index[i]
          exit 0
        }
      }

      exit 1
    }
  ' 2>/dev/null)

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

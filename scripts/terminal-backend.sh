#!/bin/bash
# terminal-backend.sh - Terminal multiplexer abstraction layer
#
# Provides unified API for both tmux (Linux/macOS) and wezterm (Windows)
#
# Session ID Format: wo:session:window.pane
#   wo:myproject-parallel:feature-auth.0
#   │  │                  │            │
#   │  │                  │            └─ pane index
#   │  │                  └─ window name (branch)
#   │  └─ session name (workspace)
#   └─ prefix for worktree-orchestrator

set -e

# =============================================================================
# Configuration
# =============================================================================

TB_SOCKET="/tmp/worktree-orchestrator.sock"
WO_MAP_FILE="/tmp/worktree-orchestrator-map.json"
TB_BACKEND=""

# =============================================================================
# Initialization
# =============================================================================

_tb_init() {
  if [ -n "$TB_BACKEND" ]; then
    return 0
  fi

  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*)
      TB_BACKEND="wezterm"
      ;;
    Linux|Darwin|*)
      TB_BACKEND="tmux"
      ;;
  esac

  export TB_BACKEND
}

# Auto-initialize on source
_tb_init

# =============================================================================
# Session ID Utilities
# =============================================================================

# Parse session_id into components
# Usage: _parse_session_id "wo:workspace:window.0"
# Sets: SESSION, WINDOW, PANE, TARGET
_parse_session_id() {
  local id="$1"
  id="${id#wo:}"                    # Remove prefix
  SESSION="${id%%:*}"               # Extract session name
  local rest="${id#*:}"
  WINDOW="${rest%.*}"               # Extract window name
  PANE="${rest##*.}"                # Extract pane index
  TARGET="$SESSION:$WINDOW.$PANE"   # tmux target format
}

# Build session_id from components
# Usage: _build_session_id "workspace" "window" "0"
_build_session_id() {
  echo "wo:$1:$2.$3"
}

# =============================================================================
# tmux Backend Implementation
# =============================================================================

_tmux() {
  tmux -S "$TB_SOCKET" "$@"
}

_tmux_create_session() {
  local workspace="$1"
  local branch="$2"
  local cwd="$3"
  local pane_id

  if ! _tmux has-session -t "$workspace" 2>/dev/null; then
    # Create new session with first window
    pane_id=$(_tmux new-session -d -s "$workspace" \
      -n "$branch" -c "$cwd" -P -F "#{pane_id}" bash)
  else
    # Session exists, create new window
    pane_id=$(_tmux new-window -t "$workspace:" \
      -n "$branch" -c "$cwd" -P -F "#{pane_id}" bash)
  fi

  _build_session_id "$workspace" "$branch" "0"
}

_tmux_is_alive() {
  local session_id="$1"
  _parse_session_id "$session_id"
  _tmux list-panes -t "$TARGET" &>/dev/null
}

_tmux_send_command() {
  local session_id="$1"
  local command="$2"
  local execute="${3:-true}"

  _parse_session_id "$session_id"

  _tmux send-keys -t "$TARGET" -l "$command"
  if [ "$execute" = "true" ]; then
    _tmux send-keys -t "$TARGET" C-m
  fi
}

_tmux_focus_session() {
  local session_id="$1"
  _parse_session_id "$session_id"

  # Switch to session and select pane
  _tmux switch-client -t "$SESSION" 2>/dev/null || true
  _tmux select-window -t "$SESSION:$WINDOW" 2>/dev/null || true
  _tmux select-pane -t "$TARGET" 2>/dev/null || true
}

_tmux_cleanup_session() {
  local session_id="$1"
  _parse_session_id "$session_id"

  _tmux kill-pane -t "$TARGET" 2>/dev/null || true

  # If no more windows in session, kill session
  if ! _tmux list-windows -t "$SESSION" &>/dev/null; then
    _tmux kill-session -t "$SESSION" 2>/dev/null || true
  fi
}

_tmux_get_session_info() {
  local session_id="$1"
  _parse_session_id "$session_id"

  local info
  info=$(_tmux list-panes -t "$TARGET" -F "#{pane_id}|#{pane_current_command}|#{window_name}|#{pane_current_path}" 2>/dev/null | head -n1)

  if [ -n "$info" ]; then
    echo "$info"
  else
    echo "|dead||"
  fi
}

_tmux_poll_sessions() {
  local workspace="$1"

  _tmux list-windows -t "$workspace" -F "#{window_name}" 2>/dev/null | while read -r window; do
    local session_id
    session_id=$(_build_session_id "$workspace" "$window" "0")
    local status="active"

    # Check if pane is still running
    if ! _tmux list-panes -t "$workspace:$window" &>/dev/null; then
      status="dead"
    fi

    echo "$session_id|$status"
  done
}

# =============================================================================
# wezterm Backend Implementation
# =============================================================================

_wezterm_init_map() {
  if [ ! -f "$WO_MAP_FILE" ]; then
    echo "{}" > "$WO_MAP_FILE"
  fi
}

_wezterm_save_mapping() {
  local pane_id="$1"
  local session_id="$2"

  _wezterm_init_map

  local tmp_file="${WO_MAP_FILE}.tmp.$$"
  python3 -c "
import json
import sys

with open('$WO_MAP_FILE', 'r') as f:
    data = json.load(f)

data['$pane_id'] = '$session_id'

with open('$tmp_file', 'w') as f:
    json.dump(data, f, indent=2)
" && mv "$tmp_file" "$WO_MAP_FILE"
}

_wezterm_get_pane_id() {
  local session_id="$1"

  _wezterm_init_map

  python3 -c "
import json

with open('$WO_MAP_FILE', 'r') as f:
    data = json.load(f)

for pane_id, sid in data.items():
    if sid == '$session_id':
        print(pane_id)
        break
"
}

_wezterm_remove_mapping() {
  local session_id="$1"

  _wezterm_init_map

  local tmp_file="${WO_MAP_FILE}.tmp.$$"
  python3 -c "
import json

with open('$WO_MAP_FILE', 'r') as f:
    data = json.load(f)

data = {k: v for k, v in data.items() if v != '$session_id'}

with open('$tmp_file', 'w') as f:
    json.dump(data, f, indent=2)
" && mv "$tmp_file" "$WO_MAP_FILE"
}

_wezterm_create_session() {
  local workspace="$1"
  local branch="$2"
  local cwd="$3"
  local pane_id
  local existing_window

  # Find existing window in workspace
  existing_window=$(wezterm cli list --format json 2>/dev/null | \
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    w = [x['window_id'] for x in d if x.get('workspace') == '$workspace']
    print(w[0] if w else '')
except:
    print('')
" 2>/dev/null) || existing_window=""

  if [ -n "$existing_window" ]; then
    pane_id=$(wezterm cli spawn --window-id "$existing_window" --cwd "$cwd" -- bash)
  else
    pane_id=$(wezterm cli spawn --new-window --workspace "$workspace" --cwd "$cwd" -- bash)
  fi

  wezterm cli set-tab-title --pane-id "$pane_id" "$branch"

  local session_id
  session_id=$(_build_session_id "$workspace" "$branch" "0")
  _wezterm_save_mapping "$pane_id" "$session_id"

  echo "$session_id"
}

_wezterm_is_alive() {
  local session_id="$1"
  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -z "$pane_id" ]; then
    return 1
  fi

  wezterm cli list --format json 2>/dev/null | grep -q "\"pane_id\": *$pane_id"
}

_wezterm_send_command() {
  local session_id="$1"
  local command="$2"
  local execute="${3:-true}"

  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -z "$pane_id" ]; then
    return 1
  fi

  if [ "$execute" = "true" ]; then
    printf '%s\r' "$command" | wezterm cli send-text --pane-id "$pane_id" --no-paste
  else
    printf '%s' "$command" | wezterm cli send-text --pane-id "$pane_id" --no-paste
  fi
}

_wezterm_focus_session() {
  local session_id="$1"
  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -n "$pane_id" ]; then
    wezterm cli activate-pane --pane-id "$pane_id"
  fi
}

_wezterm_cleanup_session() {
  local session_id="$1"
  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -n "$pane_id" ]; then
    wezterm cli kill-pane --pane-id "$pane_id" 2>/dev/null || true
  fi

  _wezterm_remove_mapping "$session_id"
}

_wezterm_get_session_info() {
  local session_id="$1"
  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -z "$pane_id" ]; then
    echo "|dead||"
    return
  fi

  local info
  info=$(wezterm cli list --format json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for p in d:
        if p.get('pane_id') == $pane_id:
            print(f\"{p.get('pane_id', '')}|active|{p.get('title', '')}|{p.get('cwd', '')}\")
            break
    else:
        print('|dead||')
except:
    print('|dead||')
" 2>/dev/null) || info="|dead||"

  echo "$info"
}

_wezterm_poll_sessions() {
  local workspace="$1"

  _wezterm_init_map

  python3 -c "
import json

with open('$WO_MAP_FILE', 'r') as f:
    data = json.load(f)

for pane_id, session_id in data.items():
    if session_id.startswith('wo:$workspace:'):
        print(f'{session_id}|active')
"
}

# =============================================================================
# Public API - Backend Agnostic
# =============================================================================

# Create a new worktree session
# Usage: tb_create_worktree_session <workspace> <branch> <worktree_path> [plan_file]
# Returns: session_id
tb_create_worktree_session() {
  local workspace="$1"
  local branch="$2"
  local worktree_path="$3"
  local plan_file="$4"  # Currently unused, reserved for future

  case "$TB_BACKEND" in
    tmux)
      _tmux_create_session "$workspace" "$branch" "$worktree_path"
      ;;
    wezterm)
      _wezterm_create_session "$workspace" "$branch" "$worktree_path"
      ;;
  esac
}

# Check if session is alive
# Usage: tb_is_session_alive <session_id>
# Returns: 0 if alive, 1 if dead
tb_is_session_alive() {
  local session_id="$1"

  case "$TB_BACKEND" in
    tmux)
      _tmux_is_alive "$session_id"
      ;;
    wezterm)
      _wezterm_is_alive "$session_id"
      ;;
  esac
}

# Send command to session
# Usage: tb_send_command <session_id> <command> [execute=true]
tb_send_command() {
  local session_id="$1"
  local command="$2"
  local execute="${3:-true}"

  case "$TB_BACKEND" in
    tmux)
      _tmux_send_command "$session_id" "$command" "$execute"
      ;;
    wezterm)
      _wezterm_send_command "$session_id" "$command" "$execute"
      ;;
  esac
}

# Focus/activate session
# Usage: tb_focus_session <session_id>
tb_focus_session() {
  local session_id="$1"

  case "$TB_BACKEND" in
    tmux)
      _tmux_focus_session "$session_id"
      ;;
    wezterm)
      _wezterm_focus_session "$session_id"
      ;;
  esac
}

# Cleanup session
# Usage: tb_cleanup_session <session_id>
tb_cleanup_session() {
  local session_id="$1"

  case "$TB_BACKEND" in
    tmux)
      _tmux_cleanup_session "$session_id"
      ;;
    wezterm)
      _wezterm_cleanup_session "$session_id"
      ;;
  esac
}

# Get session info
# Usage: tb_get_session_info <session_id>
# Returns: pane_id|status|window_name|cwd
tb_get_session_info() {
  local session_id="$1"

  case "$TB_BACKEND" in
    tmux)
      _tmux_get_session_info "$session_id"
      ;;
    wezterm)
      _wezterm_get_session_info "$session_id"
      ;;
  esac
}

# Poll all sessions in workspace
# Usage: tb_poll_sessions <workspace>
# Returns: session_id|status (one per line)
tb_poll_sessions() {
  local workspace="$1"

  case "$TB_BACKEND" in
    tmux)
      _tmux_poll_sessions "$workspace"
      ;;
    wezterm)
      _wezterm_poll_sessions "$workspace"
      ;;
  esac
}

# Get current backend
# Usage: tb_get_backend
tb_get_backend() {
  echo "$TB_BACKEND"
}

# Get tmux socket path (for manual debugging)
# Usage: tb_get_socket
tb_get_socket() {
  if [ "$TB_BACKEND" = "tmux" ]; then
    echo "$TB_SOCKET"
  else
    echo ""
  fi
}

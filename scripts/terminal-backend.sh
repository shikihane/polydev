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
TB_BACKEND=""
TB_PYTHON=""

# Map file paths - need both Unix (for bash) and Windows (for Python) formats
# On MSYS/MinGW, /tmp is virtual but Python sees different path
WO_MAP_FILE="/tmp/worktree-orchestrator-map.json"

# Convert to Windows-compatible path for Python using cygpath
# cygpath -m gives mixed format (forward slashes) which Python handles well
if command -v cygpath &>/dev/null; then
  WO_MAP_FILE_WIN="$(cygpath -m /tmp)/worktree-orchestrator-map.json"
else
  # Fallback for non-MSYS environments
  WO_MAP_FILE_WIN="$WO_MAP_FILE"
fi

# Detect Python command (python3 or python)
_tb_detect_python() {
  if [ -n "$TB_PYTHON" ]; then
    return 0
  fi

  if command -v python3 &>/dev/null; then
    TB_PYTHON="python3"
  elif command -v python &>/dev/null; then
    # Verify it's Python 3
    if python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
      TB_PYTHON="python"
    else
      echo "Error: Python 3 is required but not found" >&2
      return 1
    fi
  else
    echo "Error: Python is required but not found" >&2
    return 1
  fi

  export TB_PYTHON
}

# =============================================================================
# Initialization
# =============================================================================

_tb_init() {
  if [ -n "$TB_BACKEND" ]; then
    return 0
  fi

  # Detect Python first (needed for wezterm backend)
  _tb_detect_python

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

_tmux_send_multiline_text() {
  local session_id="$1"
  local text="$2"
  local execute="${3:-true}"

  _parse_session_id "$session_id"

  # For multiline text, send without -l flag so newlines are processed
  # But we need to escape the text to avoid shell interpretation
  # Best approach: use a temp file
  local tmp_file="/tmp/tmux_multiline.$$"
  printf '%s' "$text" > "$tmp_file"

  # Use load-buffer and paste-buffer for safe multiline sending
  _tmux load-buffer "$tmp_file"
  _tmux paste-buffer -t "$TARGET"
  rm -f "$tmp_file"

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

  # Use Windows path for Python on MSYS/MinGW
  local map_file_py="${WO_MAP_FILE_WIN:-$WO_MAP_FILE}"
  local tmp_file="${WO_MAP_FILE}.tmp.$$"
  local tmp_file_py="${map_file_py}.tmp.$$"

  $TB_PYTHON -c "
import json
import sys

with open(r'$map_file_py', 'r') as f:
    data = json.load(f)

data['$pane_id'] = '$session_id'

with open(r'$tmp_file_py', 'w') as f:
    json.dump(data, f, indent=2)
" && mv "$tmp_file" "$WO_MAP_FILE"
}

_wezterm_get_pane_id() {
  local session_id="$1"

  _wezterm_init_map

  # Use Windows path for Python on MSYS/MinGW
  local map_file_py="${WO_MAP_FILE_WIN:-$WO_MAP_FILE}"

  $TB_PYTHON -c "
import json

with open(r'$map_file_py', 'r') as f:
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

  # Use Windows path for Python on MSYS/MinGW
  local map_file_py="${WO_MAP_FILE_WIN:-$WO_MAP_FILE}"
  local tmp_file="${WO_MAP_FILE}.tmp.$$"
  local tmp_file_py="${map_file_py}.tmp.$$"

  $TB_PYTHON -c "
import json

with open(r'$map_file_py', 'r') as f:
    data = json.load(f)

data = {k: v for k, v in data.items() if v != '$session_id'}

with open(r'$tmp_file_py', 'w') as f:
    json.dump(data, f, indent=2)
" && mv "$tmp_file" "$WO_MAP_FILE"
}

_wezterm_create_session() {
  local workspace="$1"
  local branch="$2"
  local cwd="$3"
  local pane_id
  local existing_window

  # Normalize path for Windows: remove trailing slashes (wezterm bug)
  # See: https://github.com/wezterm/wezterm/discussions/4703
  cwd="${cwd%/}"
  cwd="${cwd%\\}"

  # Find existing window in workspace
  existing_window=$(wezterm cli list --format json 2>/dev/null | \
    $TB_PYTHON -c "
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

  # Workaround for Windows Git Bash: --cwd may not work correctly
  # Git Bash often starts in MSYS installation dir or %USERPROFILE%
  # See: https://github.com/git-for-windows/git/issues/794
  # Explicitly cd to the target directory after bash starts
  sleep 0.3  # Wait for bash prompt to initialize
  printf 'cd "%s" && clear\r' "$cwd" | wezterm cli send-text --pane-id "$pane_id" --no-paste

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

_wezterm_send_multiline_text() {
  local session_id="$1"
  local text="$2"
  local execute="${3:-true}"

  local pane_id
  pane_id=$(_wezterm_get_pane_id "$session_id")

  if [ -z "$pane_id" ]; then
    return 1
  fi

  # For multiline text, send the entire text with newlines preserved
  # wezterm cli send-text handles this correctly
  # IMPORTANT: Send text first, then send Enter separately
  # Using \r at end of multiline text doesn't trigger execution properly
  printf '%s' "$text" | wezterm cli send-text --pane-id "$pane_id" --no-paste

  if [ "$execute" = "true" ]; then
    # Send Enter key separately to ensure execution
    # Use 'echo ""' without --no-paste as it works more reliably with Claude Code
    # See: https://github.com/wezterm/wezterm/discussions/xxxx
    sleep 0.3
    echo "" | wezterm cli send-text --pane-id "$pane_id"
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
  info=$(wezterm cli list --format json 2>/dev/null | $TB_PYTHON -c "
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

  # Use Windows path for Python on MSYS/MinGW
  local map_file_py="${WO_MAP_FILE_WIN:-$WO_MAP_FILE}"

  $TB_PYTHON -c "
import json

with open(r'$map_file_py', 'r') as f:
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

# Send multiline text (e.g., from a file)
# Usage: tb_send_multiline_text <session_id> <text> [execute=true]
# This properly handles newlines and sends the entire text as one message
tb_send_multiline_text() {
  local session_id="$1"
  local text="$2"
  local execute="${3:-true}"

  case "$TB_BACKEND" in
    tmux)
      _tmux_send_multiline_text "$session_id" "$text" "$execute"
      ;;
    wezterm)
      _wezterm_send_multiline_text "$session_id" "$text" "$execute"
      ;;
  esac
}

# Wait for Claude Code to start and be ready for input
# Usage: tb_wait_for_claude <session_id> [timeout_seconds=30]
# Returns: 0 if ready, 1 if timeout
tb_wait_for_claude() {
  local session_id="$1"
  local timeout="${2:-30}"
  local elapsed=0
  local interval=2

  echo "⏳ Waiting for Claude to start (timeout: ${timeout}s)..."

  while [ $elapsed -lt $timeout ]; do
    # Simple heuristic: wait for session to be responsive
    # Check if session is still alive
    if ! tb_is_session_alive "$session_id"; then
      echo "❌ Session died during startup"
      return 1
    fi

    sleep $interval
    elapsed=$((elapsed + interval))

    # Print progress
    echo -n "."
  done

  echo ""
  echo "⚠️  Timeout reached. Claude might still be starting..."
  echo "   Proceeding anyway..."
  return 0
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

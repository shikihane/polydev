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

TB_SOCKET="/tmp/polydev.sock"
TB_BACKEND=""
TB_PYTHON=""

# No external map file needed
# - tmux: native session:window.pane naming
# - wezterm: lookup via workspace + tab_title

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
  # Alias for scripts that use $PYTHON (polycron-*, get-pane-id.sh)
  PYTHON="$TB_PYTHON"
  export PYTHON
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
# Supports prefixes: wo:, bg:, ag: (all treated the same internally)
# Sets: SESSION, WINDOW, PANE, TARGET
_parse_session_id() {
  local id="$1"
  # Remove any known prefix (wo:, bg:, ag:)
  id="${id#wo:}"
  id="${id#bg:}"
  id="${id#ag:}"
  SESSION="${id%%:*}"               # Extract session name (workspace)
  local rest="${id#*:}"
  WINDOW="${rest%.*}"               # Extract window name (tab_title)
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
    # Wait for Claude Code to process the pasted text before submitting
    sleep 2
    # Claude Code multiline mode: C-j submits, C-m just inserts newline
    _tmux send-keys -t "$TARGET" C-j
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

# Create session, return numeric pane_id
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

  # Find existing window in workspace (use temp file to avoid pipe issues)
  local tmpfile
  tmpfile="$(mktemp)"
  wezterm cli list --format json > "$tmpfile" 2>/dev/null || true

  existing_window=$(WORKSPACE="$workspace" TMPFILE="$tmpfile" $TB_PYTHON -c "
import sys, json, os
try:
    workspace = os.environ.get('WORKSPACE', '')
    tmpfile = os.environ.get('TMPFILE', '')
    with open(tmpfile, 'r') as f:
        d = json.load(f)
    w = [x['window_id'] for x in d if x.get('workspace') == workspace]
    print(w[0] if w else '')
except:
    print('')
" 2>/dev/null) || existing_window=""
  rm -f "$tmpfile"

  if [ -n "$existing_window" ]; then
    pane_id=$(wezterm cli spawn --window-id "$existing_window" --cwd "$cwd")
  else
    pane_id=$(wezterm cli spawn --new-window --workspace "$workspace" --cwd "$cwd")
  fi

  # Set tab_title - includes pane_id for easy identification
  wezterm cli set-tab-title --pane-id "$pane_id" "${branch} [${pane_id}]"

  # Workaround for Windows Git Bash: --cwd may not work correctly
  # Git Bash often starts in MSYS installation dir or %USERPROFILE%
  # See: https://github.com/git-for-windows/git/issues/794
  # Explicitly cd to the target directory after bash starts
  sleep 2  # Wait for bash prompt to initialize
  printf 'cd "%s"' "$cwd" | wezterm cli send-text --no-paste --pane-id "$pane_id"
  sleep 2
  printf '\r' | wezterm cli send-text --no-paste --pane-id "$pane_id"
  sleep 2
  printf 'clear' | wezterm cli send-text --no-paste --pane-id "$pane_id"
  sleep 2
  printf '\r' | wezterm cli send-text --no-paste --pane-id "$pane_id"

  # Return the numeric pane_id (not session_id)
  echo "$pane_id"
}

_wezterm_is_alive() {
  local pane_id="$1"

  # Try to get pane info - if succeeds, pane is alive
  wezterm cli get-text --pane-id "$pane_id" --start-line 0 --end-line 0 &>/dev/null
}

_wezterm_send_command() {
  local pane_id="$1"
  local command="$2"
  local execute="${3:-true}"

  # Send text first (--no-paste: avoid bracketed paste swallowing control chars)
  printf '%s' "$command" | wezterm cli send-text --no-paste --pane-id "$pane_id"

  if [ "$execute" = "true" ]; then
    sleep 2
    printf '\r' | wezterm cli send-text --no-paste --pane-id "$pane_id"
  fi
}

_wezterm_send_multiline_text() {
  local pane_id="$1"
  local text="$2"
  local execute="${3:-true}"

  # Send text first, then send Enter separately after delay
  # --no-paste: avoid bracketed paste swallowing control chars
  printf '%s' "$text" | wezterm cli send-text --no-paste --pane-id "$pane_id"

  if [ "$execute" = "true" ]; then
    sleep 2
    printf '\r' | wezterm cli send-text --no-paste --pane-id "$pane_id"
  fi
}

_wezterm_focus_session() {
  local pane_id="$1"

  if [ -n "$pane_id" ]; then
    wezterm cli activate-pane --pane-id "$pane_id"
  fi
}

_wezterm_cleanup_session() {
  local pane_id="$1"

  if [ -n "$pane_id" ]; then
    wezterm cli kill-pane --pane-id "$pane_id" 2>/dev/null || true
  fi
  # No map file to clean up - wezterm metadata is managed by wezterm itself
}

_wezterm_get_session_info() {
  local pane_id="$1"

  if [ -z "$pane_id" ]; then
    echo "|dead||"
    return
  fi

  local info
  info=$(wezterm cli list --format json 2>/dev/null | $TB_PYTHON -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for p in d:
        if p.get("pane_id") == int('"$pane_id"'):
            print("{}|active|{}|{}".format(p.get("pane_id", ""), p.get("title", ""), p.get("cwd", "")))
            break
    else:
        print("|dead||")
except:
    print("|dead||")
' 2>/dev/null) || info="|dead||"

  echo "$info"
}

_wezterm_poll_sessions() {
  local workspace="$1"

  # Query wezterm directly - no map file needed
  local tmpfile
  tmpfile="$(mktemp)"
  wezterm cli list --format json > "$tmpfile" 2>/dev/null || true

  WORKSPACE="$workspace" TMPFILE="$tmpfile" $TB_PYTHON -c '
import json, os

workspace = os.environ.get("WORKSPACE", "")
tmpfile = os.environ.get("TMPFILE", "")

with open(tmpfile, "r") as f:
    data = json.load(f)

for p in data:
    ws = p.get("workspace", "")
    tab_title = p.get("tab_title", "")
    pane_id = p.get("pane_id", "")
    if ws == workspace and tab_title and pane_id:
        print(str(pane_id) + "|active")
' 2>/dev/null

  rm -f "$tmpfile"
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
  local pane_id="$1"

  case "$TB_BACKEND" in
    tmux)
      _tmux_get_session_info "$pane_id"
      ;;
    wezterm)
      _wezterm_get_session_info "$pane_id"
      ;;
  esac
}

# Poll all sessions in workspace
# Usage: tb_poll_sessions <workspace>
# Returns: pane_id|status (one per line)
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

# Wait for Claude to start accepting input
# Usage: tb_wait_for_claude <pane_id> [timeout_seconds=5] [initial_content]
# Returns: 0 if ready or timeout (proceed anyway), 1 if session died
# Strategy: detect terminal content change from initial state
tb_wait_for_claude() {
  local pane_id="$1"
  local timeout="${2:-5}"
  local initial_content="${3:-}"
  local start_time=$(date +%s)

  # If no initial content provided, just do a brief wait
  if [ -z "$initial_content" ]; then
    sleep 1
    return 0
  fi

  while true; do
    local now=$(date +%s)
    local elapsed=$((now - start_time))

    if [ $elapsed -ge $timeout ]; then
      return 0  # Timeout - proceed anyway
    fi

    if ! tb_is_session_alive "$pane_id"; then
      echo "❌ Session died" >&2
      return 1
    fi

    # Get current content
    local current_content
    current_content=$(_tb_capture_pane "$pane_id")

    # If content changed, Claude has started
    if [ "$current_content" != "$initial_content" ]; then
      return 0
    fi

    sleep 0.2
  done
}

# Helper: capture pane content with proper session_id parsing
_tb_capture_pane() {
  local pane_id="$1"
  case "$TB_BACKEND" in
    wezterm)
      wezterm cli get-text --pane-id "$pane_id" 2>/dev/null
      ;;
    tmux)
      _parse_session_id "$pane_id"
      _tmux capture-pane -t "$TARGET" -p 2>/dev/null
      ;;
  esac
}

# Wait for Codex CLI to be ready
# Usage: tb_wait_for_codex <pane_id> [timeout_seconds=15]
# Returns: 0 if ready, 1 if timeout or session died
# Ready marker: "context left" in status line
tb_wait_for_codex() {
  local pane_id="$1"
  local timeout="${2:-15}"
  local start_time=$(date +%s)

  while true; do
    local now=$(date +%s)
    local elapsed=$((now - start_time))

    if [ $elapsed -ge $timeout ]; then
      echo "[W] Codex wait timeout after ${timeout}s" >&2
      return 1
    fi

    if ! tb_is_session_alive "$pane_id"; then
      echo "[E] Session died while waiting for Codex" >&2
      return 1
    fi

    local current_content
    current_content=$(_tb_capture_pane "$pane_id")

    # Check for Codex ready marker
    if echo "$current_content" | grep -q "context left"; then
      return 0
    fi

    sleep 0.5
  done
}

# Wait for Gemini CLI to be ready
# Usage: tb_wait_for_gemini <pane_id> [timeout_seconds=15]
# Returns: 0 if ready, 1 if timeout or session died
# Ready marker: "Type your message" in input box
tb_wait_for_gemini() {
  local pane_id="$1"
  local timeout="${2:-15}"
  local start_time=$(date +%s)

  while true; do
    local now=$(date +%s)
    local elapsed=$((now - start_time))

    if [ $elapsed -ge $timeout ]; then
      echo "[W] Gemini wait timeout after ${timeout}s" >&2
      return 1
    fi

    if ! tb_is_session_alive "$pane_id"; then
      echo "[E] Session died while waiting for Gemini" >&2
      return 1
    fi

    local current_content
    current_content=$(_tb_capture_pane "$pane_id")

    # Check for Gemini ready marker
    if echo "$current_content" | grep -q "Type your message"; then
      return 0
    fi

    sleep 0.5
  done
}

# Capture terminal content for change detection
# Usage: tb_capture_content <pane_id>
tb_capture_content() {
  local pane_id="$1"
  case "$TB_BACKEND" in
    wezterm)
      wezterm cli get-text --pane-id "$pane_id" 2>/dev/null | head -5
      ;;
    tmux)
      _parse_session_id "$pane_id"
      _tmux capture-pane -t "$TARGET" -p 2>/dev/null | head -5
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

# tb_peek - 等待后截屏
# 用法: tb_peek <pane_id> <delay_seconds> [lines]
tb_peek() {
  local pane_id="$1"
  local delay="$2"
  local lines="${3:-50}"
  if [ "$delay" -gt 0 ] 2>/dev/null; then
    sleep "$delay"
  fi
  echo "---PEEK---"
  "$SCRIPT_DIR/capture-screen.sh" --pane-id "$pane_id" --lines "$lines"
}

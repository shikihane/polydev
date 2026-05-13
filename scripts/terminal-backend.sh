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

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# =============================================================================
# Configuration
# =============================================================================

TB_SOCKET="/tmp/polydev.sock"
TB_BACKEND=""

# No external map file needed
# - tmux: native session:window.pane naming
# - wezterm: lookup via workspace + tab_title

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

_tmux_target_for_id() {
  local id="$1"
  case "$id" in
    %*)
      echo "$id"
      ;;
    *)
      _parse_session_id "$id"
      echo "$TARGET"
      ;;
  esac
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
  local id="$1"
  local target
  target=$(_tmux_target_for_id "$id")
  _tmux list-panes -t "$target" &>/dev/null
}

_tmux_send_command() {
  local id="$1"
  local command="$2"
  local execute="${3:-true}"

  local target
  target=$(_tmux_target_for_id "$id")

  _tmux send-keys -t "$target" -l "$command"
  if [ "$execute" = "true" ]; then
    _tmux send-keys -t "$target" C-m
  fi
}

_tmux_send_multiline_text() {
  local id="$1"
  local text="$2"
  local execute="${3:-true}"

  local target
  target=$(_tmux_target_for_id "$id")

  # For multiline text, send without -l flag so newlines are processed
  # But we need to escape the text to avoid shell interpretation
  # Best approach: use a temp file
  local tmp_file="/tmp/tmux_multiline.$$"
  printf '%s' "$text" > "$tmp_file"

  # Use load-buffer and paste-buffer for safe multiline sending
  _tmux load-buffer "$tmp_file"
  _tmux paste-buffer -t "$target"
  rm -f "$tmp_file"

  if [ "$execute" = "true" ]; then
    # Wait for Claude Code to process the pasted text before submitting
    sleep 2
    # Claude Code multiline mode: C-j submits, C-m just inserts newline
    _tmux send-keys -t "$target" C-j
  fi
}

_tmux_focus_session() {
  local id="$1"
  local target
  target=$(_tmux_target_for_id "$id")

  # Switch to session and select pane
  if [[ "$id" == %* ]]; then
    _tmux select-pane -t "$target" 2>/dev/null || true
  else
    _tmux switch-client -t "$SESSION" 2>/dev/null || true
    _tmux select-window -t "$SESSION:$WINDOW" 2>/dev/null || true
    _tmux select-pane -t "$target" 2>/dev/null || true
  fi
}

_tmux_cleanup_session() {
  local id="$1"
  local target
  target=$(_tmux_target_for_id "$id")

  _tmux kill-pane -t "$target" 2>/dev/null || true

  # If no more windows in session, kill session
  if [[ "$id" != %* ]]; then
    if ! _tmux list-windows -t "$SESSION" &>/dev/null; then
      _tmux kill-session -t "$SESSION" 2>/dev/null || true
    fi
  fi
}

_tmux_get_session_info() {
  local id="$1"
  local target
  target=$(_tmux_target_for_id "$id")

  local info
  info=$(_tmux list-panes -t "$target" -F "#{pane_id}|#{pane_current_command}|#{window_name}|#{pane_current_path}" 2>/dev/null | head -n1)

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

_json_unquote() {
  local value="$1"
  value="${value%$'\r'}"
  if [ "${value#\"}" != "$value" ] && [ "${value%\"}" != "$value" ]; then
    value="${value#\"}"
    value="${value%\"}"
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
    value="${value//\\\//\/}"
  fi
  printf '%s' "$value"
}

_wezterm_json_rows() {
  sh "$SCRIPT_DIR/lib/jq.sh" -l 2>/dev/null | while IFS=$'\t' read -r path value; do
    case "$path" in
      \[[0-9]*,\"workspace\"\]|\[[0-9]*,\"tab_title\"\]|\[[0-9]*,\"title\"\]|\[[0-9]*,\"cwd\"\]|\[[0-9]*,\"pane_id\"\]|\[[0-9]*,\"window_id\"\])
        local index field
        index="${path#\[}"
        index="${index%%,*}"
        field="${path#*,\"}"
        field="${field%\"\]}"
        printf '%s\t%s\t%s\n' "$index" "$field" "$(_json_unquote "$value")"
        ;;
    esac
  done
}

_wezterm_first_window_id_for_workspace() {
  local workspace="$1"
  awk -F '\t' -v ws="$workspace" '
    $2 == "workspace" { workspace_by_index[$1] = $3 }
    $2 == "window_id" { window_by_index[$1] = $3 }
    END {
      for (i = 0; i <= 10000; i++) {
        if (workspace_by_index[i] == ws && window_by_index[i] != "") {
          print window_by_index[i]
          exit
        }
      }
    }
  '
}

_wezterm_title_for_pane_id() {
  local pane_id="$1"
  awk -F '\t' -v pid="$pane_id" '
    $2 == "pane_id" { pane_by_index[$1] = $3 }
    $2 == "title" { title_by_index[$1] = $3 }
    END {
      for (i = 0; i <= 10000; i++) {
        if (pane_by_index[i] == pid) {
          print title_by_index[i]
          exit
        }
      }
    }
  '
}

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

  existing_window=$(_wezterm_json_rows < "$tmpfile" | _wezterm_first_window_id_for_workspace "$workspace") || existing_window=""
  rm -f "$tmpfile"

  if [ -n "$existing_window" ]; then
    pane_id=$(wezterm cli spawn --window-id "$existing_window" --cwd "$cwd" | tr -d '\r')
  else
    pane_id=$(wezterm cli spawn --new-window --workspace "$workspace" --cwd "$cwd" | tr -d '\r')
  fi

  # Set tab_title - includes pane_id for easy identification
  wezterm cli set-tab-title --pane-id "$pane_id" "${branch} [${pane_id}]"

  # Detect shell type: 3-layer detection
  # Layer 1: POLYDEV_PANE_SHELL env override (user can force a shell type)
  # Layer 2: wezterm cli list title (process name, reliable on default configs)
  # Layer 3: Platform fallback (Windows→powershell, others→bash)
  sleep 2  # Wait for shell to initialize
  local shell_type=""
  if [ -n "${POLYDEV_PANE_SHELL:-}" ]; then
    shell_type="$POLYDEV_PANE_SHELL"
  else
    local pane_title
    pane_title=$(wezterm cli list --format json 2>/dev/null | \
      _wezterm_json_rows | _wezterm_title_for_pane_id "$pane_id") || pane_title=""
    if echo "$pane_title" | grep -qiE 'pwsh|powershell'; then
      shell_type="powershell"
    elif echo "$pane_title" | grep -qiE 'cmd\.exe'; then
      shell_type="cmd"
    elif echo "$pane_title" | grep -qiE 'bash|MINGW|MSYS|zsh'; then
      shell_type="bash"
    else
      # Platform fallback: WezTerm defaults to PowerShell on Windows
      case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) shell_type="powershell" ;;
        *) shell_type="bash" ;;
      esac
    fi
  fi
  # Store shell type in temp file keyed by pane_id
  local shell_type_dir="${TMPDIR:-/tmp}/polydev-shell-types"
  mkdir -p "$shell_type_dir"
  echo "$shell_type" > "$shell_type_dir/$pane_id"

  # Explicitly cd to the target directory after shell starts
  # Git Bash paths (/c/...) are invalid in PowerShell, convert with cygpath
  local cd_path="$cwd"
  local clear_cmd="clear"
  if [ "$shell_type" = "powershell" ] || [ "$shell_type" = "cmd" ]; then
    cd_path=$(cygpath -w "$cwd" 2>/dev/null || echo "$cwd")
    clear_cmd="cls"
  fi
  # Send cd command (separate text + Enter calls; positional arg for \r)
  printf 'cd "%s"' "$cd_path" | wezterm cli send-text --no-paste --pane-id "$pane_id"
  sleep 2
  wezterm cli send-text --no-paste --pane-id "$pane_id" -- $'\r'
  sleep 2
  printf '%s' "$clear_cmd" | wezterm cli send-text --no-paste --pane-id "$pane_id"
  sleep 2
  wezterm cli send-text --no-paste --pane-id "$pane_id" -- $'\r'

  # Return the numeric pane_id (not session_id)
  echo "$pane_id"
}

_wezterm_is_alive() {
  local pane_id="$1"

  # Try to get pane info - if succeeds, pane is alive
  wezterm cli get-text --pane-id "$pane_id" --start-line 0 --end-line 0 &>/dev/null
}

# ─── Claude Binary Detection ───

# Find the claude CLI binary, searching PATH and common install locations.
# Usage: tb_find_claude_bin
# Sets: CLAUDE_BIN (exported)
# Returns: 0 if found, 1 if not found
tb_find_claude_bin() {
  CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
  if [ -z "$CLAUDE_BIN" ]; then
    for candidate in "$HOME/.nvm/versions/node"/*/bin/claude "$HOME/.local/bin/claude" /usr/local/bin/claude; do
      if [ -x "$candidate" ]; then
        CLAUDE_BIN="$candidate"
        break
      fi
    done
  fi
  if [ -z "$CLAUDE_BIN" ]; then
    return 1
  fi
  export CLAUDE_BIN
  return 0
}

# ─── Shell Detection (cross-shell support) ───

# Get the detected shell type for a WezTerm pane
# Returns: "powershell" or "bash"
_wezterm_get_pane_shell() {
  local pane_id="$1"
  # Strip \r that wezterm cli may return on Windows
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')
  local shell_type_file="${TMPDIR:-/tmp}/polydev-shell-types/$pane_id"
  if [ -f "$shell_type_file" ]; then
    cat "$shell_type_file"
  else
    # Platform-aware fallback: WezTerm defaults to PowerShell on Windows
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) echo "powershell" ;;
      *) echo "bash" ;;
    esac
  fi
}

# Launch Claude CLI in a pane, adapting syntax to the pane's shell (bash or PowerShell)
# Usage: tb_launch_claude <pane_id> <claude_bin> <model> [extra_args...]
tb_launch_claude() {
  local pane_id="$1"
  local claude_bin="$2"
  local model="$3"
  shift 3
  local extra_args="$*"

  # Strip \r that wezterm cli may return on Windows
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')

  # Build the launch command based on shell type
  local cmd
  if [ "$TB_BACKEND" = "wezterm" ]; then
    local shell_type
    shell_type=$(_wezterm_get_pane_shell "$pane_id")
    if [ "$shell_type" = "powershell" ]; then
      # PowerShell: Remove-Item instead of unset, basename only (Git Bash paths invalid)
      local ps_bin
      ps_bin=$(basename "$claude_bin" .cmd)
      cmd="Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue; $ps_bin --dangerously-skip-permissions --model $model $extra_args"
    fi
  fi

  # Default: bash syntax (used by tmux and wezterm-bash)
  if [ -z "$cmd" ]; then
    cmd="unset CLAUDECODE && $claude_bin --dangerously-skip-permissions --model $model $extra_args"
  fi

  tb_send_command "$pane_id" "$cmd" "true"
}

_wezterm_send_command() {
  local pane_id="$1"
  local command="$2"
  local execute="${3:-true}"

  # Strip \r that wezterm cli may return on Windows
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')

  # IMPORTANT: text and Enter MUST be sent as separate send-text calls.
  # Combined (printf '%s\r') does NOT work for TUI apps like Claude Code:
  # the TUI processes the combined buffer as one chunk and ignores the trailing \r.
  printf '%s' "$command" | wezterm cli send-text --no-paste --pane-id "$pane_id"

  if [ "$execute" = "true" ]; then
    # ⛔ sleep >= 2s: target app needs time to process text before Enter
    sleep 2
    # Send \r as positional argument (not via stdin pipe).
    # Piping single-byte \r is unreliable on Windows Git Bash — the byte can
    # be swallowed by MSYS pipe text-mode translation or wezterm's stdin handling.
    wezterm cli send-text --no-paste --pane-id "$pane_id" -- $'\r'
  fi
}

# Send multiline text to a pane and submit.
# For WezTerm, multiline paste + submit is unreliable: neither \r (Enter) nor
# \n (Ctrl+J) via send-text reliably triggers submit in Claude Code multiline mode.
# Workaround: write text to a temp file, then send a short single-line command
# instructing Claude to read and follow the file.
_wezterm_send_multiline_text() {
  local pane_id="$1"
  local text="$2"
  local execute="${3:-true}"

  # Strip \r that wezterm cli may return on Windows
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')

  # If text has no newlines, just use single-line send
  if ! printf '%s' "$text" | grep -q $'\n'; then
    _wezterm_send_command "$pane_id" "$text" "$execute"
    return $?
  fi

  # Multiline: write to temp file, send short command to read it
  local prompt_file="${TMPDIR:-/tmp}/polydev-prompt-${pane_id}.md"
  printf '%s' "$text" > "$prompt_file"

  if [ "$execute" = "true" ]; then
    # Convert to Windows path (Git Bash paths invalid in Claude Code's Read tool)
    local win_path
    win_path=$(cygpath -w "$prompt_file" 2>/dev/null || echo "$prompt_file")
    _wezterm_send_command "$pane_id" "Read ${win_path} and follow all instructions in it" "true"
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
  info=$(wezterm cli list --format json 2>/dev/null | _wezterm_json_rows | awk -F '\t' -v pid="$pane_id" '
    $2 == "pane_id" { pane_by_index[$1] = $3 }
    $2 == "title" { title_by_index[$1] = $3 }
    $2 == "cwd" { cwd_by_index[$1] = $3 }
    END {
      for (i = 0; i <= 10000; i++) {
        if (pane_by_index[i] == pid) {
          print pane_by_index[i] "|active|" title_by_index[i] "|" cwd_by_index[i]
          found = 1
          break
        }
      }
      if (!found) {
        print "|dead||"
      }
    }
  ') || info="|dead||"

  echo "$info"
}

_wezterm_poll_sessions() {
  local workspace="$1"

  # Query wezterm directly - no map file needed
  local tmpfile
  tmpfile="$(mktemp)"
  wezterm cli list --format json > "$tmpfile" 2>/dev/null || true

  _wezterm_json_rows < "$tmpfile" | awk -F '\t' -v ws="$workspace" '
    $2 == "workspace" { workspace_by_index[$1] = $3 }
    $2 == "tab_title" { tab_by_index[$1] = $3 }
    $2 == "pane_id" { pane_by_index[$1] = $3 }
    END {
      for (i = 0; i <= 10000; i++) {
        if (workspace_by_index[i] == ws && tab_by_index[i] != "" && pane_by_index[i] != "") {
          print pane_by_index[i] "|active"
        }
      }
    }
  '

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
      local target
      target=$(_tmux_target_for_id "$pane_id")
      _tmux capture-pane -t "$target" -p 2>/dev/null
      ;;
  esac
}

# Wait for a CLI tool to be ready by polling for a marker string in the pane.
# Usage: _tb_wait_for_marker <tool_name> <pane_id> <marker_pattern> [timeout_seconds=15]
# Returns: 0 if marker found, 1 if timeout or session died
_tb_wait_for_marker() {
  local tool_name="$1"
  local pane_id="$2"
  local marker="$3"
  local timeout="${4:-15}"
  local start_time=$(date +%s)

  while true; do
    local now=$(date +%s)
    local elapsed=$((now - start_time))

    if [ $elapsed -ge $timeout ]; then
      echo "[W] $tool_name wait timeout after ${timeout}s" >&2
      return 1
    fi

    if ! tb_is_session_alive "$pane_id"; then
      echo "[E] Session died while waiting for $tool_name" >&2
      return 1
    fi

    local current_content
    current_content=$(_tb_capture_pane "$pane_id")

    if echo "$current_content" | grep -q "$marker"; then
      return 0
    fi

    sleep 0.5
  done
}

# Wait for Codex CLI to be ready by polling for known startup prompts.
# Usage: tb_wait_for_codex <pane_id> [timeout_seconds=15]
# Returns: 0 if ready, 1 if timeout or session died
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

    if echo "$current_content" | grep -q "context left"; then
      return 0
    fi

    if echo "$current_content" | grep -q "OpenAI Codex" && echo "$current_content" | grep -q "›"; then
      return 0
    fi

    sleep 0.5
  done
}

# Wait for Gemini CLI to be ready
# Usage: tb_wait_for_gemini <pane_id> [timeout_seconds=15]
# Returns: 0 if ready, 1 if timeout or session died
tb_wait_for_gemini() {
  _tb_wait_for_marker "Gemini" "$1" "Type your message" "${2:-15}"
}

# Capture terminal content for change detection (first 5 lines)
# Usage: tb_capture_content <pane_id>
tb_capture_content() {
  _tb_capture_pane "$1" | head -5
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

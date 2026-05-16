#!/bin/bash
# terminal-backend.sh - Small terminal backend API for tmux and WezTerm.

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TB_SOCKET="/tmp/polydev.sock"
TB_BACKEND="${TB_BACKEND:-}"

_tb_quote_shell_arg() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

_tb_init() {
  [ -n "$TB_BACKEND" ] && return 0
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*) TB_BACKEND="wezterm" ;;
    *) TB_BACKEND="tmux" ;;
  esac
  export TB_BACKEND
}

_tb_init

_parse_session_id() {
  local id="$1"
  id="${id#wo:}"
  id="${id#bg:}"
  id="${id#ag:}"
  SESSION="${id%%:*}"
  local rest="${id#*:}"
  WINDOW="${rest%.*}"
  PANE="${rest##*.}"
  TARGET="$SESSION:$WINDOW.$PANE"
}

_tmux_target_for_id() {
  local id="$1"
  case "$id" in
    %*) echo "$id" ;;
    *) _parse_session_id "$id"; echo "$TARGET" ;;
  esac
}

_build_session_id() {
  echo "wo:$1:$2.$3"
}

_tmux() {
  tmux -S "$TB_SOCKET" "$@"
}

_tmux_create_session() {
  local workspace="$1" branch="$2" cwd="$3" pane_id
  if ! _tmux has-session -t "$workspace" 2>/dev/null; then
    pane_id=$(_tmux new-session -d -s "$workspace" -n "$branch" -c "$cwd" -P -F "#{pane_id}" bash)
  else
    pane_id=$(_tmux new-window -t "$workspace:" -n "$branch" -c "$cwd" -P -F "#{pane_id}" bash)
  fi
  _build_session_id "$workspace" "$branch" "0"
}

_tmux_is_alive() {
  _tmux list-panes -t "$(_tmux_target_for_id "$1")" &>/dev/null
}

_tmux_send_command() {
  local id="$1" command="$2" execute="${3:-true}" target
  target="$(_tmux_target_for_id "$id")"
  _tmux send-keys -t "$target" -l "$command"
  [ "$execute" = "true" ] && _tmux send-keys -t "$target" C-m
}

_tmux_send_multiline_text() {
  local id="$1" text="$2" execute="${3:-true}" target tmp_file
  target="$(_tmux_target_for_id "$id")"
  tmp_file="/tmp/tmux_multiline.$$"
  printf '%s' "$text" > "$tmp_file"
  _tmux load-buffer "$tmp_file"
  _tmux paste-buffer -t "$target"
  rm -f "$tmp_file"
  if [ "$execute" = "true" ]; then
    sleep 2
    _tmux send-keys -t "$target" C-j
  fi
}

_tmux_focus_session() {
  local id="$1" target
  target="$(_tmux_target_for_id "$id")"
  if [[ "$id" == %* ]]; then
    _tmux select-pane -t "$target" 2>/dev/null || true
  else
    _tmux switch-client -t "$SESSION" 2>/dev/null || true
    _tmux select-window -t "$SESSION:$WINDOW" 2>/dev/null || true
    _tmux select-pane -t "$target" 2>/dev/null || true
  fi
}

_tmux_cleanup_session() {
  local id="$1" target
  target="$(_tmux_target_for_id "$id")"
  _tmux kill-pane -t "$target" 2>/dev/null || true
  if [[ "$id" != %* ]] && ! _tmux list-windows -t "$SESSION" &>/dev/null; then
    _tmux kill-session -t "$SESSION" 2>/dev/null || true
  fi
}

_tmux_get_session_info() {
  local info
  info=$(_tmux list-panes -t "$(_tmux_target_for_id "$1")" -F "#{pane_id}|#{pane_current_command}|#{window_name}|#{pane_current_path}" 2>/dev/null | head -n1)
  [ -n "$info" ] && echo "$info" || echo "|dead||"
}

_tmux_poll_sessions() {
  local workspace="$1" window session_id status
  _tmux list-windows -t "$workspace" -F "#{window_name}" 2>/dev/null | while read -r window; do
    session_id="$(_build_session_id "$workspace" "$window" "0")"
    status="active"
    _tmux list-panes -t "$workspace:$window" &>/dev/null || status="dead"
    echo "$session_id|$status"
  done
}

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
    $2 == "workspace" { w[$1] = $3 }
    $2 == "window_id" { id[$1] = $3 }
    END { for (i = 0; i <= 10000; i++) if (w[i] == ws && id[i] != "") { print id[i]; exit } }
  '
}

_wezterm_bash_program_args() {
  local bash_bin
  WEZTERM_BASH_PROGRAM_ARGS=()
  bash_bin="$(command -v bash 2>/dev/null || true)"
  [ -z "$bash_bin" ] && echo "[E] error=bash binary not found" >&2 && return 1
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*)
      command -v cygpath >/dev/null 2>&1 && bash_bin="$(cygpath -w "$bash_bin")"
      WEZTERM_BASH_PROGRAM_ARGS=("$bash_bin" "--noprofile" "--norc" "-i")
      ;;
    *) WEZTERM_BASH_PROGRAM_ARGS=("$bash_bin") ;;
  esac
}

_wezterm_create_session() {
  local workspace="$1" branch="$2" cwd="$3" pane_id existing_window tmpfile
  local -a bash_program_args
  cwd="${cwd%/}"
  cwd="${cwd%\\}"
  _wezterm_bash_program_args
  bash_program_args=("${WEZTERM_BASH_PROGRAM_ARGS[@]}")
  tmpfile="$(mktemp)"
  wezterm cli list --format json > "$tmpfile" 2>/dev/null || true
  existing_window=$(_wezterm_json_rows < "$tmpfile" | _wezterm_first_window_id_for_workspace "$workspace") || existing_window=""
  rm -f "$tmpfile"
  if [ -n "$existing_window" ]; then
    pane_id=$(wezterm cli spawn --window-id "$existing_window" -- "${bash_program_args[@]}" | tr -d '\r')
  else
    pane_id=$(wezterm cli spawn --new-window --workspace "$workspace" -- "${bash_program_args[@]}" | tr -d '\r')
  fi
  wezterm cli set-tab-title --pane-id "$pane_id" "${branch} [${pane_id}]"
  sleep "${POLYDEV_WEZTERM_SHELL_INIT_DELAY:-0.5}"
  mkdir -p "${TMPDIR:-/tmp}/polydev-shell-types"
  echo "bash" > "${TMPDIR:-/tmp}/polydev-shell-types/$pane_id"
  mkdir -p "${TMPDIR:-/tmp}/polydev-pane-cwds"
  printf '%s\n' "$cwd" > "${TMPDIR:-/tmp}/polydev-pane-cwds/$pane_id"
  echo "$pane_id"
}

_wezterm_is_alive() {
  wezterm cli get-text --pane-id "$1" --start-line 0 --end-line 0 &>/dev/null
}

_wezterm_get_pane_shell() {
  local pane_id shell_type_file
  pane_id=$(printf '%s' "$1" | tr -d '\r')
  shell_type_file="${TMPDIR:-/tmp}/polydev-shell-types/$pane_id"
  [ -f "$shell_type_file" ] && cat "$shell_type_file" || echo "unsupported"
}

_wezterm_send_command() {
  local pane_id="$1" command="$2" execute="${3:-true}" enter_delay="${4:-${POLYDEV_WEZTERM_ENTER_DELAY:-2}}"
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')
  printf '%s' "$command" | wezterm cli send-text --no-paste --pane-id "$pane_id"
  if [ "$execute" = "true" ]; then
    sleep "$enter_delay"
    wezterm cli send-text --no-paste --pane-id "$pane_id" -- $'\r'
  fi
}

_wezterm_prepare_cwd() {
  local pane_id="$1" cwd_file cwd marker content
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')
  cwd_file="${TMPDIR:-/tmp}/polydev-pane-cwds/$pane_id"
  [ -f "$cwd_file" ] || return 0
  cwd="$(cat "$cwd_file")"
  [ -n "$cwd" ] || return 0
  marker="__POLYDEV_CWD_READY_${pane_id}_$(date +%s%N)__"
  _wezterm_send_command "$pane_id" "export PATH=\"/usr/bin:/bin:\$PATH\"; cd $(_tb_quote_shell_arg "$cwd") && printf '%s\n' '$marker'" "true" "${POLYDEV_CWD_ENTER_DELAY:-0.2}"
  local start_time
  start_time=$(date +%s)
  while true; do
    if [ $(($(date +%s) - start_time)) -ge "${POLYDEV_CWD_READY_TIMEOUT:-5}" ]; then
      echo "[E] error=Pane did not enter cwd within timeout: $cwd" >&2
      return 1
    fi
    content="$(_tb_capture_pane "$pane_id")"
    if printf '%s' "$content" | grep -Fq "$marker"; then
      rm -f "$cwd_file"
      return 0
    fi
    sleep 0.1
  done
}

_wezterm_send_multiline_text() {
  local pane_id="$1" text="$2" execute="${3:-true}" prompt_file
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')
  if ! printf '%s' "$text" | grep -q $'\n'; then
    _wezterm_send_command "$pane_id" "$text" "$execute"
    return $?
  fi
  prompt_file="${TMPDIR:-/tmp}/polydev-prompt-${pane_id}.md"
  printf '%s' "$text" > "$prompt_file"
  [ "$execute" = "true" ] && _wezterm_send_command "$pane_id" "Read ${prompt_file} and follow all instructions in it" "true"
}

_wezterm_focus_session() {
  [ -n "$1" ] && wezterm cli activate-pane --pane-id "$1"
}

_wezterm_cleanup_session() {
  [ -n "$1" ] && wezterm cli kill-pane --pane-id "$1" 2>/dev/null || true
}

_wezterm_get_session_info() {
  local pane_id="$1" info
  [ -z "$pane_id" ] && echo "|dead||" && return
  info=$(wezterm cli list --format json 2>/dev/null | _wezterm_json_rows | awk -F '\t' -v pid="$pane_id" '
    $2 == "pane_id" { pane[$1] = $3 }
    $2 == "title" { title[$1] = $3 }
    $2 == "cwd" { cwd[$1] = $3 }
    END {
      for (i = 0; i <= 10000; i++) if (pane[i] == pid) { print pane[i] "|active|" title[i] "|" cwd[i]; found = 1; break }
      if (!found) print "|dead||"
    }') || info="|dead||"
  echo "$info"
}

_wezterm_poll_sessions() {
  local workspace="$1" tmpfile
  tmpfile="$(mktemp)"
  wezterm cli list --format json > "$tmpfile" 2>/dev/null || true
  _wezterm_json_rows < "$tmpfile" | awk -F '\t' -v ws="$workspace" '
    $2 == "workspace" { workspace[$1] = $3 }
    $2 == "tab_title" { tab[$1] = $3 }
    $2 == "pane_id" { pane[$1] = $3 }
    END { for (i = 0; i <= 10000; i++) if (workspace[i] == ws && tab[i] != "" && pane[i] != "") print pane[i] "|active" }
  '
  rm -f "$tmpfile"
}

tb_path_to_bash() {
  local path="$1" rest drive tail
  case "$path" in
    file:///[A-Za-z]:/*)
      rest="${path#file:///}"
      drive="${rest%%:*}"
      tail="${rest#*:}"
      drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
      printf '/%s%s\n' "$drive" "$tail"
      ;;
    [A-Za-z]:/*|[A-Za-z]:\\*)
      command -v cygpath >/dev/null 2>&1 && cygpath -u "$path" || printf '%s\n' "$path"
      ;;
    *) printf '%s\n' "$path" ;;
  esac
}

tb_path_to_agent() {
  local path="$1"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*)
      command -v cygpath >/dev/null 2>&1 && cygpath -w "$path" && return
      ;;
  esac
  printf '%s\n' "$path"
}

tb_path_is_absolute() {
  case "$1" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*|file:///[A-Za-z]:/*) return 0 ;;
  esac
  return 1
}

tb_is_windows_bash() {
  case "${POLYDEV_TEST_UNAME:-$(uname -s)}" in
    MINGW*|MSYS*|CYGWIN*|Windows*) return 0 ;;
  esac
  return 1
}

tb_is_default_git_bash_home() {
  local cwd users_root="/c""/Users"
  cwd="$(tb_path_to_bash "$1")"
  cwd="${cwd%/}"
  [ "${cwd##*/}" = "gitbash" ] && [ "${cwd%/*}" = "$users_root" ]
}

tb_infer_polydev_cwd_from_wezterm() {
  [ "$TB_BACKEND" != "wezterm" ] && return 1
  local tmp rows count
  tmp="$(mktemp)"
  wezterm cli list --format json 2>/dev/null | _wezterm_json_rows | awk -F '\t' '
    $2 == "workspace" { workspace[$1] = $3 }
    $2 == "cwd" { cwd[$1] = $3 }
    END { for (i = 0; i <= 10000; i++) if (workspace[i] ~ /^(ag|bg|wo)-/ && cwd[i] != "") print cwd[i] }
  ' | while IFS= read -r candidate; do
    candidate="$(tb_path_to_bash "$candidate")"
    case "$candidate" in ""|/c/Users/*) ;; *) printf '%s\n' "$candidate" ;; esac
  done | sort -u > "$tmp"
  count="$(wc -l < "$tmp" | tr -d ' ')"
  if [ "$count" = "1" ]; then
    rows="$(cat "$tmp")"
    rm -f "$tmp"
    printf '%s\n' "$rows"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

tb_resolve_cwd_arg() {
  local cwd_arg="$1" caller_cwd="${2:-}" base resolved
  if tb_path_is_absolute "$cwd_arg"; then
    resolved="$(tb_path_to_bash "$cwd_arg")"
  else
    if [ -n "$caller_cwd" ]; then base="$(tb_path_to_bash "$caller_cwd")"
    elif [ -n "${POLYDEV_CALLER_CWD:-}" ]; then base="$(tb_path_to_bash "$POLYDEV_CALLER_CWD")"
    else base="$(pwd)"
    fi
    if tb_is_windows_bash && tb_is_default_git_bash_home "$base"; then
      if inferred="$(tb_infer_polydev_cwd_from_wezterm)"; then base="$inferred"
      else echo "[E] error=Cannot resolve relative cwd '$cwd_arg' from Git Bash home '$base'; pass --caller-cwd or an absolute --cwd" >&2; return 1
      fi
    fi
    resolved="$base/$cwd_arg"
  fi
  [ -d "$resolved" ] || { echo "[E] error=Directory not found: $resolved" >&2; return 1; }
  (cd "$resolved" && pwd)
}

tb_find_claude_bin() {
  CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
  if [ -z "$CLAUDE_BIN" ]; then
    for candidate in "$HOME/.nvm/versions/node"/*/bin/claude "$HOME/.local/bin/claude" /usr/local/bin/claude; do
      [ -x "$candidate" ] && CLAUDE_BIN="$candidate" && break
    done
  fi
  [ -n "$CLAUDE_BIN" ] || return 1
  export CLAUDE_BIN
}

tb_launch_claude() {
  local pane_id="$1" claude_bin="$2" model="$3" cwd="${4:-}" extra_args=""
  if [ "$#" -gt 4 ]; then
    shift 4
    extra_args="$*"
  else
    set --
  fi
  pane_id=$(printf '%s' "$pane_id" | tr -d '\r')
  if [ "$TB_BACKEND" = "wezterm" ] && [ "$(_wezterm_get_pane_shell "$pane_id")" != "bash" ]; then
    echo "[E] error=ClaudeCode Bash adapter requires a bash pane" >&2
    return 1
  fi
  local cd_part=""
  [ -n "$cwd" ] && cd_part="cd $(_tb_quote_shell_arg "$cwd") && "
  tb_send_command "$pane_id" "${cd_part}unset CLAUDECODE && $claude_bin --dangerously-skip-permissions --model $model $extra_args" "true" "${POLYDEV_AGENT_ENTER_DELAY:-1}"
}

tb_create_pane_session() {
  case "$TB_BACKEND" in
    tmux) _tmux_create_session "$1" "$2" "$3" ;;
    wezterm) _wezterm_create_session "$1" "$2" "$3" ;;
  esac
}

tb_create_worktree_session() {
  tb_create_pane_session "$@"
}

tb_is_session_alive() {
  case "$TB_BACKEND" in
    tmux) _tmux_is_alive "$1" ;;
    wezterm) _wezterm_is_alive "$1" ;;
  esac
}

tb_send_command() {
  if [ "$TB_BACKEND" = "wezterm" ] && [ "${POLYDEV_PREPARE_CWD:-1}" = "1" ]; then
    POLYDEV_PREPARE_CWD=0 _wezterm_prepare_cwd "$1" || return 1
  fi
  case "$TB_BACKEND" in
    tmux) _tmux_send_command "$1" "$2" "${3:-true}" ;;
    wezterm) _wezterm_send_command "$1" "$2" "${3:-true}" "${4:-}" ;;
  esac
}

tb_send_multiline_text() {
  case "$TB_BACKEND" in
    tmux) _tmux_send_multiline_text "$1" "$2" "${3:-true}" ;;
    wezterm) _wezterm_send_multiline_text "$1" "$2" "${3:-true}" ;;
  esac
}

tb_focus_session() {
  case "$TB_BACKEND" in tmux) _tmux_focus_session "$1" ;; wezterm) _wezterm_focus_session "$1" ;; esac
}

tb_cleanup_session() {
  case "$TB_BACKEND" in tmux) _tmux_cleanup_session "$1" ;; wezterm) _wezterm_cleanup_session "$1" ;; esac
}

tb_get_session_info() {
  case "$TB_BACKEND" in tmux) _tmux_get_session_info "$1" ;; wezterm) _wezterm_get_session_info "$1" ;; esac
}

tb_poll_sessions() {
  case "$TB_BACKEND" in tmux) _tmux_poll_sessions "$1" ;; wezterm) _wezterm_poll_sessions "$1" ;; esac
}

_tb_capture_pane() {
  case "$TB_BACKEND" in
    wezterm) wezterm cli get-text --pane-id "$1" 2>/dev/null ;;
    tmux) _tmux capture-pane -t "$(_tmux_target_for_id "$1")" -p 2>/dev/null ;;
  esac
}

_tb_normalize_for_compare() {
  local path="$1"
  path="$(tb_path_to_bash "$path" 2>/dev/null || printf '%s' "$path")"
  path="${path%/}"
  printf '%s' "$path" | tr '[:upper:]' '[:lower:]'
}

_tb_trust_cwd_matches() {
  local content="$1" expected="$2" actual
  [ -z "$expected" ] && return 0
  actual="$(printf '%s\n' "$content" | sed -n 's/^.*You are in //p' | head -n1 | tr -d '\r')"
  [ -z "$actual" ] && return 0
  [ "$(_tb_normalize_for_compare "$actual")" = "$(_tb_normalize_for_compare "$expected")" ]
}

tb_wait_for_agent_ready() {
  local agent="$1" pane_id="$2" timeout="${3:-20}" expected_cwd="${4:-}" auto_trust="${5:-true}"
  local start_time trusted_sent=0 content elapsed
  start_time=$(date +%s)
  while true; do
    elapsed=$(($(date +%s) - start_time))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "[W] ${agent} wait timeout after ${timeout}s" >&2
      return 1
    fi
    tb_is_session_alive "$pane_id" || { echo "[E] Session died while waiting for ${agent}" >&2; return 1; }
    content="$(_tb_capture_pane "$pane_id")"
    if printf '%s' "$content" | grep -qiE 'command not found|No such file or directory|panic|error: unexpected argument'; then
      echo "[E] ${agent} launcher failed" >&2
      return 1
    fi
    if printf '%s' "$content" | grep -qiE 'Do you trust the contents of this directory|Press enter to continue'; then
      if ! _tb_trust_cwd_matches "$content" "$expected_cwd"; then
        echo "[E] ${agent} trust prompt cwd does not match expected cwd: $expected_cwd" >&2
        return 1
      fi
      if [ "$auto_trust" = "true" ] && [ "$trusted_sent" = "0" ]; then
        echo "[I] event=trust_prompt_confirmed,pane_id=$pane_id,agent=$agent" >&2
        tb_send_command "$pane_id" "" "true" "${POLYDEV_AGENT_ENTER_DELAY:-1}"
        trusted_sent=1
      fi
      sleep 0.2
      continue
    fi
    case "$agent" in
      codex)
        printf '%s' "$content" | grep -qE 'OpenAI Codex|Use /skills|context left|Ask Codex|What can I help|gpt-[^[:space:]]+[[:space:]].*·|^[[:space:]]*›|^[[:space:]]*>' && return 0
        ;;
      claude)
        printf '%s' "$content" | grep -qE 'Claude Code|bypass permissions|cwd:|^[[:space:]]*>|^[[:space:]]*›|❯' && return 0
        ;;
      gemini)
        printf '%s' "$content" | grep -qE 'Type your message|Gemini' && return 0
        ;;
      *)
        printf '%s' "$content" | grep -qE '^[[:space:]]*>|^[[:space:]]*›|❯' && return 0
        ;;
    esac
    sleep 0.25
  done
}

tb_wait_for_claude() {
  tb_wait_for_agent_ready "claude" "$1" "${2:-20}" "${4:-}" "true"
}

tb_wait_for_codex() {
  tb_wait_for_agent_ready "codex" "$1" "${2:-20}" "${3:-}" "true"
}

_tb_wait_for_marker() {
  local tool_name="$1" pane_id="$2" marker="$3" timeout="${4:-20}" start_time content
  start_time=$(date +%s)
  while true; do
    [ $(($(date +%s) - start_time)) -ge "$timeout" ] && echo "[W] $tool_name wait timeout after ${timeout}s" >&2 && return 1
    tb_is_session_alive "$pane_id" || { echo "[E] Session died while waiting for $tool_name" >&2; return 1; }
    content="$(_tb_capture_pane "$pane_id")"
    printf '%s' "$content" | grep -q "$marker" && return 0
    sleep 0.5
  done
}

tb_wait_for_gemini() {
  tb_wait_for_agent_ready "gemini" "$1" "${2:-20}"
}

tb_capture_content() {
  _tb_capture_pane "$1" | head -5
}

tb_get_backend() {
  echo "$TB_BACKEND"
}

tb_get_socket() {
  [ "$TB_BACKEND" = "tmux" ] && echo "$TB_SOCKET" || echo ""
}

tb_peek() {
  local pane_id="$1" delay="$2" lines="${3:-50}"
  [ "$delay" -gt 0 ] 2>/dev/null && sleep "$delay"
  echo "---PEEK---"
  "$SCRIPT_DIR/capture-screen.sh" --pane-id "$pane_id" --lines "$lines"
}

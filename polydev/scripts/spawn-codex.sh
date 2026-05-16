#!/bin/bash
# spawn-codex.sh - Start a ready Codex CLI TUI session.
#
# Usage:
#   spawn-codex.sh <name> --cwd <dir> [--workspace <name>] [--model <name>] [--ready-timeout 15] [--peek N]
#
# This script only starts the session and waits for the TUI to be ready.
# Use send-prompt.sh to send work after readiness is confirmed.

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

NAME=""
CWD=""
WORKSPACE=""
MODEL=""
VERBOSE=false
PEEK_DELAY=""
CALLER_CWD=""
READY_TIMEOUT="${CODEX_READY_TIMEOUT:-15}"

toon_log() {
  local event="$1"
  shift
  echo "[I] event=${event}${*:+,$*}"
}

usage() {
  echo "Usage: spawn-codex.sh <name> --cwd <dir> [--workspace <name>] [--model <name>] [--ready-timeout 15] [--peek N]" >&2
}

reject_old_arg() {
  echo "[E] error=spawn-codex.sh no longer accepts $1" >&2
  echo "[E] hint=Start the session first, then use send-prompt.sh and capture-screen.sh" >&2
  exit 2
}

find_codex_bin() {
  local codex_bin=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*)
      for candidate in \
        "/c/ProgramData/npm/npm/node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/codex/codex.exe" \
        "$HOME/AppData/Local/OpenAI/Codex/bin"/*/codex.exe; do
        [ -x "$candidate" ] && codex_bin="$candidate" && break
      done
      ;;
  esac
  [ -z "$codex_bin" ] && codex_bin="$(command -v codex 2>/dev/null || true)"
  [ -n "$codex_bin" ] || { echo "[E] error=codex binary not found" >&2; return 1; }
  printf '%s\n' "$codex_bin"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt|--output|--report) reject_old_arg "$1" ;;
    --cwd) CWD="$2"; shift 2 ;;
    --caller-cwd) CALLER_CWD="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --model|-m) MODEL="$2"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT="$2"; shift 2 ;;
    --peek) PEEK_DELAY="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [ -z "$NAME" ]; then NAME="$1"; else echo "[E] error=unexpected argument: $1" >&2; usage; exit 2; fi
      shift
      ;;
  esac
done

if [ -z "$NAME" ] || [ -z "$CWD" ]; then
  echo "[E] error=Missing required parameter(s): name or cwd" >&2
  usage
  exit 2
fi

CWD="$(tb_resolve_cwd_arg "$CWD" "$CALLER_CWD")" || exit 1
[ -n "$WORKSPACE" ] || WORKSPACE="$(basename "$CWD")"

if $VERBOSE; then
  echo "Starting Codex CLI session"
  echo "Name: $NAME"
  echo "Directory: $CWD"
  echo "Backend: $(tb_get_backend)"
  echo ""
fi

toon_log "agent_starting" "name=$NAME,workspace=$WORKSPACE,cwd=$CWD,timeout=$READY_TIMEOUT"

pane_id=$(tb_create_pane_session "ag-${WORKSPACE}" "$NAME" "$CWD" "")
toon_log "terminal_session_created" "pane_id=$pane_id,backend=$(tb_get_backend)"

CODEX_BIN="$(find_codex_bin)" || exit 1
CODEX_CMD="cd $(_tb_quote_shell_arg "$CWD") && $(_tb_quote_shell_arg "$CODEX_BIN") --cd $(_tb_quote_shell_arg "$CWD") --dangerously-bypass-approvals-and-sandbox --no-alt-screen --disable plugins"
[ -n "$MODEL" ] && CODEX_CMD="$CODEX_CMD -m $(_tb_quote_shell_arg "$MODEL")"

if ! tb_send_command "$pane_id" "$CODEX_CMD" "true" "${POLYDEV_AGENT_ENTER_DELAY:-1}"; then
  echo "[E] error=Failed to start Codex" >&2
  exit 1
fi

toon_log "codex_started" "pane_id=$pane_id,codex_bin=$CODEX_BIN${MODEL:+,model=$MODEL}"

if ! tb_wait_for_codex "$pane_id" "$READY_TIMEOUT" "$CWD"; then
  echo "[E] error=Codex did not become ready after startup timeout" >&2
  echo "[E] diagnostic=$SCRIPT_DIR/capture-screen.sh --pane-id $pane_id --lines 80" >&2
  echo "[E] cleanup=$SCRIPT_DIR/close-session.sh --pane-id $pane_id" >&2
  exit 1
fi

toon_log "agent_ready" "pane_id=$pane_id"
echo "$pane_id"

if [ -n "$PEEK_DELAY" ]; then
  tb_peek "$pane_id" "$PEEK_DELAY"
fi

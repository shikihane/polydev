#!/bin/bash
# spawn-agent.sh - Start a ready Claude Code TUI session.
#
# Usage:
#   spawn-agent.sh <name> --cwd <dir> [--workspace <name>] [--model sonnet] [--ready-timeout 15] [--peek N]
#
# This script only starts the session and waits for the TUI to be ready.
# Use send-prompt.sh to send work after readiness is confirmed.

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

NAME=""
CWD=""
WORKSPACE=""
MODEL="${CLAUDE_MODEL:-sonnet}"
VERBOSE=false
PEEK_DELAY=""
CALLER_CWD=""
READY_TIMEOUT="${CLAUDE_READY_TIMEOUT:-15}"

toon_log() {
  local event="$1"
  shift
  echo "[I] event=${event}${*:+,$*}"
}

usage() {
  echo "Usage: spawn-agent.sh <name> --cwd <dir> [--workspace <name>] [--model sonnet] [--ready-timeout 15] [--peek N]" >&2
}

reject_old_arg() {
  echo "[E] error=spawn-agent.sh no longer accepts $1" >&2
  echo "[E] hint=Start the session first, then use send-prompt.sh and capture-screen.sh" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt|--report|--output) reject_old_arg "$1" ;;
    --cwd) CWD="$2"; shift 2 ;;
    --caller-cwd) CALLER_CWD="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
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
  echo "Starting Claude Code session"
  echo "Name: $NAME"
  echo "Directory: $CWD"
  echo "Model: $MODEL"
  echo "Backend: $(tb_get_backend)"
  echo ""
fi

toon_log "agent_starting" "name=$NAME,workspace=$WORKSPACE,cwd=$CWD,model=$MODEL,timeout=$READY_TIMEOUT"

pane_id=$(tb_create_pane_session "ag-${WORKSPACE}" "$NAME" "$CWD" "")
toon_log "terminal_session_created" "pane_id=$pane_id,backend=$(tb_get_backend)"

if ! tb_find_claude_bin; then
  echo "[E] error=claude binary not found" >&2
  exit 1
fi

if ! tb_launch_claude "$pane_id" "$CLAUDE_BIN" "$MODEL" "$CWD"; then
  echo "[E] error=Failed to start Claude" >&2
  exit 1
fi

toon_log "claude_started" "model=$MODEL,pane_id=$pane_id"

if ! tb_wait_for_claude "$pane_id" "$READY_TIMEOUT" "" "$CWD"; then
  echo "[E] error=Claude did not become ready after startup timeout" >&2
  echo "[E] diagnostic=$SCRIPT_DIR/capture-screen.sh --pane-id $pane_id --lines 80" >&2
  echo "[E] cleanup=$SCRIPT_DIR/close-session.sh --pane-id $pane_id" >&2
  exit 1
fi

toon_log "agent_ready" "pane_id=$pane_id"
echo "$pane_id"

if [ -n "$PEEK_DELAY" ]; then
  tb_peek "$pane_id" "$PEEK_DELAY"
fi

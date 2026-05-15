#!/bin/bash
# spawn-codex.sh - Start a Codex CLI session with a prompt (no worktree)
#
# Usage: spawn-codex.sh <name> --prompt "<task>" --cwd <dir> [--model <name>] [--output <path>] [--verbose]
#
# Output (TOON by default):
#   [I] event=agent_starting,name=...,workspace=...,cwd=...
#   [I] event=terminal_session_created,pane_id=...,backend=...
#   [I] event=codex_started,pane_id=...
#   [I] event=prompt_sent,length=...
#   [I] event=agent_ready,pane_id=...
#   5  (pane_id on last line for scripting)
#
# Use --verbose for human-readable output

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/terminal-backend.sh"

NAME=""
PROMPT=""
OUTPUT_PATH=""
CWD=""
WORKSPACE=""
MODEL=""
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --cwd)
      CWD="$2"
      shift 2
      ;;
    --workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    --model|-m)
      MODEL="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      if [ -z "$NAME" ]; then
        NAME="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$NAME" ] || [ -z "$PROMPT" ] || [ -z "$CWD" ]; then
  echo "error=Missing required parameter(s): name, prompt, or cwd" >&2
  echo "Usage: spawn-codex.sh <name> --prompt \"<task>\" --cwd <dir> [--model <name>] [--output <path>] [--verbose]" >&2
  exit 1
fi

if [ ! -d "$CWD" ]; then
  echo "error=Directory not found: $CWD" >&2
  exit 1
fi

CWD="$(cd "$CWD" && pwd)"

# Derive workspace from CWD if not explicitly set
if [ -z "$WORKSPACE" ]; then
  WORKSPACE="$(basename "$CWD")"
fi

# Handle output path if provided. This Bash adapter is for D3 Linux Codex Bash,
# not D1 native Windows Codex.
if [ -n "$OUTPUT_PATH" ]; then
  if [[ "$OUTPUT_PATH" != /* ]]; then
    OUTPUT_PATH="$CWD/$OUTPUT_PATH"
  fi
  OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
  mkdir -p "$OUTPUT_DIR"
fi

toon_log() {
  local event="$1"
  shift
  local pairs="$*"
  echo "[I] event=${event}${pairs:+,${pairs}}"
}

if $VERBOSE; then
  echo "Starting Codex CLI Session"
  echo "Name: $NAME"
  echo "Prompt: ${PROMPT:0:50}..."
  [ -n "$OUTPUT_PATH" ] && echo "Output: $OUTPUT_PATH"
  echo "Directory: $CWD"
  echo "Backend: $(tb_get_backend)"
  echo ""
fi

toon_log "agent_starting" "name=$NAME,workspace=$WORKSPACE,cwd=$CWD"

# Create session
ag_workspace="ag-${WORKSPACE}"
pane_id=$(tb_create_worktree_session "$ag_workspace" "$NAME" "$CWD" "")

toon_log "terminal_session_created" "pane_id=$pane_id,backend=$(tb_get_backend)"

if [ -n "$OUTPUT_PATH" ]; then
  PROMPT="${PROMPT}

Write your final answer to: ${OUTPUT_PATH}
Do this before replying AGENT_DONE."
fi

# Start Codex
CODEX_CMD="codex --dangerously-bypass-approvals-and-sandbox"
if [ -n "$MODEL" ]; then
  CODEX_CMD="$CODEX_CMD -m $MODEL"
fi
if ! tb_send_command "$pane_id" "$CODEX_CMD" "true"; then
  echo "[E] error=Failed to start Codex" >&2
  exit 1
fi

toon_log "codex_started" "pane_id=$pane_id${MODEL:+,model=$MODEL}"

# Wait for Codex to be ready. Codex startup can be slow when it prints a lot of
# initialization output; if the pane is still alive, keep the session and try a
# short recovery wait before sending the prompt.
if ! tb_wait_for_codex "$pane_id" 30; then
  if ! tb_is_session_alive "$pane_id"; then
    echo "[E] error=Codex session died while starting" >&2
    exit 1
  fi

  toon_log "codex_wait_timeout" "pane_id=$pane_id,timeout=30"

  if tb_wait_for_codex "$pane_id" 10; then
    toon_log "codex_wait_recovered" "pane_id=$pane_id"
  else
    if ! tb_is_session_alive "$pane_id"; then
      echo "[E] error=Codex session died after startup timeout" >&2
      exit 1
    fi
    toon_log "codex_wait_recovery_warning" "pane_id=$pane_id"
  fi
fi

# Send prompt directly (no template wrapping)
if tb_send_multiline_text "$pane_id" "$PROMPT" "true"; then
  toon_log "prompt_sent" "length=${#PROMPT}"
else
  toon_log "prompt_send_warning" "pane_id=$pane_id"
fi

output_info=""
[ -n "$OUTPUT_PATH" ] && output_info=",output=$OUTPUT_PATH"
toon_log "agent_ready" "pane_id=$pane_id${output_info}"

if $VERBOSE; then
  echo ""
  echo "Codex session started: pane_id=$pane_id"
  [ -n "$OUTPUT_PATH" ] && echo "Output: $OUTPUT_PATH"
  echo "Monitor: capture-screen.sh --pane-id $pane_id --lines 30"
fi

echo "$pane_id"

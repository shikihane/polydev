#!/bin/bash
# spawn-agent.sh - Start an investigation agent (Claude, no worktree)
#
# Usage: spawn-agent.sh <name> --prompt "<task>" --report <report_path> [--cwd <dir>] [--model <model>] [--verbose]
#
# Output (TOON by default):
#   [I] event=agent_starting,name=...,workspace=...,cwd=...,model=...
#   [I] event=terminal_session_created,pane_id=...,backend=...
#   [I] event=claude_started,model=...,pane_id=...
#   [I] event=prompt_sent,template=...
#   [I] event=agent_ready,pane_id=...,report=...
#   5  (pane_id on last line for scripting)
#
# Use --verbose for human-readable output

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/terminal-backend.sh"

NAME=""
PROMPT=""
REPORT_PATH=""
CWD=""
WORKSPACE=""
MODEL="${CLAUDE_MODEL:-sonnet}"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    --report)
      REPORT_PATH="$2"
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
    --model)
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

if [ -z "$NAME" ] || [ -z "$PROMPT" ] || [ -z "$REPORT_PATH" ] || [ -z "$CWD" ]; then
  echo "error=Missing required parameter(s): name, prompt, report, or cwd" >&2
  echo "Usage: spawn-agent.sh <name> --prompt \"<task>\" --report <path> --cwd <dir> [--verbose]" >&2
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

if [[ "$REPORT_PATH" != /* ]]; then
  REPORT_PATH="$CWD/$REPORT_PATH"
fi

REPORT_DIR="$(dirname "$REPORT_PATH")"
mkdir -p "$REPORT_DIR"

toon_log() {
  local event="$1"
  shift
  local pairs="$*"
  echo "[I] event=${event}${pairs:+,${pairs}}"
}

if $VERBOSE; then
  echo "Starting Investigation Agent"
  echo "Name: $NAME"
  echo "Prompt: ${PROMPT:0:50}..."
  echo "Report: $REPORT_PATH"
  echo "Directory: $CWD"
  echo "Model: $MODEL"
  echo "Backend: $(tb_get_backend)"
  echo ""
fi

toon_log "agent_starting" "name=$NAME,workspace=$WORKSPACE,cwd=$CWD,model=$MODEL"

# Create session
ag_workspace="ag-${WORKSPACE}"
pane_id=$(tb_create_worktree_session "$ag_workspace" "$NAME" "$CWD" "")

toon_log "terminal_session_created" "pane_id=$pane_id,backend=$(tb_get_backend)"

# Capture terminal state before starting Claude
initial_content=$(tb_capture_content "$pane_id")

# Start Claude
if ! tb_send_command "$pane_id" "claude --dangerously-skip-permissions --model $MODEL" "true"; then
  echo "[E] error=Failed to start Claude" >&2
  exit 1
fi

toon_log "claude_started" "model=$MODEL,pane_id=$pane_id"

# Wait for Claude to start (detects terminal content change, max 5s)
tb_wait_for_claude "$pane_id" 5 "$initial_content"

# Build agent prompt
AGENT_PROMPT=""
if [ -f "$ORCHESTRATOR_DIR/templates/investigator-prompt.md" ]; then
  AGENT_PROMPT=$(cat "$ORCHESTRATOR_DIR/templates/investigator-prompt.md")
  AGENT_PROMPT="${AGENT_PROMPT//\{\{TASK\}\}/$PROMPT}"
  AGENT_PROMPT="${AGENT_PROMPT//\{\{REPORT_PATH\}\}/$REPORT_PATH}"
else
  AGENT_PROMPT="You are an investigation agent. Your task:

$PROMPT

## Requirements

1. Investigate thoroughly using available tools
2. Write your findings to: $REPORT_PATH
3. When complete, output this EXACT marker:

\`\`\`
[AGENT_DONE]
report: $REPORT_PATH
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
summary: <20字以内摘要>
\`\`\`

Start now."
fi

# Send prompt
if tb_send_multiline_text "$pane_id" "$AGENT_PROMPT" "true"; then
  toon_log "prompt_sent" "template=investigator-prompt.md"
else
  toon_log "prompt_send_warning" "pane_id=$pane_id"
fi

toon_log "agent_ready" "pane_id=$pane_id,report=$REPORT_PATH"

if $VERBOSE; then
  echo ""
  echo "Investigation agent started: pane_id=$pane_id"
  echo "Report: $REPORT_PATH"
  echo "Monitor: capture-screen.sh --pane-id $pane_id --lines 30"
fi

echo "$pane_id"

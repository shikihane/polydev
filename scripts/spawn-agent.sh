#!/bin/bash
# spawn-agent.sh - Start an investigation agent (Claude, no worktree)
#
# Usage: spawn-agent.sh <name> --prompt "<task>" --report <report_path> [--cwd <dir>] [--model <model>]
#
# Returns: session_id (format: ag:<workspace>:<name>.0)
#
# The agent will:
#   1. Execute the investigation task
#   2. Write results to the report file
#   3. Output [AGENT_DONE] marker when complete
#
# Examples:
#   ./scripts/spawn-agent.sh auth-research \
#     --prompt "分析项目的认证机制，找出安全隐患" \
#     --report ./.agent-reports/auth-analysis.md
#
#   ./scripts/spawn-agent.sh codebase-overview \
#     --prompt "给我一个项目结构概述" \
#     --report ./.agent-reports/overview.md \
#     --model sonnet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/terminal-backend.sh"

# Defaults
NAME=""
PROMPT=""
REPORT_PATH=""
CWD="$(pwd)"
WORKSPACE="$(basename "$(pwd)")"
MODEL="${CLAUDE_MODEL:-sonnet}"  # Default to sonnet for cost control

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
    *)
      if [ -z "$NAME" ]; then
        NAME="$1"
      fi
      shift
      ;;
  esac
done

# Validation
if [ -z "$NAME" ] || [ -z "$PROMPT" ] || [ -z "$REPORT_PATH" ]; then
  echo "Usage: spawn-agent.sh <name> --prompt \"<task>\" --report <path> [--cwd <dir>] [--model <model>]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --prompt    The investigation task (required)" >&2
  echo "  --report    Path for the report file (required)" >&2
  echo "  --cwd       Working directory (default: current)" >&2
  echo "  --model     Claude model: sonnet, opus, haiku (default: sonnet)" >&2
  echo "" >&2
  echo "Example:" >&2
  echo "  ./scripts/spawn-agent.sh auth-research \\" >&2
  echo "    --prompt \"分析认证机制\" \\" >&2
  echo "    --report ./.agent-reports/auth.md" >&2
  exit 1
fi

# Validate CWD
if [ ! -d "$CWD" ]; then
  echo "Error: Directory not found: $CWD" >&2
  exit 1
fi

# Convert to absolute paths
CWD="$(cd "$CWD" && pwd)"

# Handle report path - make it absolute if relative
if [[ "$REPORT_PATH" != /* ]]; then
  REPORT_PATH="$CWD/$REPORT_PATH"
fi

# Create report directory if needed
REPORT_DIR="$(dirname "$REPORT_PATH")"
mkdir -p "$REPORT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Starting Investigation Agent"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Name:      $NAME"
echo "Prompt:    ${PROMPT:0:50}..."
echo "Report:    $REPORT_PATH"
echo "Directory: $CWD"
echo "Model:     $MODEL"
echo "Backend:   $(tb_get_backend)"
echo ""

# Create session
ag_workspace="ag-${WORKSPACE}"

echo "🖥️  Creating terminal session..."
internal_session_id=$(tb_create_worktree_session "$ag_workspace" "$NAME" "$CWD" "")
external_session_id="${internal_session_id/wo:/ag:}"
echo "   ✅ Session created: $external_session_id"

# Start Claude
echo ""
echo "🤖 Starting Claude agent..."
if ! tb_send_command "$internal_session_id" "claude --dangerously-skip-permissions --model $MODEL" "true"; then
  echo "   ❌ Failed to start Claude" >&2
  exit 1
fi

# Wait for Claude to initialize
echo "⏳ Waiting for Claude to start..."
tb_wait_for_claude "$internal_session_id" 15

# Build the agent prompt
# Use the investigator prompt template if available, otherwise use inline
AGENT_PROMPT=""
if [ -f "$ORCHESTRATOR_DIR/templates/investigator-prompt.md" ]; then
  AGENT_PROMPT=$(cat "$ORCHESTRATOR_DIR/templates/investigator-prompt.md")
  # Replace placeholders
  AGENT_PROMPT="${AGENT_PROMPT//\{\{TASK\}\}/$PROMPT}"
  AGENT_PROMPT="${AGENT_PROMPT//\{\{REPORT_PATH\}\}/$REPORT_PATH}"
else
  # Inline prompt
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

# Send the prompt
echo ""
echo "📤 Sending investigation task..."
if tb_send_multiline_text "$internal_session_id" "$AGENT_PROMPT" "true"; then
  echo "   ✅ Task sent"
else
  echo "   ⚠️  Warning: Task may not have been sent properly"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Investigation agent started!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Session ID: $external_session_id"
echo "Report:     $REPORT_PATH"
echo ""
echo "💡 Wait for completion:"
echo "   ./scripts/wait-for-pattern.sh $external_session_id --success \"\\[AGENT_DONE\\]\" --timeout 600"
echo ""
echo "💡 Check status:"
echo "   ./scripts/analyze-output.sh $external_session_id --lines 10 --json"
echo ""
echo "💡 View progress:"
echo "   ./scripts/capture-screen.sh --session $internal_session_id --lines 30"
echo ""

# Output session_id for scripting
echo "$external_session_id"

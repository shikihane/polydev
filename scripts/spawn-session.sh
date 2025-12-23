#!/bin/bash
# spawn-session.sh - Create worktree + terminal session + start Claude
#
# Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level] [verify_fallback] [verify_commands]
#
# Verification info can be passed as arguments or extracted from plan file frontmatter
# Supports both tmux (Linux/macOS) and wezterm (Windows) via terminal-backend.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

# Portable sed -i (works on GNU and BSD/macOS)
sed_inplace() {
  local expr="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

WORKSPACE="$1"
BRANCH_NAME="$2"
WORKTREE_PATH="$3"
PLAN_FILE="$4"
VERIFY_LEVEL="${5:-L2}"
VERIFY_FALLBACK="${6:-L1}"
VERIFY_COMMANDS="${7:-}"

if [ -z "$WORKSPACE" ] || [ -z "$BRANCH_NAME" ] || [ -z "$WORKTREE_PATH" ] || [ -z "$PLAN_FILE" ]; then
  echo "Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level] [verify_fallback] [verify_commands]"
  exit 1
fi

# Try to extract verification info from plan file frontmatter if not provided
if [ -z "$VERIFY_COMMANDS" ] && [ -f "$PLAN_FILE" ]; then
  # Extract level from frontmatter
  extracted_level=$(grep -A10 "^---" "$PLAN_FILE" | grep "level:" | head -1 | sed 's/.*level: *//' | tr -d ' ')
  [ -n "$extracted_level" ] && VERIFY_LEVEL="$extracted_level"

  # Extract fallback
  extracted_fallback=$(grep -A10 "^---" "$PLAN_FILE" | grep "fallback:" | head -1 | sed 's/.*fallback: *//' | tr -d ' ')
  [ -n "$extracted_fallback" ] && VERIFY_FALLBACK="$extracted_fallback"
fi

# Create worktree
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"

# Setup .claude directory with hooks
mkdir -p "$WORKTREE_PATH/.claude/hooks"
cp "$ORCHESTRATOR_DIR/templates/claude-settings.json" "$WORKTREE_PATH/.claude/settings.json"
cp "$ORCHESTRATOR_DIR/hooks/on-stop.sh" "$WORKTREE_PATH/.claude/hooks/"
cp "$ORCHESTRATOR_DIR/hooks/on-session-start.sh" "$WORKTREE_PATH/.claude/hooks/"
chmod +x "$WORKTREE_PATH/.claude/hooks/"*.sh 2>/dev/null || true

# Copy plan file
cp "$PLAN_FILE" "$WORKTREE_PATH/PLAN.md"

# Initialize task.toon with verification info
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sed -e "s|{{WORKTREE_PATH}}|$WORKTREE_PATH|g" \
    -e "s|{{BRANCH_NAME}}|$BRANCH_NAME|g" \
    -e "s|{{CREATED}}|$CREATED|g" \
    -e "s|{{VERIFY_LEVEL}}|$VERIFY_LEVEL|g" \
    -e "s|{{VERIFY_FALLBACK}}|$VERIFY_FALLBACK|g" \
    -e "s|{{VERIFY_COMMANDS}}|$VERIFY_COMMANDS|g" \
    "$ORCHESTRATOR_DIR/templates/task.toon.template" > "$WORKTREE_PATH/task.toon"

# Create terminal session using abstraction layer
PROJECT_NAME=$(basename "$(pwd)")
TAB_NAME="${PROJECT_NAME}-${BRANCH_NAME}"

session_id=$(tb_create_worktree_session "$WORKSPACE" "$TAB_NAME" "$WORKTREE_PATH" "$PLAN_FILE")

# Update session_id in task.toon (replaces old pane_id)
sed_inplace "s/PENDING_PANE_ID/$session_id/" "$WORKTREE_PATH/task.toon"

# Start Claude
tb_send_command "$session_id" "claude --dangerously-skip-permissions"

# Wait for Claude to start, then send prompt
(
  sleep 4
  prompt=$(cat "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md")
  tb_send_command "$session_id" "$prompt"
) &

echo "Spawned: session_id=$session_id, worktree=$WORKTREE_PATH, branch=$BRANCH_NAME, verify=$VERIFY_LEVEL, backend=$(tb_get_backend)"

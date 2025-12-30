#!/bin/bash
# spawn-session.sh - Create worktree + terminal session + start Claude
#
# Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level] [verify_fallback] [verify_commands]
#
# Environment variables:
#   CLAUDE_MODEL - Model to use for sub-agents (default: sonnet)
#                  Options: sonnet, opus, haiku
#
# Verification info can be passed as arguments or extracted from plan file frontmatter
# Supports both tmux (Linux/macOS) and wezterm (Windows) via terminal-backend.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

# Portable sed -i (works on GNU and BSD/macOS) with atomic operations
sed_inplace() {
  local expr="$1" file="$2"
  local tmp="${file}.tmp.$$"
  local backup="${file}.backup.$$"

  # Create safety backup
  if ! cp "$file" "$backup" 2>/dev/null; then
    echo "❌ Error: Cannot create backup of $file" >&2
    return 1
  fi

  # Try sed operation
  if sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"; then
    rm -f "$backup"
    return 0
  else
    # Restore on failure
    echo "⚠️  Warning: sed operation failed, restoring original" >&2
    mv "$backup" "$file"
    rm -f "$tmp"
    return 1
  fi
}

# Backup task.toon before modification
backup_task_toon() {
  local task_file="$1"
  local backup_dir="$(dirname "$task_file")/.task_backups"

  [ ! -f "$task_file" ] && return 0

  mkdir -p "$backup_dir"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$task_file" "$backup_dir/task.toon.${timestamp}.bak"

  # Keep only last 10 backups (safer than xargs for portability)
  (cd "$backup_dir" && ls -t task.toon.*.bak 2>/dev/null | tail -n +11 | while read f; do rm -f "$f"; done) 2>/dev/null || true
}

WORKSPACE="$1"
BRANCH_NAME="$2"
WORKTREE_PATH="$3"
PLAN_FILE="$4"
VERIFY_LEVEL="${5:-L2}"
VERIFY_FALLBACK="${6:-L1}"
VERIFY_COMMANDS="${7:-}"

# Model for sub-agents (default: sonnet for cost control)
CLAUDE_MODEL="${CLAUDE_MODEL:-sonnet}"

if [ -z "$WORKSPACE" ] || [ -z "$BRANCH_NAME" ] || [ -z "$WORKTREE_PATH" ] || [ -z "$PLAN_FILE" ]; then
  echo "❌ Error: Missing required arguments"
  echo ""
  echo "Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level] [verify_fallback] [verify_commands]"
  echo ""
  echo "Arguments:"
  echo "  workspace       - Name of the workspace (e.g., 'myproject-parallel')"
  echo "  branch_name     - Git branch name for the worktree"
  echo "  worktree_path   - Path where worktree will be created"
  echo "  plan_file       - Path to PLAN.md file"
  echo "  verify_level    - Optional: Verification level (L0-L5), default: L2"
  echo "  verify_fallback - Optional: Fallback level, default: L1"
  echo "  verify_commands - Optional: Custom verification commands"
  echo ""
  echo "Example:"
  echo "  ./spawn-session.sh myproject-parallel feature-auth .worktrees/auth ./PLAN.md L3 L2"
  exit 1
fi

# Validate plan file exists
if [ ! -f "$PLAN_FILE" ]; then
  echo "❌ Error: Plan file not found: $PLAN_FILE"
  exit 1
fi

# Check if worktree path already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo "⚠️  Warning: Directory already exists: $WORKTREE_PATH"
  echo "   Use restore-session.sh to recover, or cleanup-worktree.sh to remove it."
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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Creating Worktree Session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Workspace:     $WORKSPACE"
echo "Branch:        $BRANCH_NAME"
echo "Worktree:      $WORKTREE_PATH"
echo "Verification:  $VERIFY_LEVEL (fallback: $VERIFY_FALLBACK)"
echo "Model:         $CLAUDE_MODEL"
echo "Backend:       $(tb_get_backend)"
echo ""

# Create worktree
echo "📁 Creating git worktree..."
if ! git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null; then
  echo "❌ Failed to create worktree"
  echo "   This might mean the branch already exists or the path is invalid."
  echo "   Run 'git worktree list' to see existing worktrees."
  exit 1
fi
echo "   ✅ Worktree created"

# Setup .claude directory with hooks
echo ""
echo "⚙️  Setting up Claude configuration..."
mkdir -p "$WORKTREE_PATH/.claude/hooks"
cp "$ORCHESTRATOR_DIR/templates/claude-settings.json" "$WORKTREE_PATH/.claude/settings.json"
cp "$ORCHESTRATOR_DIR/hooks/on-stop.sh" "$WORKTREE_PATH/.claude/hooks/"
cp "$ORCHESTRATOR_DIR/hooks/on-session-start.sh" "$WORKTREE_PATH/.claude/hooks/"
chmod +x "$WORKTREE_PATH/.claude/hooks/"*.sh 2>/dev/null || true
echo "   ✅ Claude config ready"

# Copy plan file
echo ""
echo "📋 Copying plan file..."
cp "$PLAN_FILE" "$WORKTREE_PATH/PLAN.md"
echo "   ✅ PLAN.md copied"

# Initialize task.toon with verification info
echo ""
echo "📝 Creating task.toon..."
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sed -e "s|{{WORKTREE_PATH}}|$WORKTREE_PATH|g" \
    -e "s|{{BRANCH_NAME}}|$BRANCH_NAME|g" \
    -e "s|{{CREATED}}|$CREATED|g" \
    -e "s|{{VERIFY_LEVEL}}|$VERIFY_LEVEL|g" \
    -e "s|{{VERIFY_FALLBACK}}|$VERIFY_FALLBACK|g" \
    -e "s|{{VERIFY_COMMANDS}}|$VERIFY_COMMANDS|g" \
    "$ORCHESTRATOR_DIR/templates/task.toon.template" > "$WORKTREE_PATH/task.toon"
echo "   ✅ task.toon initialized"

# Create terminal session using abstraction layer
echo ""
echo "🖥️  Creating terminal session..."
PROJECT_NAME=$(basename "$(pwd)")
TAB_NAME="${PROJECT_NAME}-${BRANCH_NAME}"

session_id=$(tb_create_worktree_session "$WORKSPACE" "$TAB_NAME" "$WORKTREE_PATH" "$PLAN_FILE")
echo "   ✅ Session created: $session_id"

# Update session_id in task.toon (replaces old pane_id)
# Backup first, then update
backup_task_toon "$WORKTREE_PATH/task.toon"
# Use | as delimiter to safely handle : and . in session_id
sed_inplace "s|PENDING_PANE_ID|$session_id|" "$WORKTREE_PATH/task.toon"

# Start Claude
echo ""
echo "🤖 Starting Claude agent..."

if ! tb_send_command "$session_id" "claude --dangerously-skip-permissions --model $CLAUDE_MODEL"; then
  echo "❌ Failed to start Claude"
  echo "   Session ID: $session_id"
  echo "   Try manually: ./scripts/focus-session.sh $WORKTREE_PATH"
  exit 1
fi

# Wait for Claude to start
tb_wait_for_claude "$session_id" 15

# Send the agent prompt
if [ -f "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md" ]; then
  echo ""
  echo "📤 Sending agent prompt..."
  prompt=$(cat "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md")

  if tb_send_multiline_text "$session_id" "$prompt" "true"; then
    echo "   ✅ Prompt sent successfully"
  else
    echo "   ⚠️  Warning: Prompt may not have been sent"
    echo "   You can manually send it by attaching to the session"
  fi
else
  echo "⚠️  Warning: Agent prompt file not found"
fi

echo "   ✅ Claude launched and configured"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Session spawned successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Session ID:  $session_id"
echo "Worktree:    $WORKTREE_PATH"
echo "Branch:      $BRANCH_NAME"
echo "Backend:     $(tb_get_backend)"
echo ""
echo "💡 Next steps:"
echo "   - Monitor with: ./scripts/poll.sh .worktrees 10"
echo "   - Focus with:   ./scripts/focus-session.sh $WORKTREE_PATH"
echo "   - Check status: cat $WORKTREE_PATH/task.toon"
echo ""

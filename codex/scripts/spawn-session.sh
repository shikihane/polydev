#!/bin/bash
# spawn-session.sh - Create worktree + terminal session + start Codex CLI
#
# Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level] [verify_fallback] [verify_commands]
#
# Environment variables:
#   CODEX_APPROVAL - Approval mode: untrusted, on-failure, full-auto (default: on-failure)
#                    Maps to Codex CLI: -a <mode> or --full-auto
#
# Verification info can be passed as arguments or extracted from plan file frontmatter
# Supports both tmux (Linux/macOS) and wezterm (Windows) via terminal-backend.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$(dirname "$SCRIPT_DIR")"

# Source terminal backend abstraction (local copy)
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

# Approval mode for Codex CLI (default: on-failure for reasonable automation)
# Valid values: untrusted, on-failure, on-request, never, full-auto
CODEX_APPROVAL="${CODEX_APPROVAL:-on-failure}"

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
  echo "Environment:"
  echo "  CODEX_APPROVAL  - Approval mode: untrusted, on-failure, on-request, never, full-auto (default: on-failure)"
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
echo "🚀 Creating Worktree Session (Codex CLI)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Workspace:     $WORKSPACE"
echo "Branch:        $BRANCH_NAME"
echo "Worktree:      $WORKTREE_PATH"
echo "Verification:  $VERIFY_LEVEL (fallback: $VERIFY_FALLBACK)"
echo "Approval:      $CODEX_APPROVAL"
echo "Backend:       $(tb_get_backend)"
echo ""

# Check if git repo exists
if ! git rev-parse --git-dir &>/dev/null; then
  echo "❌ Error: Not a git repository."
  echo ""
  echo "   Please initialize git first:"
  echo "     git init"
  echo "     git add ."
  echo "     git commit -m \"initial commit\""
  exit 1
fi

# Check if there's at least one commit (required for worktree)
if ! git rev-parse HEAD &>/dev/null; then
  echo "❌ Error: No commits found. Git worktree requires at least one commit."
  echo ""
  echo "   Please create an initial commit first:"
  echo "     git add ."
  echo "     git commit -m \"initial commit\""
  exit 1
fi

# Create .worktrees directory if needed
WORKTREE_PARENT=$(dirname "$WORKTREE_PATH")
if [ ! -d "$WORKTREE_PARENT" ]; then
  echo "📁 Creating worktrees directory: $WORKTREE_PARENT"
  mkdir -p "$WORKTREE_PARENT"
fi

# Create worktree
echo "📁 Creating git worktree..."
if ! git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null; then
  echo "❌ Failed to create worktree"
  echo "   This might mean the branch already exists or the path is invalid."
  echo "   Run 'git worktree list' to see existing worktrees."
  exit 1
fi
echo "   ✅ Worktree created"

# Setup .codex directory (Codex uses .codex instead of .claude)
echo ""
echo "⚙️  Setting up Codex configuration..."
mkdir -p "$WORKTREE_PATH/.codex/skills"

# Copy polydev-executor skill to worktree for sub-agent use
CODEX_SKILLS_DIR="$(dirname "$SCRIPT_DIR")/skills"
if [ -d "$CODEX_SKILLS_DIR/polydev-executor" ]; then
  cp -r "$CODEX_SKILLS_DIR/polydev-executor" "$WORKTREE_PATH/.codex/skills/"
  echo "   ✅ polydev-executor skill installed"
fi

echo "   ✅ Codex config ready"

# Copy plan file
echo ""
echo "📋 Copying plan file..."
cp "$PLAN_FILE" "$WORKTREE_PATH/PLAN.md"
echo "   ✅ PLAN.md copied"

# Initialize task.toon with verification info
echo ""
echo "📝 Creating task.toon..."
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Use the main template if exists, otherwise create basic one
if [ -f "$CODEX_DIR/templates/task.toon.template" ]; then
  sed -e "s|{{WORKTREE_PATH}}|$WORKTREE_PATH|g" \
      -e "s|{{BRANCH_NAME}}|$BRANCH_NAME|g" \
      -e "s|{{CREATED}}|$CREATED|g" \
      -e "s|{{VERIFY_LEVEL}}|$VERIFY_LEVEL|g" \
      -e "s|{{VERIFY_FALLBACK}}|$VERIFY_FALLBACK|g" \
      -e "s|{{VERIFY_COMMANDS}}|$VERIFY_COMMANDS|g" \
      "$CODEX_DIR/templates/task.toon.template" > "$WORKTREE_PATH/task.toon"
else
  # Fallback: create basic task.toon
  cat > "$WORKTREE_PATH/task.toon" << EOF
branch: $BRANCH_NAME
worktree_path: $WORKTREE_PATH
overall_status: pending
agent_status: idle
blocking_reason:
verify_level: $VERIFY_LEVEL
verify_fallback: $VERIFY_FALLBACK
session_id: PENDING_PANE_ID
created: $CREATED
last_update: $CREATED
EOF
fi
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

# Start Codex CLI
echo ""
echo "🤖 Starting Codex CLI agent..."

# Build Codex CLI command with correct approval flags
# Codex CLI uses: -a <mode> or --full-auto, not --approvals
if [ "$CODEX_APPROVAL" = "full-auto" ]; then
  CODEX_CMD="codex --full-auto"
else
  CODEX_CMD="codex -a $CODEX_APPROVAL"
fi

if ! tb_send_command "$session_id" "$CODEX_CMD"; then
  echo "❌ Failed to start Codex"
  echo "   Session ID: $session_id"
  echo "   Try manually: focus the session and run: $CODEX_CMD"
  exit 1
fi

# Wait for Codex to start (reuse Claude wait function, works for any CLI)
tb_wait_for_claude "$session_id" 15

# Send the agent prompt for Codex
CODEX_PROMPT_FILE="$(dirname "$SCRIPT_DIR")/templates/worktree-agent-prompt.md"
if [ -f "$CODEX_PROMPT_FILE" ]; then
  echo ""
  echo "📤 Sending agent prompt..."
  prompt=$(cat "$CODEX_PROMPT_FILE")

  if tb_send_multiline_text "$session_id" "$prompt" "true"; then
    echo "   ✅ Prompt sent successfully"
  else
    echo "   ⚠️  Warning: Prompt may not have been sent"
    echo "   You can manually send it by attaching to the session"
  fi
elif [ -f "$CODEX_DIR/templates/worktree-agent-prompt.md" ]; then
  # Fallback to codex templates
  echo ""
  echo "📤 Sending agent prompt..."
  prompt=$(cat "$CODEX_DIR/templates/worktree-agent-prompt.md")

  if tb_send_multiline_text "$session_id" "$prompt" "true"; then
    echo "   ✅ Prompt sent successfully"
  else
    echo "   ⚠️  Warning: Prompt may not have been sent"
  fi
else
  echo "⚠️  Warning: Agent prompt file not found"
fi

echo "   ✅ Codex launched and configured"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Session spawned successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Session ID:  $session_id"
echo "Worktree:    $WORKTREE_PATH"
echo "Branch:      $BRANCH_NAME"
echo "Agent:       Codex CLI (approval: $CODEX_APPROVAL)"
echo "Backend:     $(tb_get_backend)"
echo ""
echo "💡 Next steps:"
echo "   - Monitor with: \$POLYDEV_SCRIPTS/poll.sh .worktrees 10"
echo "   - Focus with:   \$POLYDEV_SCRIPTS/focus-session.sh $WORKTREE_PATH"
echo "   - Check status: cat $WORKTREE_PATH/task.toon"
echo ""

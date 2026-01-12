#!/bin/bash
# spawn-session.sh - Create worktree + terminal session + start Claude
#
# Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level] [verify_fallback] [verify_commands] [--verbose]
#
# Output (TOON by default):
#   [I] event=session_starting,workspace=...,branch=...,worktree=...
#   [I] event=git_worktree_added,worktree=...
#   [I] event=claude_configured,worktree=...
#   [I] event=task_toon_initialized,path=...
#   [I] event=terminal_session_created,pane_id=...,backend=...
#   [I] event=claude_started,model=...,pane_id=...
#   [I] event=prompt_sent,template=...
#   [I] event=session_ready,pane_id=...,worktree=...,branch=...
#
# Use --verbose for human-readable output
#
# Environment variables:
#   CLAUDE_MODEL - Model to use for sub-agents (default: sonnet)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/terminal-backend.sh"

VERBOSE=false
if [ "$8" = "--verbose" ]; then
  VERBOSE=true
fi

# TOON log function
toon_log() {
  local event="$1"
  shift
  local pairs="$*"
  echo "[I] event=${event}${pairs:+,${pairs}}"
}

toon_error() {
  local msg="$1"
  echo "[E] error=${msg}" >&2
}

# Portable sed -i
sed_inplace() {
  local expr="$1" file="$2"
  local tmp="${file}.tmp.$$"
  local backup="${file}.backup.$$"

  if ! cp "$file" "$backup" 2>/dev/null; then
    toon_error "Cannot create backup of $file"
    return 1
  fi

  if sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"; then
    rm -f "$backup"
    return 0
  else
    mv "$backup" "$file"
    rm -f "$tmp"
    return 1
  fi
}

# Backup task.toon
backup_task_toon() {
  local task_file="$1"
  local backup_dir="$(dirname "$task_file")/.task_backups"

  [ ! -f "$task_file" ] && return 0

  mkdir -p "$backup_dir"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$task_file" "$backup_dir/task.toon.${timestamp}.bak"

  (cd "$backup_dir" && ls -t task.toon.*.bak 2>/dev/null | tail -n +11 | while read f; do rm -f "$f"; done) 2>/dev/null || true
}

WORKSPACE="$1"
BRANCH_NAME="$2"
WORKTREE_PATH="$3"
PLAN_FILE="$4"
VERIFY_LEVEL="${5:-L2}"
VERIFY_FALLBACK="${6:-L1}"
VERIFY_COMMANDS="${7:-}"

CLAUDE_MODEL="${CLAUDE_MODEL:-sonnet}"

if [ -z "$WORKSPACE" ] || [ -z "$BRANCH_NAME" ] || [ -z "$WORKTREE_PATH" ] || [ -z "$PLAN_FILE" ]; then
  toon_error "Missing required arguments"
  echo "Usage: spawn-session.sh <workspace> <branch> <worktree_path> <plan_file> [verify_level] [verify_fallback] [--verbose]" >&2
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  toon_error "Plan file not found: $PLAN_FILE"
  exit 1
fi

if [ -f "$WORKTREE_PATH" ]; then
  toon_error "WORKTREE_PATH is an existing file: $WORKTREE_PATH"
  exit 1
fi

# Validate worktree path
case "$WORKTREE_PATH" in
  .worktrees/*|*/.worktrees/*)
    ;;
  *)
    toon_log "worktree_path_warning" "expected=.worktrees/<branch>,got=$WORKTREE_PATH"
    ;;
esac

WORKTREE_EXISTS=false
[ -d "$WORKTREE_PATH" ] && WORKTREE_EXISTS=true

# Extract verification info from plan file
if [ -z "$VERIFY_COMMANDS" ] && [ -f "$PLAN_FILE" ]; then
  extracted_level=$(grep -A10 "^---" "$PLAN_FILE" | grep "level:" | head -1 | sed 's/.*level: *//' | tr -d ' ')
  [ -n "$extracted_level" ] && VERIFY_LEVEL="$extracted_level"

  extracted_fallback=$(grep -A10 "^---" "$PLAN_FILE" | grep "fallback:" | head -1 | sed 's/.*fallback: *//' | tr -d ' ')
  [ -n "$extracted_fallback" ] && VERIFY_FALLBACK="$extracted_fallback"
fi

if $VERBOSE; then
  echo "Creating Worktree Session..."
  echo "Workspace: $WORKSPACE"
  echo "Branch: $BRANCH_NAME"
  echo "Worktree: $WORKTREE_PATH"
  echo "Verification: $VERIFY_LEVEL (fallback: $VERIFY_FALLBACK)"
  echo "Model: $CLAUDE_MODEL"
  echo "Backend: $(tb_get_backend)"
  echo ""
fi

toon_log "session_starting" "workspace=$WORKSPACE,branch=$BRANCH_NAME,worktree=$WORKTREE_PATH,verify=$VERIFY_LEVEL,model=$CLAUDE_MODEL,backend=$(tb_get_backend)"

if [ "$WORKTREE_EXISTS" = "false" ]; then
  git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null || \
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>/dev/null || exit 1
  toon_log "git_worktree_added" "worktree=$WORKTREE_PATH,branch=$BRANCH_NAME"
fi

if [ ! -d "$WORKTREE_PATH/.claude" ]; then
  mkdir -p "$WORKTREE_PATH/.claude/hooks"
  cp "$ORCHESTRATOR_DIR/templates/claude-settings.json" "$WORKTREE_PATH/.claude/settings.json"
  cp "$ORCHESTRATOR_DIR/hooks/on-stop.sh" "$WORKTREE_PATH/.claude/hooks/"
  cp "$ORCHESTRATOR_DIR/hooks/on-session-start.sh" "$WORKTREE_PATH/.claude/hooks/"
  chmod +x "$WORKTREE_PATH/.claude/hooks/"*.sh 2>/dev/null || true
  toon_log "claude_configured" "worktree=$WORKTREE_PATH"
fi

[ ! -f "$WORKTREE_PATH/PLAN.md" ] && cp "$PLAN_FILE" "$WORKTREE_PATH/PLAN.md"

TASK_FILE="$WORKTREE_PATH/task.toon"
if [ ! -f "$TASK_FILE" ]; then
  CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed -e "s|{{WORKTREE_PATH}}|$WORKTREE_PATH|g" \
      -e "s|{{BRANCH_NAME}}|$BRANCH_NAME|g" \
      -e "s|{{CREATED}}|$CREATED|g" \
      -e "s|{{VERIFY_LEVEL}}|$VERIFY_LEVEL|g" \
      -e "s|{{VERIFY_FALLBACK}}|$VERIFY_FALLBACK|g" \
      -e "s|{{VERIFY_COMMANDS}}|$VERIFY_COMMANDS|g" \
      "$ORCHESTRATOR_DIR/templates/task.toon.template" > "$WORKTREE_PATH/task.toon"
  toon_log "task_toon_initialized" "path=$TASK_FILE"
fi

# Check existing pane_id
existing_pane_id=""
if [ -f "$TASK_FILE" ]; then
  meta_line=$(grep -A1 "^meta{" "$TASK_FILE" 2>/dev/null | tail -1 | tr -d " ")
  existing_pane_id=$(printf "%s" "$meta_line" | cut -d"," -f3)
fi

if [ -n "$existing_pane_id" ] && [ "$existing_pane_id" != "PENDING_PANE_ID" ]; then
  if tb_is_session_alive "$existing_pane_id"; then
    toon_log "session_already_running" "pane_id=$existing_pane_id"
    exit 0
  fi
fi

# Create terminal session (now returns pane_id)
# TAB_NAME uses branch name only; pane_id is appended by terminal-backend.sh
TAB_NAME="$BRANCH_NAME"

pane_id=$(tb_create_worktree_session "$WORKSPACE" "$TAB_NAME" "$WORKTREE_PATH" "$PLAN_FILE")
toon_log "terminal_session_created" "pane_id=$pane_id,backend=$(tb_get_backend)"

# Update pane_id in task.toon
backup_task_toon "$WORKTREE_PATH/task.toon"
if [ -n "$existing_pane_id" ] && [ "$existing_pane_id" != "PENDING_PANE_ID" ]; then
  sed_inplace "s|$existing_pane_id|$pane_id|g" "$TASK_FILE"
else
  sed_inplace "s|PENDING_PANE_ID|$pane_id|" "$TASK_FILE"
fi

# Start Claude (using pane_id directly)
if ! tb_send_command "$pane_id" "claude --dangerously-skip-permissions --model $CLAUDE_MODEL"; then
  toon_error "Failed to start Claude"
  echo "Pane ID: $pane_id" >&2
  exit 1
fi

toon_log "claude_started" "model=$CLAUDE_MODEL,pane_id=$pane_id"

sleep 2

# Send agent prompt (using pane_id directly)
if [ -f "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md" ]; then
  prompt=$(cat "$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md")
  if tb_send_multiline_text "$pane_id" "$prompt" "true"; then
    toon_log "prompt_sent" "template=worktree-agent-prompt.md"
  else
    toon_log "prompt_send_warning" "pane_id=$pane_id"
  fi
else
  toon_log "prompt_template_missing" "expected=$ORCHESTRATOR_DIR/templates/worktree-agent-prompt.md"
fi

toon_log "session_ready" "pane_id=$pane_id,worktree=$WORKTREE_PATH,branch=$BRANCH_NAME"

if $VERBOSE; then
  echo ""
  echo "Session spawned successfully!"
  echo "Pane ID: $pane_id"
  echo "Worktree: $WORKTREE_PATH"
  echo "Branch: $BRANCH_NAME"
  echo ""
  echo "Next: poll.sh .worktrees 10"
fi

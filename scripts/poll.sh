#!/bin/bash
# poll.sh - Poll all worktrees, return when any needs attention
#
# Usage: poll.sh [worktrees_dir] [poll_interval]
#
# Returns CSV: worktree,branch,overall_status,agent_status,last_update,session_id
# Supports both tmux (Linux/macOS) and wezterm (Windows) via terminal-backend.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source terminal backend abstraction
source "$SCRIPT_DIR/terminal-backend.sh"

# Disable set -e from terminal-backend.sh - poll needs to handle errors gracefully
set +e

WORKTREES_DIR="${1:-.worktrees}"
POLL_INTERVAL="${2:-10}"

iteration=0
while true; do
  ((iteration++))

  result=""
  needs_attention=false
  attention_list=""
  summary=""
  worktree_count=0

  for worktree in "$WORKTREES_DIR"/*/; do
    task_file="$worktree/task.toon"
    [ -f "$task_file" ] || continue

    ((worktree_count++))

    # Read status
    overall_status=$(grep "^overall_status:" "$task_file" | cut -d' ' -f2)
    agent_status=$(grep "^agent_status:" "$task_file" | cut -d' ' -f2)
    last_update=$(grep "^last_update:" "$task_file" | cut -d' ' -f2)

    # Parse meta - now uses session_id instead of pane_id
    meta_line=$(grep -A1 "^meta{" "$task_file" | tail -1 | tr -d ' ')
    session_id=$(echo "$meta_line" | cut -d',' -f3)
    branch=$(echo "$meta_line" | cut -d',' -f2)

    # Check session alive using abstraction layer
    if [ -n "$session_id" ] && [ "$session_id" != "PENDING_PANE_ID" ]; then
      if ! tb_is_session_alive "$session_id"; then
        agent_status="crashed"
      fi
    fi

    # Build summary for this branch
    icon="⏳"
    case "$overall_status" in
      in_progress) icon="🔄" ;;
      completed)   icon="✅"; needs_attention=true ;;
      hil)         icon="🙋"; needs_attention=true ;;
      conflict)    icon="⚠️"; needs_attention=true ;;
      rejected)    icon="❌"; needs_attention=true ;;
      blocked)     icon="🚫"; needs_attention=true ;;
      merged)      icon="🎉" ;;
      cleanup_pending) icon="🧹"; needs_attention=true ;;
    esac

    case "$agent_status" in
      idle)    icon="😴"; needs_attention=true ;;
      crashed) icon="💀"; needs_attention=true ;;
    esac

    summary+="$icon $branch($overall_status) "

    # Build detailed attention list
    if $needs_attention; then
      reason=""
      # Read blocking_reason for blocked/hil status (use :- for empty string fallback)
      blocking_reason=$(grep "^blocking_reason:" "$task_file" 2>/dev/null | cut -d' ' -f2- | head -c 50)
      # Trim whitespace
      blocking_reason="${blocking_reason#"${blocking_reason%%[![:space:]]*}"}"

      case "$overall_status" in
        completed) reason="ready for test & merge" ;;
        hil)       reason="${blocking_reason:+$blocking_reason}"; reason="${reason:-needs human input}" ;;
        conflict)  reason="merge conflict" ;;
        rejected)  reason="tests failed, needs fix" ;;
        blocked)   reason="${blocking_reason:+$blocking_reason}"; reason="${reason:-stuck on issue}" ;;
        cleanup_pending) reason="awaiting cleanup confirmation" ;;
      esac
      case "$agent_status" in
        idle)    reason="agent stopped unexpectedly" ;;
        crashed) reason="agent crashed (session $session_id gone)" ;;
      esac
      [ -n "$reason" ] && attention_list+="  $branch: $reason\n"
    fi

    result+="$worktree,$branch,$overall_status,$agent_status,$last_update,$session_id\n"
  done

  if [ $worktree_count -eq 0 ]; then
    echo "❌ No worktrees in $WORKTREES_DIR" >&2
    exit 1
  fi

  # Brief polling summary
  echo -ne "\r[#$iteration] $summary" >&2

  if $needs_attention; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "🔔 Needs attention:" >&2
    echo -e "$attention_list" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo -e "$result"
    exit 0
  fi

  sleep "$POLL_INTERVAL"
done

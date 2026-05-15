#!/bin/bash
# poll.sh - Poll all worktrees, return when any needs attention
#
# Usage: poll.sh [worktrees_dir] [poll_interval] [--verbose]
#
# Output (TOON by default):
#   worktree=/path/to/worktree,branch=feature,overall_status=in_progress,agent_status=active,last_update=2025-01-09T10:30:00Z,pane_id=5
#
# Output (--verbose mode):
#   [#123] [status] branch(status) ...
#   Needs attention:
#     branch: reason

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/terminal-backend.sh"

set +e  # poll needs to handle errors gracefully

WORKTREES_DIR="${1:-.worktrees}"
POLL_INTERVAL="${2:-10}"
VERBOSE=false

if [ "$3" = "--verbose" ]; then
  VERBOSE=true
fi

iteration=0
while true; do
  ((iteration++))

  result=""
  needs_attention=false
  attention_list=""
  summary=""
  worktree_count=0
  workspace_map=""

  # Collect all worktrees and their session info
  for worktree in "$WORKTREES_DIR"/*/; do
    task_file="$worktree/task.toon"
    [ -f "$task_file" ] || continue

    ((worktree_count++))

    # Read status from task.toon
    overall_status=$(grep "^overall_status:" "$task_file" | cut -d' ' -f2)
    agent_status=$(grep "^agent_status:" "$task_file" | cut -d' ' -f2)
    last_update=$(grep "^last_update:" "$task_file" | cut -d' ' -f2)

    # Parse meta - uses pane_id
    meta_line=$(grep -A1 "^meta{" "$task_file" | tail -1 | tr -d ' ')
    pane_id=$(echo "$meta_line" | cut -d',' -f3)
    branch=$(echo "$meta_line" | cut -d',' -f2)
    workspace=$(echo "$meta_line" | cut -d',' -f1)

    # Check session alive using pane_id
    session_alive=false
    if [ -n "$pane_id" ] && [ "$pane_id" != "PENDING_PANE_ID" ]; then
      if tb_is_session_alive "$pane_id" 2>/dev/null; then
        session_alive=true
      else
        agent_status="crashed"
      fi
    fi

    # Build summary
    icon="?"
    case "$overall_status" in
      pending)     icon="." ;;
      in_progress) icon="I" ;;
      completed)   icon="C"; needs_attention=true ;;
      hil)         icon="H"; needs_attention=true ;;
      conflict)    icon="X"; needs_attention=true ;;
      rejected)    icon="R"; needs_attention=true ;;
      blocked)     icon="B"; needs_attention=true ;;
      merged)      icon="M" ;;
      cleanup_pending) icon="P"; needs_attention=true ;;
    esac
    case "$agent_status" in
      pending) icon="." ;;
      idle)    icon="i"; needs_attention=true ;;
      crashed) icon="!"; needs_attention=true ;;
    esac

    [ "$session_alive" = "false" ] && icon="D"

    summary="${summary}${icon}${branch} "

    # Build attention list
    if $needs_attention; then
      reason=""
      blocking_reason=$(grep "^blocking_reason:" "$task_file" 2>/dev/null | cut -d' ' -f2- | head -c 50)
      blocking_reason="${blocking_reason#"${blocking_reason%%[![:space:]]*}"}"

      case "$overall_status" in
        completed) reason="ready for test & merge" ;;
        hil)       reason="${blocking_reason:+$blocking_reason}"; reason="${reason:-needs human input}" ;;
        conflict)  reason="merge conflict" ;;
        rejected)  reason="tests failed" ;;
        blocked)   reason="${blocking_reason:+$blocking_reason}"; reason="${reason:-stuck}" ;;
        cleanup_pending) reason="awaiting cleanup" ;;
      esac
      case "$agent_status" in
        idle)    reason="agent stopped" ;;
        crashed) reason="agent crashed" ;;
      esac
      [ -n "$reason" ] && attention_list="${attention_list}  ${branch}: ${reason}\n"
    fi

    # TOON output line
    worktree_path="${worktree%/}"
    result="${result}worktree=${worktree_path},branch=${branch},overall_status=${overall_status},agent_status=${agent_status},last_update=${last_update},pane_id=${pane_id}\n"
  done

  if [ $worktree_count -eq 0 ]; then
    echo "error=no worktrees in ${WORKTREES_DIR}" >&2
    exit 1
  fi

  # Output polling status (stderr for non-verbose)
  if $VERBOSE; then
    echo "[#${iteration}] ${summary}"
  else
    echo -ne "\r[#${iteration}] ${summary}" >&2
  fi

  if $needs_attention; then
    if ! $VERBOSE; then
      echo "" >&2
    fi
    if $VERBOSE; then
      echo "Needs attention:"
      echo -e "$attention_list"
    fi
    echo -e "$result"
    exit 0
  fi

  sleep "$POLL_INTERVAL"
done

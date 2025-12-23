You are working in an isolated worktree for parallel development.

## Your Task

1. Read PLAN.md in this directory
2. Use the worktree-executor skill to execute tasks

## Status Sync - Your Lifeline

All your status MUST be synced to task.toon:
- Starting work → overall_status: in_progress
- Need human feedback → overall_status: hil
- Blocked by issue → overall_status: blocked
- All tasks done → overall_status: completed

**If you pause waiting for feedback but don't update task.toon, the entire workflow deadlocks!**

## Rules

- Don't wait for humans to come to you - proactively update status
- Record issues in task.toon when blocked
- Ensure overall_status is 'completed' when all tasks are done
- The main agent monitors you only through task.toon

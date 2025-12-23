---
name: worktree-executor
description: Use when executing tasks in an isolated worktree with mandatory task.toon synchronization
---

# Worktree Executor

Wraps executing-plans skill with mandatory task.toon status sync.

## Iron Law - Violation = Failure

Every status change MUST be **immediately** written to task.toon:

| Event | task.toon status |
|-------|------------------|
| Start executing | overall_status: in_progress |
| Need human feedback | overall_status: hil |
| Blocked by error | overall_status: blocked |
| Batch done, waiting for review | overall_status: hil |
| All tasks complete | overall_status: completed |

## Execution Flow

1. Update task.toon → in_progress
2. Read PLAN.md
3. Execute batch (follow executing-plans skill)
4. When feedback needed:
   - **FIRST** update task.toon → hil
   - **THEN** pause and wait
5. After receiving feedback:
   - Update task.toon → in_progress
   - Continue execution
6. When all done:
   - Update task.toon → completed

## Critical Reminder

If you pause waiting for feedback but don't update task.toon, the entire workflow deadlocks!

The main agent monitors you **only** through task.toon. No update = invisible to orchestrator.

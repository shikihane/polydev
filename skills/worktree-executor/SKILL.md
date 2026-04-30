---
name: worktree-executor
description: "Use when an isolated worktree agent must execute PLAN.md, update task.toon, commit changes, and stop for blocked or human-in-the-loop states"
---

# Worktree Executor

This skill is for the agent running inside a Polydev worktree. It is provider-neutral: Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, or another adapter may be the executing agent.

Announce: "I'm executing the plan in this worktree."

## Context

The main agent started this worktree with `spawn-session.sh`.

Do not call Polydev orchestration scripts from inside the worktree. Your responsibilities are:

1. Read `PLAN.md`.
2. Execute tasks exactly.
3. Keep `task.toon` current.
4. Commit completed changes.
5. Stop for `blocked` or `hil` instead of guessing.

## Status Law

Every meaningful state change must be written to `task.toon` immediately.

| Event | task.toon fields |
| --- | --- |
| Start | `overall_status: in_progress`, clear `blocking_reason` |
| Main agent can help | `overall_status: blocked`, `blocking_reason: <why>` |
| Human must decide | `overall_status: hil`, `blocking_reason: <why>` |
| Awaiting review | `overall_status: hil`, `blocking_reason: Awaiting code review` |
| Complete | `overall_status: completed` |

If you pause without updating `task.toon`, the workflow deadlocks.

## Execution Flow

1. Set `overall_status: in_progress`.
2. Read and critique `PLAN.md`.
3. If the plan is ambiguous or unsafe, set `hil` with a precise reason and stop.
4. Execute a small batch of tasks, defaulting to 3 tasks per checkpoint.
5. Run the verification commands required by the plan.
6. Commit changes required by the completed batch.
7. Set `hil` for review checkpoints, or continue if the plan explicitly says no checkpoint is needed.
8. After all tasks, run final verification, commit remaining changes, and set `completed`.

## Blocked vs HIL

| Status | Who resolves | Examples |
| --- | --- | --- |
| `blocked` | main agent or another agent | missing dependency branch, environment issue, failing shared test |
| `hil` | human | credentials, product choice, security approval, ambiguous requirements |

Do not loop endlessly. If the next step is not clear after reasonable local diagnosis, set the right status and stop.

## Completion

Before setting `completed`:

```bash
git status --short
git add -A
git diff --cached --quiet || git commit -m "feat: complete worktree plan"
```

Use the plan's requested commit message if it specifies one. Never leave intended changes uncommitted unless the plan explicitly says so and `task.toon` explains why.

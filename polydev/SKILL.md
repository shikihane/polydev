---
name: polydev
description: Use when coordinating Polydev workflows for parallel worktrees, background terminal tasks, read-only investigations, recurring jobs, or workflow selection in a Windows-first agent setup.
---

# Polydev

Polydev is the single top-level skill. Use the internal references in this folder for the specific workflow.

## Choose the workflow

| Need | Read |
| --- | --- |
| Decide which Polydev flow to use | `references/using-polydev.md` |
| Run parallel worktree sessions | `references/worktree-executor.md` |
| Host long terminal work | `references/terminal-task-runner.md` |
| Run a read-only investigation | `references/agent-investigator.md` |
| Write or revise an implementation plan | `references/writing-plans.md` |
| Schedule recurring or delayed runs | `references/polycron.md` |
| Start or explain the Dashboard/Kanban monitor | `references/kanban.md` |

## Core rules

- Use the full absolute path for every Polydev script.
- Resolve the scripts root once from the installed skill directory for the active runtime, then paste literal full script paths in commands.
- Do not invent usernames or home directories. Derive the scripts root from the loaded skill path or an existing installed directory before running any script.
- For Claude Code runtimes, the scripts root is `.claude/skills/polydev/scripts`; do not use cache-based install paths.
- Only run public root-level entry scripts. Do not execute `terminal-backend.sh`, `terminal-backend.ps1`, files under `scripts/backends/`, or files under `scripts/adapters/` directly; those are implementation helpers.
- Keep provider-specific launch logic inside adapters.
- Treat Windows and WezTerm as first-class.
- Use `task.toon` for session state and terminal capture for diagnosis.
- Follow `references/architecture.md` for the session model and `references/verification-levels.md` for verification scope.

## Safe smoke test

When the user asks to test or check this skill, do a non-destructive smoke test only:

1. State the resolved Polydev scripts root as a literal fact.
2. Verify expected files exist: `SKILL.md`, `scripts/list-sessions.sh`, and the workflow references.
3. If checking runtime behavior, run only a public read-only entry point such as `list-sessions.sh` with a short timeout.
4. If the command hangs or is interrupted, report that exact result and inspect the terminal/backend condition before retrying.

Never test the skill by launching worktree agents, scheduled jobs, cleanup scripts, or internal backend libraries unless the user explicitly asks for that specific action.

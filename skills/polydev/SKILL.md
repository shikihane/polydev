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

## Core rules

- Use the full absolute path for every Polydev script.
- Resolve the scripts root once from the installed skill directory for the active runtime, then paste literal full script paths in commands.
- For Claude Code runtimes, the scripts root is `.claude/skills/polydev/scripts`; do not use cache-based install paths.
- Keep provider-specific launch logic inside adapters.
- Treat Windows and WezTerm as first-class.
- Use `task.toon` for session state and terminal capture for diagnosis.
- Follow `references/architecture.md` for the session model and `references/verification-levels.md` for verification scope.

# CLAUDE.md
This file provides guidance to Claude Code when working in this repository.

## Project Overview

Polydev is an agent orchestration toolkit for parallel development. It uses Git worktrees plus terminal sessions to let multiple coding agents work on independent branches at the same time, with progress coordinated through `task.toon` files.

The design should remain agent-tool neutral. Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and similar coding agents should be able to use the same worktree, terminal, status, and intervention model through thin adapters.

## Core Rules

- Treat `AGENTS.md` as the repo-wide source of truth.
- Use `skills/polydev` for the main skill and workflow references.
- Use full absolute script paths only.
- For Claude Code runtimes, the scripts root is `.claude/skills/polydev/scripts`.
- Do not rely on `$POLYDEV_SCRIPTS` or `$env:POLYDEV_SCRIPTS`.
- Keep provider-specific launch logic inside adapters.
- Keep Windows and WezTerm first-class.

## Common Entry Points

```text
polydev:using-polydev
/polydev-brainstorm
```

## Windows Codex

- Use `start-codex-investigation.ps1` or `start-codex-worktree.ps1`.
- Pass the literal full script path to `pwsh`.
- Use Windows paths and `$env:TEMP`, not `/tmp`, unless Bash is explicitly verified.

## Notes

- Use `task.toon` for session state and terminal capture for diagnosis.
- Follow `skills/polydev/references/architecture.md` for the session model and `skills/polydev/references/verification-levels.md` for verification scope.

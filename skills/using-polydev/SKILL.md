---
name: using-polydev
description: "Use when a user mentions parallel work, multiple independent tasks, worktrees, background commands, long-running sessions, SSH, scheduled agent runs, or Polydev workflow selection"
---

# Using Polydev Skills

Polydev is a Windows-first, agent-neutral orchestration layer for terminal-hosted coding agents. It should work through thin adapters for Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and similar tools.

Use this skill to select the right Polydev workflow before launching sessions or scheduling work.

## Design Rules

- Treat Windows and WezTerm as first-class targets, not compatibility fallback.
- Prefer semi-automation: keep sessions visible, inspectable, interruptible, and recoverable.
- Use Polydev scripts instead of direct tmux/WezTerm commands.
- Call scripts through `$POLYDEV_SCRIPTS`, never `./scripts/...`.
- Keep provider-specific commands, model flags, and environment handling inside adapter scripts.

## Script Path

Use `$POLYDEV_SCRIPTS` for every script call:

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature-auth .worktrees/feature-auth PLAN.md
```

If `$POLYDEV_SCRIPTS` is not set, initialize it from the hook-written path:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
```

On Windows/Git Bash, if a script exits with code 0 but prints no output, use the fallback form:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/list-sessions.sh")"
```

## Skill Selection

| Need | Use |
| --- | --- |
| Complex or unclear parallel request | `/polydev-brainstorm` |
| Detailed task plan or `PLAN.md` | `polydev:writing-plans` |
| 2+ independent implementation branches | `polydev:polydev` |
| Long build, test, server, SSH, REPL | `polydev:terminal-task-runner` |
| Scheduled or recurring agent session | `polydev:polycron` |
| Worktree execution agent | `polydev:worktree-executor` |
| Read-only investigation agent | `polydev:agent-investigator` |

Prefix convention:

- `wo:` worktree development, requires Git, uses `polydev`
- `bg:` background terminal task, no Git required, uses `terminal-task-runner`
- `ag:` investigation agent, no Git required, uses `agent-investigator`

## Script Quick Reference

| Scenario | Script |
| --- | --- |
| Create worktree-backed agent session | `spawn-session.sh <workspace> <branch> <worktree-path> <plan-file>` |
| Monitor worktree status | `poll.sh <worktrees-dir> <timeout>` |
| Restore worktree session | `restore-session.sh <worktree-path> [--force]` |
| Send to worktree session | `wo-send-command.sh <worktree-path> "<cmd>" [--peek N]` |
| Send to any pane | `send-to-session.sh <pane_id> "<cmd>" [--peek N]` |
| Capture screen | `capture-screen.sh <worktree-path>` or `--pane-id <id>` |
| List sessions | `list-sessions.sh [workspace]` |
| Close session | `close-session.sh <worktree-path>` or `--pane-id <id>` |
| Background command | `run-background.sh <name> "<cmd>" [--cwd <dir>] [--peek N]` |
| Claude Code adapter | `spawn-agent.sh <name> --prompt "<task>" --report <path> --cwd <dir>` |
| Codex CLI adapter | `spawn-codex.sh <name> --prompt "<task>" --cwd <dir> [--output <path>]` |
| Gemini CLI adapter | `spawn-gemini.sh <name> --prompt "<task>" --cwd <dir> [--output <path>]` |
| Add scheduled job | `polycron-add.sh <job-id> --schedule "..." --prompt "..." --cwd <dir>` |

Example calls:

```bash
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature-auth .worktrees/feature-auth PLAN.md
"$POLYDEV_SCRIPTS/poll.sh" .worktrees 10
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps" --peek 3
```

## Decision Guide

- User gives 2+ independent code tasks: plan with `writing-plans`, then execute with `polydev`.
- User gives one long command, dev server, test run, SSH, or REPL: use `terminal-task-runner`.
- User asks for read-only research: start an investigation through the available adapter script.
- User asks for a future or recurring run: use `polycron`.
- User wants direct control or a terminal is stuck: use `list-sessions.sh`, `capture-screen.sh`, `send-to-session.sh`, `restore-session.sh`, and `close-session.sh`.

## Cost Controls

Cost controls are adapter-specific. Claude Code `Task` sub-agents should specify `model: "sonnet"` unless the user requests a different model. Do not apply that rule globally to Codex, Cursor, OpenCode, Gemini CLI, or future adapters.

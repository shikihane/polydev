# Polydev Architecture

## Overview

Polydev enables parallel development by orchestrating Git worktrees and terminal sessions. The architecture separates concerns between:

- **Main Agent**: Coordinates work, monitors status, handles blockers
- **Sub-Agents**: Execute tasks in isolated worktrees
- **Terminal Backend**: Abstracts tmux/wezterm differences

## Directory Structure

```
project/
├── .worktrees/              # Git worktrees
│   ├── feature-auth/
│   ├── feature-api/
│   └── feature-ui/
├── PLAN.md                  # Main plan (optional)
├── task.toon                # Status file (main agent only)
└── .agent-reports/          # Investigation reports
```

## Session Types

| Type | Prefix | Git Required | Sub-Claude | Purpose |
|------|--------|--------------|------------|---------|
| Worktree | `wo:` | Yes | Yes | Parallel development |
| Background | `bg:` | No | No | Long-running commands |
| Agent | `ag:` | No | Yes | Read-only research |

## Status Communication

### task.toon Format

```toon
overall_status=in_progress
agent_status=active
blocking_reason=
last_update=2025-01-09T10:30:00Z
session_id=wo:myproject:feature.0
```

### Status Values

**overall_status:**
- `pending` - Assigned, not started
- `in_progress` - Branch agent working
- `completed` - Branch done, awaiting verification
- `blocked` - Needs help (main agent might solve)
- `hil` - Human intervention required
- `merged` - Merge successful

**agent_status:**
- `active` - Claude active
- `idle` - Claude unexpectedly stopped
- `crashed` - Process does not exist

## Terminal Backend

Polydev abstracts terminal session management:

- **Linux/macOS**: Uses tmux with socket at `/tmp/polydev.sock`
- **Windows**: Uses WezTerm

The backend is automatically detected based on the environment.

## Script Reference

| Script | Purpose | Parameters |
|--------|---------|------------|
| `spawn-session.sh` | Create worktree + Claude | `<workspace> <branch> <worktree-path> <plan-file>` |
| `poll.sh` | Monitor status | `<worktrees-dir> <timeout>` |
| `restore-session.sh` | Recover crashed session | `<worktree-path> [--force]` |
| `wo-send-command.sh` | Send to worktree | `<worktree-path> "<cmd>"` |
| `send-to-session.sh` | Send to any session | `<pane_id> "<cmd>"` |
| `capture-screen.sh` | Read output | `--pane-id <id> --lines N` |
| `list-sessions.sh` | List active | `[workspace]` |
| `close-session.sh` | Terminate | `<worktree_path>` or `--pane-id <id>` |
| `run-background.sh` | Background command | `<name> "<cmd>"` |
| `spawn-agent.sh` | Investigation agent | `<name> --prompt "<task>" --report <path>` |

## Cleanup Order

**Critical:** Follow this exact order to avoid "Permission denied" errors:

1. `close-session.sh` - Close terminal (releases directory lock)
2. `list-sessions.sh` - Verify session is gone
3. `git worktree remove` - Delete worktree
4. `git branch -D` - Delete branch (optional)

**Never skip step 1!** Direct `rm -rf` is forbidden.

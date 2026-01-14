# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Polydev is a Claude Code plugin that enables parallel development orchestration using Git worktrees and terminal sessions. It spawns multiple Claude agents to work on independent branches simultaneously, with status tracking via `task.toon` files.

**Cross-platform backends:**
- Linux/macOS: tmux (isolated socket at `/tmp/polydev.sock`)
- Windows: WezTerm

## Architecture

```
polydev/
├── commands/                  # Slash commands
│   └── polydev-brainstorm.md  # /polydev-brainstorm - task decomposition
├── skills/                    # Claude Code skills
│   ├── using-polydev/         # Entry point - skill selection guide
│   ├── polydev/               # Main orchestration skill
│   ├── writing-plans/         # Implementation plan generation
│   ├── worktree-executor/     # Sub-agent execution in worktrees
│   ├── terminal-task-runner/  # Background command hosting
│   └── agent-investigator/    # Read-only investigation agents
├── scripts/                   # Shell scripts (MUST use via $POLYDEV_SCRIPTS)
│   │
│   │ # Core (required for parallel dev)
│   ├── spawn-session.sh       # Create worktree + terminal + Claude (returns pane_id)
│   ├── poll.sh                # Status monitoring loop
│   ├── restore-session.sh     # Session recovery
│   ├── terminal-backend.sh    # Backend abstraction (internal)
│   │
│   │ # Session management
│   ├── wo-send-command.sh     # Send commands to worktree sessions
│   ├── send-to-session.sh     # Send commands to any session (via pane_id)
│   ├── capture-screen.sh      # Read terminal output (via worktree path or --pane-id)
│   ├── list-sessions.sh       # List active sessions
│   ├── close-session.sh       # Terminate sessions (via worktree path or --pane-id)
│   │
│   │ # Background tasks
│   ├── run-background.sh      # Background commands (no sub-Claude, returns pane_id)
│   └── spawn-agent.sh         # Investigation agents (returns pane_id)
│   │
│   │ # Cleanup
│   └── cleanup-worktree.sh    # Clean up worktree + session
├── hooks/                     # Claude Code hooks
└── templates/                 # Task templates
```

## Critical Rules

### Script Path - MANDATORY

**All scripts must be called via `$POLYDEV_SCRIPTS` variable. NEVER use `./scripts/`**

```bash
# Set path variable first
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"

# Then call scripts
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

**Why?** `./scripts/` relative path fails when working outside the plugin directory.

### Workspace Parameter - CRITICAL

**The `workspace` parameter determines window grouping. Same workspace = same window with multiple tabs.**

```bash
# ❌ WRONG - Creates 3 separate windows
spawn-session.sh project-ws1 feature/auth ...
spawn-session.sh project-ws2 feature/api ...
spawn-session.sh project-ws3 feature/ui ...

# ✅ CORRECT - Creates 1 window with 3 tabs
spawn-session.sh my-project feature/auth ...
spawn-session.sh my-project feature/api ...
spawn-session.sh my-project feature/ui ...
```

**Rule:** Use a consistent workspace name (e.g., project name) for all parallel tasks in the same project.

### Script Usage by Scenario

**Core workflow:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Create worktree + Claude | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status (loop) | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |

**Session management:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Send to worktree (has task.toon) | `wo-send-command.sh` | `<worktree-path> "<cmd>"` |
| Send to any session (SSH, REPL) | `send-to-session.sh` | `<pane_id> "<cmd>"` |
| Read screen output | `capture-screen.sh` | `<worktree-path> [--lines N]` or `--pane-id <id>` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<worktree-path>` or `--pane-id <id>` |

**Background tasks:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Start background command | `run-background.sh` | `<name> "<cmd>" [--cwd <dir>]` |
| Start investigation agent | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path>` |

**Cleanup:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Clean up worktree | `cleanup-worktree.sh` | `<worktree-path>` |

### Cost Control

**Parallel sub-agents MUST use `model: "sonnet"`:**

```javascript
// WRONG - inherits expensive model
Task({ prompt: "...", subagent_type: "general-purpose" })

// CORRECT
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })
```

### Status Communication

Sub-agents communicate only via `task.toon` files. Main agent monitors via `poll.sh`.

**Key statuses:**
- `blocked`: Main agent might resolve (dependency, env issue)
- `hil`: Human must decide (credentials, design decisions, ambiguity)

### pane_id Format

pane_id 是主要标识符，格式因后端而异：

| 后端 | pane_id 格式 | 示例 |
|------|-------------|------|
| WezTerm | 数字 | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

**注意**：调试信息输出到 stderr，人类可通过 `[D]` 前缀查看工作树、分支等上下文。

## Development Workflow

1. **Brainstorm** (`/polydev-brainstorm`) - Task decomposition via command
2. **Plan** (`polydev:writing-plans`) - Detailed implementation plans
3. **Execute** (`polydev:polydev`) - Spawn parallel worktrees
4. **Monitor** - Poll loop with `poll.sh`, handle blockers
5. **Verify & Merge** - Per verification level (L0-L5)
6. **Cleanup** - Human confirms before deletion

**Skill selection:** Use `polydev:using-polydev` to determine which skill/command to use.

## Testing Scripts

```bash
# Verify terminal backend
source scripts/terminal-backend.sh
echo "Backend: $(tb_get_backend)"
```

## Verification Levels

| Level | Name | Scope |
|-------|------|-------|
| L0 | skip | No verification (docs, config) |
| L1 | compile | Build only |
| L2 | unit | Build + unit tests |
| L3 | integration | + integration tests |
| L4 | e2e | + end-to-end tests |
| L5 | manual | + human verification |

## Windows Git Bash Notes

- Use `python` not `python3` (detection handled by `terminal-backend.sh`)
- Always quote paths with spaces
- Scripts handle path conversion automatically

## Troubleshooting

### WezTerm Cold Start Timeout

After system boot, WezTerm's mux server may not be fully initialized, causing `wezterm cli list` and other commands to timeout or hang.

**Solution**: Wait a few seconds and retry, or manually open a WezTerm window first to initialize the service.

## Shell Inline Python Escaping

When passing shell variables to inline Python, use environment variables instead of string interpolation to avoid escaping issues with special characters (`/`, `'`, `"`):

```bash
# ✅ Correct - use environment variable
PANE_ID="$pane_id" $PYTHON -c "
import os
pid = os.environ.get('PANE_ID', '')
"

# ❌ Wrong - string interpolation breaks on special chars
$PYTHON -c "if pid == '$pane_id': ..."
```

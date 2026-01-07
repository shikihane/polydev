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
│   ├── terminal-backend.sh    # Backend abstraction (tmux/wezterm)
│   ├── spawn-session.sh       # Create worktree + terminal + Claude
│   ├── poll.sh                # Status monitoring loop
│   ├── restore-session.sh     # Session recovery
│   ├── wo-send-command.sh     # Send commands to worktree sessions (wo: only)
│   ├── send-to-session.sh     # Send commands to any session (SSH, REPL, etc.)
│   ├── capture-screen.sh      # Read terminal output
│   ├── run-background.sh      # Background commands (no sub-Claude)
│   ├── analyze-output.sh      # Analyze background task output
│   ├── wait-for-pattern.sh    # Wait for pattern match in output
│   ├── spawn-agent.sh         # Investigation agents
│   ├── list-sessions.sh       # List active sessions
│   ├── close-session.sh       # Terminate sessions
│   └── prune-dead-sessions.sh # Clean up dead sessions
├── hooks/                     # Claude Code hooks
└── templates/                 # Task templates
```

## Critical Rules

### Script Path - MANDATORY

**All scripts must be called via `$POLYDEV_SCRIPTS` variable. NEVER use `./scripts/`**

```bash
# Set path variable first
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# Then call scripts
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

**Why?** `./scripts/` relative path fails when working outside the plugin directory.

### Script Usage by Scenario

| Scenario | Script | Parameters |
|----------|--------|------------|
| Create worktree + Claude | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status (loop) | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |
| Send to worktree (has task.toon) | `wo-send-command.sh` | `<worktree-path> "<cmd>"` |
| Send to any session (SSH, REPL) | `send-to-session.sh` | `<session_id> "<cmd>"` |
| Read screen output | `capture-screen.sh` | `--session <wo:id> --lines N` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<session_id>` |
| Start background command | `run-background.sh` | `<name> "<cmd>"` |
| Analyze output | `analyze-output.sh` | `<session_id> --lines N` |
| Wait for pattern | `wait-for-pattern.sh` | `<session_id> --success "<pattern>"` |
| Start investigation agent | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path>` |

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

### Session ID Format

```
wo:workspace:branch.0    # Worktree sessions
bg:workspace:name.0      # Background commands
ag:workspace:name.0      # Investigation agents
```

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

# Test session functions
./scripts/test-terminal-backend.sh
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

## Shell Inline Python Escaping

When passing shell variables to inline Python, use environment variables instead of string interpolation to avoid escaping issues with special characters (`/`, `'`, `"`):

```bash
# ✅ Correct - use environment variable
SESSION_ID="$session_id" $PYTHON -c "
import os
sid = os.environ.get('SESSION_ID', '')
"

# ❌ Wrong - string interpolation breaks on special chars
$PYTHON -c "if sid == '$session_id': ..."
```

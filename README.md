# Polydev

**[中文文档](README_CN.md)**

Parallel development orchestration for Claude Code using Git worktrees and terminal sessions.

---

## Why Polydev?

### The Problem with Native Background Tasks

Claude Code's native background tasks and async sub-agents have fundamental limitations:

**1. Cannot Handle Interactive TUI**
- Password prompts (SSH, sudo)
- Configuration interfaces (menuconfig, ncurses)
- Nested Claude Code sessions

**2. Async Sub-agents Are Hard to Monitor and Guide**
- Black-box execution with no real-time visibility
- Humans cannot intervene or correct mid-task
- Difficult to diagnose and recover from errors

**Polydev's Solution:** Use real terminal multiplexers (tmux/WezTerm) to host tasks, providing:
- Full TTY support for any interactive program
- Real-time screen capture to monitor execution status
- Humans can attach to sessions anytime for intervention
- Session recovery from state files after crashes

### Why WezTerm on Windows?

tmux support on Windows is complex and incomplete:
- Requires WSL, Cygwin, or MSYS2 environment
- High performance overhead, path conversion issues
- Difficult integration with native Windows toolchain

**WezTerm** is a better choice:
- Native Windows support, no virtualization layer needed
- Complete CLI control API
- GPU-accelerated rendering, excellent performance
- Cross-platform consistent behavior

### True Parallelism with Git Worktrees

Traditional branch switching is serial—you can only work on one branch at a time. Polydev uses Git Worktrees for true parallelism:

- **Isolated Working Directories**: Each task has its own filesystem space
- **Zero Switching Overhead**: No need for stash, checkout, restore
- **True Parallel Execution**: N Claude agents working on N branches simultaneously
- **Automatic Merging**: Auto-merge back to main branch after task completion
- **Conflict Handling**: Detect and report merge conflicts, support human intervention

### Strict Verification Strategy

Software quality cannot rely on luck. Polydev provides L0-L5 six-level verification strategy to ensure each task meets expected quality standards:

| Level | Use Case | Verification Scope |
|-------|----------|-------------------|
| L0 | Docs, config | No verification |
| L1 | Minor changes | Build passes |
| L2 | Regular features | + Unit tests |
| L3 | Module interactions | + Integration tests |
| L4 | Core workflows | + End-to-end tests |
| L5 | Critical features | + Human verification |

Tasks are automatically assessed for importance and assigned verification levels during decomposition.

### Roadmap

**Episodic Memory System**

Currently, sub-agents sync status via task.toon files, but can only pass "results", not "process". We plan to implement an episodic memory system:

- **Temporal Event Stream**: Record complete timeline of discoveries, hypotheses, decisions, and lessons
- **Cross-agent Knowledge Sharing**: Lessons learned by one agent are shared with others
- **Rule Reflection Mechanism**: Auto-extract rules from recurring issues into project config
- **Experience Crystallization**: Migrate high-value experiences to project docs, forming organizational memory

---

## Overview

Polydev is a Claude Code plugin that enables parallel development by spawning multiple Claude agents to work on independent Git branches simultaneously. Each agent runs in an isolated terminal session (tmux on Linux/macOS, WezTerm on Windows) with real-time status tracking via `task.toon` files.

**Key Features:**
- Parallel execution across multiple Git worktrees
- Cross-platform: tmux (Linux/macOS) or WezTerm (Windows)
- L0-L5 verification levels for automated acceptance
- Background task hosting (builds, tests, SSH sessions)
- Investigation agents for read-only research tasks

## Requirements

| Component | Linux/macOS | Windows |
|-----------|-------------|---------|
| Claude Code CLI | Required | Required |
| Git | >= 2.15 | >= 2.15 |
| Bash | >= 4.0 | Git Bash |
| Terminal | tmux | WezTerm + Python 3 |

## Installation

### From Plugin Marketplace (Recommended)

```bash
# Use HTTPS URL (SSH may fail due to authentication issues)
claude plugin marketplace add https://github.com/shikihane/polydev
claude plugin install polydev
```

### Manual Installation

```bash
# Linux/macOS
mkdir -p ~/.claude/plugins
cp -r /path/to/polydev ~/.claude/plugins/

# Windows (Git Bash)
mkdir -p "$USERPROFILE/.claude/plugins"
cp -r /path/to/polydev "$USERPROFILE/.claude/plugins/"

# Set permissions (Linux/macOS only)
chmod +x ~/.claude/plugins/polydev/plugins/polydev/scripts/*.sh
```

### Verify Installation

```bash
cd ~/.claude/plugins/polydev  # or your install path
source scripts/terminal-backend.sh
echo "Backend: $(tb_get_backend)"
# Expected: tmux (Linux/macOS) or wezterm (Windows)
```

## Usage

### Quick Start

In Claude Code, describe your parallel tasks:

```
I need to implement these features in parallel:
1. User authentication API
2. User profile management
3. Dashboard page

Use polydev to work on these simultaneously.
```

Claude will automatically use the appropriate polydev skills.

### Available Skills

| Skill | Purpose |
|-------|---------|
| `polydev:using-polydev` | Entry point - guides skill selection |
| `polydev:polydev` | Main orchestration for parallel worktrees |
| `polydev:writing-plans` | Generate implementation plans |
| `polydev:terminal-task-runner` | Host background commands (builds, SSH) |
| `polydev:agent-investigator` | Spawn read-only research agents |
| `polydev:worktree-executor` | Sub-agent execution in worktrees |

### Slash Commands

- `/polydev-brainstorm` - Decompose complex tasks into parallel work items

## Workflow

```
User Request
    ↓
1. Analyze & Decompose Tasks
    ↓
2. Assign Verification Levels (L0-L5)
    ↓
3. User Confirms Plan
    ↓
4. Spawn N Worktrees + Claude Sessions
    ↓
5. Monitor via poll.sh
    ↓
6. Verify & Merge (incremental)
    ↓
7. Cleanup (requires confirmation)
```

## Task Status

| Status | Meaning |
|--------|---------|
| `pending` | Assigned, not started |
| `in_progress` | Agent working |
| `completed` | Done, awaiting verification |
| `blocked` | Needs help (main agent may resolve) |
| `hil` | Human-in-loop required |
| `merged` | Successfully merged |

## Manual Script Usage

All scripts must be called via `$POLYDEV_SCRIPTS` variable:

```bash
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"

# Background task
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")

# Send command to session
"$POLYDEV_SCRIPTS/send-to-session.sh" "$session_id" "docker ps"

# Capture output
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 50

# Analyze status
"$POLYDEV_SCRIPTS/analyze-output.sh" "$session_id" --lines 20 --json

# Close session
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

## Session ID Format

```
wo:workspace:branch.0    # Worktree sessions
bg:workspace:name.0      # Background commands
ag:workspace:name.0      # Investigation agents
```

## Troubleshooting

### tmux sessions not found (Linux/macOS)

```bash
tmux -S /tmp/polydev.sock list-sessions
tmux -S /tmp/polydev.sock attach
```

### WezTerm CLI not working (Windows)

Ensure WezTerm is in PATH and Python 3 is installed.

### Session crashed or stuck

```bash
# Auto-detect and recover
./scripts/restore-session.sh .worktrees/your-branch

# Force restart
./scripts/restore-session.sh .worktrees/your-branch --force
```

### Cleanup worktrees

```bash
git worktree list           # List all
git worktree remove <path>  # Remove specific
git worktree prune          # Clean invalid refs
```

## License

MIT License

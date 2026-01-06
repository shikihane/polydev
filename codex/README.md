# Polydev for OpenAI Codex CLI

Parallel development orchestration using Git worktrees and terminal sessions (tmux/wezterm) for OpenAI Codex CLI.

## Overview

This is the Codex CLI version of Polydev. It provides the same parallel development capabilities as the Claude Code version, but adapted for Codex's architecture.

**Key Differences from Claude Code version:**
- No plugin system - skills are installed directly to `~/.codex/skills/`
- No subagents - uses `spawn-session.sh` to launch independent Codex CLI instances
- Scripts are shared between both versions

## Installation

### 1. Install Skills

**Method A: One-line Install (Recommended)**

```bash
git clone https://github.com/shikihane/polydev.git && ./polydev/codex/install.sh
```

**Method B: Using `$skill-installer` in Codex CLI**

```bash
# Install all polydev skills from GitHub
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-plans
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-runner
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-executor
```

**Method C: Manual Copy**

```bash
# Clone the repository
git clone https://github.com/shikihane/polydev.git
cd polydev

# Copy Codex skills
cp -r codex/skills/* ~/.codex/skills/
```

**Method C: Symlinks (for development)**

```bash
git clone https://github.com/anthropics/polydev.git
cd polydev

ln -s "$(pwd)/codex/skills/polydev" ~/.codex/skills/polydev
ln -s "$(pwd)/codex/skills/polydev-plans" ~/.codex/skills/polydev-plans
ln -s "$(pwd)/codex/skills/polydev-runner" ~/.codex/skills/polydev-runner
ln -s "$(pwd)/codex/skills/polydev-executor" ~/.codex/skills/polydev-executor
```

### 2. Set Up Scripts Path

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export POLYDEV_SCRIPTS="$HOME/.codex/polydev/scripts"
```

### 3. Terminal Backend

Polydev requires either tmux (Linux/macOS) or WezTerm (Windows):

**Linux/macOS:**
```bash
# Install tmux
brew install tmux  # macOS
apt install tmux   # Ubuntu/Debian
```

**Windows:**
```bash
# Install WezTerm
winget install wez.wezterm
```

## Available Skills

| Skill | Description | When to Use |
|-------|-------------|-------------|
| `polydev` | Main orchestration skill | When executing 2+ independent tasks in parallel |
| `polydev-plans` | Implementation plan generator | Before parallel execution, create detailed plans |
| `polydev-runner` | Background command runner | Long-running commands (builds, tests, servers) |
| `polydev-executor` | Worktree executor (sub-agent) | Automatically loaded in worktree sessions |

## Usage

### Basic Parallel Development

```
User: Implement feature A, feature B, and fix bug C in parallel

Codex will:
1. Create implementation plans for each task
2. Spawn separate worktrees for each branch
3. Launch independent Codex instances in each worktree
4. Monitor progress via task.toon files
5. Verify and merge completed work
```

### Running Background Commands

```
User: Run the build and let me know when it's done

Codex will:
1. Use polydev-runner skill
2. Start build in background terminal session
3. Monitor output for success/failure patterns
4. Report back when complete
```

## Directory Structure

```
~/.codex/skills/
├── polydev/              # Main orchestration
│   └── SKILL.md
├── polydev-plans/        # Plan generation
│   └── SKILL.md
├── polydev-runner/       # Background commands
│   └── SKILL.md
└── polydev-executor/     # Worktree execution (sub-agent)
    └── SKILL.md
```

## Scripts Reference

All scripts via `$POLYDEV_SCRIPTS`:

```bash
# Create worktree + Codex session
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>

# Monitor all worktrees
"$POLYDEV_SCRIPTS/poll.sh" <worktrees-dir> <timeout>

# Restore crashed session
"$POLYDEV_SCRIPTS/restore-session.sh" <worktree-path> [--force]

# Run background command
"$POLYDEV_SCRIPTS/run-background.sh" <name> "<command>"

# Capture terminal output
"$POLYDEV_SCRIPTS/capture-screen.sh" --session <session_id> --lines <N>

# List/close sessions
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/close-session.sh" <session_id>
```

Environment variable for approval mode:
```bash
CODEX_APPROVAL=full-auto "$POLYDEV_SCRIPTS/spawn-session.sh" ...
```

## Comparison with Claude Code Version

| Feature | Claude Code | Codex CLI |
|---------|-------------|-----------|
| Installation | Plugin marketplace | Manual copy |
| Sub-agents | Task tool | spawn-session.sh |
| Skill invocation | `$skill-name` | Description matching |
| MCP support | STDIO + HTTP | STDIO only |
| Scripts | Shared | Shared |

## Troubleshooting

### Skills not triggering

Codex matches skills based on `description` field. Try:
1. Explicitly mention "parallel" or "multiple tasks"
2. Use `/skills` to manually select
3. Check `~/.codex/skills/` contains the skill directories

### Terminal backend not working

```bash
# Test backend detection
source /path/to/polydev/scripts/terminal-backend.sh
echo "Backend: $(tb_get_backend)"

# Run test script
./scripts/test-terminal-backend.sh
```

### Session not starting

Check that:
1. `$POLYDEV_SCRIPTS` is set correctly
2. Terminal backend (tmux/wezterm) is installed
3. Git is configured for worktrees

## License

MIT License - See LICENSE file in repository root.

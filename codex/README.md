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
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/using-polydev
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-plans
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-runner
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-executor
$skill-installer --url https://github.com/shikihane/polydev/tree/master/codex/skills/polydev-agent
```

**Method C: Manual Copy**

```bash
# Clone the repository
git clone https://github.com/shikihane/polydev.git
cd polydev

# Copy Codex skills
cp -r codex/skills/* ~/.codex/skills/
```

**Method D: Symlinks (for development)**

```bash
git clone https://github.com/shikihane/polydev.git
cd polydev

ln -s "$(pwd)/codex/skills/polydev" ~/.codex/skills/polydev
ln -s "$(pwd)/codex/skills/polydev-plans" ~/.codex/skills/polydev-plans
ln -s "$(pwd)/codex/skills/polydev-runner" ~/.codex/skills/polydev-runner
ln -s "$(pwd)/codex/skills/polydev-executor" ~/.codex/skills/polydev-executor
ln -s "$(pwd)/codex/skills/polydev-agent" ~/.codex/skills/polydev-agent
ln -s "$(pwd)/codex/skills/using-polydev" ~/.codex/skills/using-polydev
```

### 2. Scripts Path

Scripts are installed to `$HOME/.codex/polydev/scripts`. No environment variable setup required - skills reference this path directly.

**Note for Windows users:** See "Windows Usage" section below.

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

| Skill | Session Type | Description |
|-------|:------------:|-------------|
| `using-polydev` | - | Entry point - determines which polydev skill to use |
| `polydev` | `wo:` | Main orchestration (requires git) |
| `polydev-plans` | - | Implementation plan generator |
| `polydev-runner` | `bg:` | Background commands (SSH, builds, tests, servers) |
| `polydev-agent` | `ag:` | Investigation/research sub-agents |
| `polydev-executor` | - | Worktree executor (sub-agent only) |

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
├── using-polydev/        # Entry point - skill selection
│   └── SKILL.md
├── polydev/              # Main orchestration (wo:)
│   └── SKILL.md
├── polydev-plans/        # Plan generation
│   └── SKILL.md
├── polydev-runner/       # Background commands (bg:)
│   └── SKILL.md
├── polydev-agent/        # Investigation agents (ag:)
│   └── SKILL.md
└── polydev-executor/     # Worktree execution (sub-agent)
    └── SKILL.md
```

## Windows Usage (CRITICAL)

**On Windows, you MUST use `bash` to execute `.sh` scripts.** Otherwise Windows will open them in an editor instead of running them.

```powershell
# ❌ WRONG - Windows opens editor
& "$HOME/.codex/polydev/scripts/list-sessions.sh"

# ✅ CORRECT - Use bash prefix
bash "$HOME/.codex/polydev/scripts/list-sessions.sh"
```

All script calls should follow this pattern:
```bash
bash "$HOME/.codex/polydev/scripts/<script-name>.sh" [args...]
```

## Scripts Reference

Scripts location: `$HOME/.codex/polydev/scripts`

**All examples below use Windows format (with `bash` prefix).** On Linux/macOS, you can omit `bash`.

```bash
# Create worktree + Codex session
bash "$HOME/.codex/polydev/scripts/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>

# Monitor all worktrees
bash "$HOME/.codex/polydev/scripts/poll.sh" <worktrees-dir> <timeout>

# Restore crashed session
bash "$HOME/.codex/polydev/scripts/restore-session.sh" <worktree-path> [--force]

# Run background command
bash "$HOME/.codex/polydev/scripts/run-background.sh" <name> "<command>"

# Capture terminal output
bash "$HOME/.codex/polydev/scripts/capture-screen.sh" --session <session_id> --lines <N>

# List/close sessions
bash "$HOME/.codex/polydev/scripts/list-sessions.sh"
bash "$HOME/.codex/polydev/scripts/close-session.sh" <session_id>
```

Environment variable for approval mode:
```bash
CODEX_APPROVAL=full-auto bash "$HOME/.codex/polydev/scripts/spawn-session.sh" ...
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

### Windows: Script opens in editor instead of running

**This is the most common issue on Windows.** You MUST use `bash` prefix:

```bash
# ❌ WRONG
"$HOME/.codex/polydev/scripts/list-sessions.sh"

# ✅ CORRECT
bash "$HOME/.codex/polydev/scripts/list-sessions.sh"
```

### Terminal backend not working

```bash
# Test backend detection (in Git Bash)
source "$HOME/.codex/polydev/scripts/terminal-backend.sh"
echo "Backend: $(tb_get_backend)"
```

### Session not starting

Check that:
1. You're using `bash` prefix on Windows
2. Terminal backend (tmux/wezterm) is installed
3. Git is configured for worktrees

## License

MIT License - See LICENSE file in repository root.

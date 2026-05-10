# Polydev

Polydev is an agent orchestration toolkit for running parallel development work with Git worktrees and terminal-hosted coding agents. It helps split a larger task into independent branches, launch agents in isolated terminals, monitor their status, and clean up the resulting worktrees when the work is complete.

## Design Point Of View

Polydev is Windows-first. Linux/macOS support is included, but this project intentionally gives Windows and WezTerm first-class attention because most parallel agent tooling is built around Unix-like environments.

Polydev is semi-automated, not a sealed autopilot. It automates the repetitive parts of orchestration while keeping terminal sessions visible, inspectable, and interruptible. A human can step in to send commands, handle `hil` decisions, recover sessions, or stop work when context changes.

Polydev should not be tied to one coding agent. The same orchestration model should be usable from Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and other agent tools through thin adapters.

## What It Provides

- Parallel agent execution across Git worktrees
- Terminal session management for tmux on Linux/macOS and WezTerm on Windows
- `task.toon` status files for agent-to-main coordination
- Background command hosting for builds, tests, servers, and one-off agent investigations
- Scheduled agent tasks through Polycron
- Agent workflow instructions and command entry points for planning, execution, and monitoring

## Requirements

- Git
- At least one supported coding agent, such as Codex CLI, Cursor, OpenCode, Claude Code, or Gemini CLI
- tmux on Linux/macOS, or WezTerm on Windows
- Bash-compatible shell for the scripts
- PowerShell 7 (`pwsh`) for Windows-native Codex adapter scripts

## Repository Layout

```text
commands/     Agent command entry points
skills/       Agent workflow instructions for orchestration, planning, and execution
scripts/      Stable script entry points plus provider adapters and terminal backends
hooks/        Tool-specific hook integration
templates/    Task and workflow templates
docs/         Supporting documentation
```

Provider-specific and platform-specific implementation files live below `scripts/adapters/` and `scripts/backends/`. Root-level scripts remain stable wrappers so existing `$POLYDEV_SCRIPTS\...` and `$POLYDEV_SCRIPTS/...` commands keep working.

## Getting Started

Install or load this repository through the integration for your coding agent, then use the Polydev entry workflow to choose the right path:

```text
polydev:using-polydev
```

For task decomposition, start with:

```text
/polydev-brainstorm
```

Polydev scripts are normally discovered by the plugin hook and exposed through:

```bash
$POLYDEV_SCRIPTS
```

Call scripts through that variable:

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

On Windows PowerShell, call Windows-native Codex adapter scripts through `$env:POLYDEV_SCRIPTS`:

```powershell
$env:POLYDEV_SCRIPTS = "E:\Heyang3\polydev\scripts"
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" research -Prompt "Inspect the auth flow." -Cwd .
```

## Typical Workflow

1. Decompose the work with `/polydev-brainstorm`.
2. Write implementation plans with `polydev:writing-plans`.
3. Launch parallel worktrees with `polydev:polydev`.
4. Monitor status using `poll.sh`.
5. Resolve `blocked` and `hil` statuses as needed.
6. Verify each branch at the required level.
7. Merge or preserve completed work, then clean up worktrees.

## Common Scripts

Bash scripts should be called through `$POLYDEV_SCRIPTS`.

```bash
# List active terminal sessions
"$POLYDEV_SCRIPTS/list-sessions.sh"

# Spawn a worktree-backed agent session
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/auth ../worktrees/auth plan.md

# Monitor worktree task status
"$POLYDEV_SCRIPTS/poll.sh" ../worktrees 1800

# Send a command to an existing session
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "npm test" --peek 5

# Capture terminal output
"$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id 5 --lines 80

# Clean up a worktree and session
"$POLYDEV_SCRIPTS/cleanup-worktree.sh" ../worktrees/auth
```

## Provider Adapters

| Provider | Purpose | Stable Entry Point | Implementation |
| --- | --- | --- | --- |
| Claude Code | Existing bash investigation/worktree launchers | `spawn-agent.sh`, `spawn-session.sh` | bash adapter scripts |
| Codex CLI | Windows PowerShell investigation session | `start-codex-investigation.ps1` | `scripts/adapters/codex/windows/start-investigation.ps1` |
| Codex CLI | Windows PowerShell worktree session | `start-codex-worktree.ps1` | `scripts/adapters/codex/windows/start-worktree.ps1` |
| Gemini CLI | Existing bash investigation launcher | `spawn-gemini.sh` | bash adapter script |

Windows Codex PowerShell examples:

```powershell
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" research -Prompt "Inspect repository only." -Cwd .
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" my-project codex/auth .worktrees/codex-auth docs/plans/auth.md
```

The Codex PowerShell adapter defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use `-DangerousBypass` only for explicitly approved unattended runs.

## Background Tasks

Use background sessions for long-running commands, local servers, test watchers, and read-only investigations:

```bash
"$POLYDEV_SCRIPTS/run-background.sh" tests "npm test" --cwd /path/to/project --peek 10

"$POLYDEV_SCRIPTS/spawn-agent.sh" investigator \
  --prompt "Investigate the failing auth tests and write a report." \
  --report /tmp/auth-investigation.md \
  --cwd /path/to/project \
  --peek 5
```

## Scheduled Tasks

Polycron lets you schedule agent sessions through the operating system scheduler.

```bash
"$POLYDEV_SCRIPTS/polycron-add.sh" daily-report \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report" \
  --cwd /path/to/project

"$POLYDEV_SCRIPTS/polycron-list.sh"
"$POLYDEV_SCRIPTS/polycron-history.sh" --last 10
"$POLYDEV_SCRIPTS/polycron-remove.sh" daily-report
```

Polycron stores job definitions and history under `~/.polydev/cron/`.

## Verification Levels

| Level | Name | Scope |
| --- | --- | --- |
| L0 | skip | Docs or config only |
| L1 | compile | Build only |
| L2 | unit | Build plus unit tests |
| L3 | integration | Integration tests |
| L4 | e2e | End-to-end tests |
| L5 | manual | Human verification |

## Windows Notes

On Windows, Polydev uses WezTerm as the terminal backend. If a script exits successfully but prints no output in Git Bash, use the fallback form:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/list-sessions.sh")"
```

After a fresh boot, WezTerm's mux server may need a few seconds to initialize. Retry the command or open a WezTerm window once before launching sessions.

## Agent Guidance

Agent-agnostic operating rules live in `AGENTS.md`. Claude Code-specific guidance remains in `CLAUDE.md` as one integration layer, not the product definition.

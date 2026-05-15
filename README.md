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
polydev/      Installable Polydev skill package; copy this directory to the skill root
  SKILL.md    Top-level skill entry point
  references/ Workflow and architecture references
  scripts/    Stable script entry points plus provider adapters and terminal backends
  dashboard/  Skill-carried web dashboard for monitoring sessions and task state
  templates/  Task and workflow templates
  commands/   Agent command entry points
docs/         Supporting documentation
tests/        Regression tests for the package
```

Provider-specific and platform-specific implementation files live below `polydev/scripts/adapters/` and `polydev/scripts/backends/` in this repository, and below `scripts/adapters/` and `scripts/backends/` after installation. Root-level scripts remain stable wrappers, but user-facing commands should call those wrappers by full absolute script path.

## Getting Started

Install or load Polydev through the integration for your coding agent. Use the entry workflow to choose the right orchestration path:

```text
polydev -> references/using-polydev.md
```

For task decomposition, start with:

```text
/polydev-brainstorm
```

### Script Path

Polydev scripts must be loaded from the installed skill directory, not from a user-global path file or a repository checkout. Resolve the Polydev scripts root once per agent session and keep that root as a literal fact in the agent prompt/context. Every script command must then use the full absolute script path by appending the script filename to that resolved root.

For Claude Code, the installed path is the Claude skill directory. D2 and D4 must resolve to `.claude/skills/polydev/scripts`; do not substitute a repository checkout path, `.claudecode`, or any cache-based install path.

Initial resolution is runtime-specific:

```text
D1 Windows Codex: C:\Users\<user>\.codex\polydev\scripts
D2 Windows Claude Code: /c/Users/<user>/.claude/skills/polydev/scripts
D3 Linux/macOS Codex: /home/<user>/.codex/polydev/scripts
D4 Linux/macOS Claude Code: /home/<user>/.claude/skills/polydev/scripts
```

Do not use script-root environment variables, shell profiles, inherited process environments, or repository-relative `./polydev/scripts/...` / `./scripts/...` paths as the script path mechanism.

D1 PowerShell callers use the complete `.ps1` path:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-investigation.ps1" research -Prompt "Inspect the auth flow." -Cwd .
```

When launching a Windows PowerShell adapter from Bash, pass a Bash-form full absolute path to `pwsh`.

```bash
pwsh -NoProfile -File "/c/Users/<user>/.codex/polydev/scripts/start-codex-investigation.ps1" research -Prompt "Inspect the auth flow." -Cwd .
```

## Typical Workflow

1. Decompose the work with `/polydev-brainstorm`.
2. Write implementation plans with `polydev` with `references/writing-plans.md`.
3. Launch parallel worktrees with `polydev` with `references/worktree-executor.md`.
4. Monitor status using `poll.sh`.
5. Resolve `blocked` and `hil` statuses as needed.
6. Verify each branch at the required level.
7. Merge or preserve completed work, then clean up worktrees.

## Common Scripts

Bash scripts should be called with the full absolute script path.

```bash
# List active terminal sessions
"/c/Users/<user>/.claude/skills/polydev/scripts/list-sessions.sh"

# Spawn a worktree-backed agent session
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature/auth ../worktrees/auth plan.md

# Monitor worktree task status
"/c/Users/<user>/.claude/skills/polydev/scripts/poll.sh" ../worktrees 1800

# Send a command to an existing session
"/c/Users/<user>/.claude/skills/polydev/scripts/send-to-session.sh" 5 "npm test" --peek 5

# Capture terminal output
"/c/Users/<user>/.claude/skills/polydev/scripts/capture-screen.sh" --pane-id 5 --lines 80

# Clean up a worktree and session
"/c/Users/<user>/.claude/skills/polydev/scripts/cleanup-worktree.sh" ../worktrees/auth
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
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-investigation.ps1" research -Prompt "Inspect repository only." -Cwd .
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-worktree.ps1" my-project codex/auth .worktrees\codex-auth docs\plans\auth.md
```

Bash callers should still use Bash path syntax when launching a PowerShell adapter:

```bash
pwsh -NoProfile -File "/c/Users/<user>/.codex/polydev/scripts/start-codex-investigation.ps1" research -Prompt "Inspect repository only." -Cwd .
```

The Codex PowerShell adapter defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use `-DangerousBypass` only for explicitly approved unattended runs.

## Background Tasks

Use background sessions for long-running commands, local servers, test watchers, and read-only investigations:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" tests "npm test" --cwd /path/to/project --peek 10

"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" investigator \
  --prompt "Investigate the failing auth tests and write a report." \
  --report /tmp/auth-investigation.md \
  --cwd /path/to/project \
  --peek 5
```

## Scheduled Tasks

Polycron lets you schedule agent sessions through the operating system scheduler.

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-add.sh" daily-report \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report" \
  --cwd /path/to/project

"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-list.sh"
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-history.sh" --last 10
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-remove.sh" daily-report
```

Polycron stores job definitions and history under `~/.polydev/cron/`.

## Dashboard

The dashboard is packaged beside `scripts/` in the installed Polydev skill directory:

```text
<polydev-skill-root>/
├── scripts/
└── dashboard/
```

It monitors an explicit project root instead of inferring the project from the dashboard server's current directory. Manage Node dependencies and frontend builds in the dashboard directory:

```bash
cd /path/to/polydev/dashboard
npm install
npm run build
POLYDEV_PROJECT_ROOT=/path/to/project node server/index.js
```

The Bash wrapper keeps npm operations inside the dashboard directory and passes the monitored project through `POLYDEV_PROJECT_ROOT`:

```bash
"/path/to/polydev/scripts/dashboard.sh" --cwd /path/to/project --port 3120
```

D1 Windows Codex users can start it directly from PowerShell:

```powershell
Set-Location "C:\Users\<user>\.codex\polydev\dashboard"
npm install
npm run build
$env:POLYDEV_PROJECT_ROOT = "E:\repo"
node server/index.js
```

The v1 dashboard is for monitoring session/task state and closing panes. Sending commands, focusing panes, restoring sessions from the UI, and Polycron views are future control-plane features.

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

On Windows, Polydev uses WezTerm as the terminal backend. If a direct full-path script call exits successfully but prints no output in Git Bash, use the fallback form with the same full script path:

```bash
bash -c "$(cat "/c/Users/<user>/.claude/skills/polydev/scripts/list-sessions.sh")"
```

After a fresh boot, WezTerm's mux server may need a few seconds to initialize. Retry the command or open a WezTerm window once before launching sessions.

## Agent Guidance

Agent-agnostic operating rules live in `AGENTS.md`. Claude Code-specific guidance remains in `CLAUDE.md` as one integration layer, not the product definition.

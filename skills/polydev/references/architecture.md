# Polydev Architecture

Polydev orchestrates Git worktrees and terminal-hosted coding agents. The core model is agent-neutral and should stay usable from Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and future adapters.

## Design Principles

- Windows-first: WezTerm on Windows is a first-class path.
- Semi-automated: sessions remain visible, inspectable, interruptible, and recoverable.
- Adapter boundary: provider-specific launch commands, model flags, prompt wrappers, and environment variables stay in launcher scripts.
- Script invocation is always by full absolute script path.

## Session Types

| Type | Prefix | Git required | Agent process | Purpose |
| --- | --- | --- | --- | --- |
| Worktree | `wo:` | yes | yes | Parallel implementation |
| Background | `bg:` | no | no | Long-running commands, SSH, REPLs |
| Investigation | `ag:` | no | yes | Read-only research and reports |

## Status Communication

Worktree sessions communicate through `task.toon`:

```toon
overall_status=in_progress
agent_status=active
blocking_reason=
last_update=2026-04-30T10:30:00Z
session_id=wo:myproject:feature.0
pane_id=5
```

`overall_status` values:

- `pending`: assigned, not started
- `in_progress`: branch agent working
- `completed`: branch done, awaiting verification
- `blocked`: main agent may resolve
- `hil`: human intervention required
- `merged`: merge successful

`agent_status` values:

- `active`: agent process appears active
- `idle`: agent unexpectedly stopped
- `crashed`: process no longer exists

## Terminal Backend

| Platform | Backend | Notes |
| --- | --- | --- |
| Windows | WezTerm | First-class target; pane ids are numeric |
| Linux/macOS | tmux | Uses isolated socket at `/tmp/polydev.sock` |

Windows Codex launchers use native PowerShell 7 plus WezTerm and do not require Git Bash for session creation. Existing bash scripts still use the shared backend abstraction.

Root-level scripts are stable public entry points. Provider-specific implementations live under `scripts/adapters/`, and platform terminal helpers live under `scripts/backends/`.

## Dashboard Packaging

The web dashboard travels with the installed Polydev skill directory as a sibling of `scripts/`:

```text
<polydev-skill-root>/
├── scripts/
└── dashboard/
```

The dashboard server resolves its skill-local script root from `dashboard/../scripts`. The project being monitored is configured separately with `POLYDEV_PROJECT_ROOT`, `--cwd`, or the API query root. This keeps D1/D2 Windows WezTerm behavior and D3/D4 tmux behavior behind their existing backend-specific code instead of inferring project paths from the server working directory.

Manual startup:

```bash
cd /path/to/polydev/dashboard
npm install
npm run build
POLYDEV_PROJECT_ROOT=/path/to/project node server/index.js
```

Wrapper startup:

```bash
"/path/to/polydev/scripts/dashboard.sh" --cwd /path/to/project --port 3120
```

D1 Windows PowerShell startup:

```powershell
Set-Location "C:\Users\<user>\.codex\polydev\dashboard"
npm install
npm run build
$env:POLYDEV_PROJECT_ROOT = "E:\repo"
node server/index.js
```

The v1 dashboard is monitor/read/close only. Command sending, pane focusing, session restore, and Polycron history are follow-up control-plane features.

## Provider Adapter Matrix

| Provider | Investigation | Worktree | Implementation | Notes |
| --- | --- | --- | --- | --- |
| Claude Code | `spawn-agent.sh` | `spawn-session.sh` | bash adapter scripts | Claude-specific model/env handling stays in adapter |
| Codex CLI | `start-codex-investigation.ps1` | `start-codex-worktree.ps1` | `adapters/codex/windows/` | Windows PowerShell path; prompt-file handoff |
| Gemini CLI | `spawn-gemini.sh` | future adapter | bash adapter script | Existing investigation path |

Codex PowerShell defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use dangerous bypass only when a human explicitly requests unattended execution.

## Script Reference

Resolve the Polydev scripts root once when first needed, keep that resolved directory as prompt/context text, and call every script by full absolute path. Do not rely on script-root environment variables, shell profiles, inherited process environments, `./scripts/...`, or repository-relative paths.

For Claude Code runtimes, the resolved scripts root must be the installed Claude skill directory: `/c/Users/<user>/.claude/skills/polydev/scripts` on Windows Git Bash or `/home/<user>/.claude/skills/polydev/scripts` on Linux/macOS. Do not use a repository checkout, `.claudecode`, or any cache-based install path.

For PowerShell scripts on Windows:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-investigation.ps1" research -Prompt "..." -Cwd .
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-worktree.ps1" myproject codex-auth .worktrees\codex-auth docs\plans\auth.md
```

When the caller shell is Bash, pass a Bash-form full absolute path:

```bash
pwsh -NoProfile -File "/c/Users/<user>/.codex/polydev/scripts/start-codex-investigation.ps1" research -Prompt "..." -Cwd .
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" myproject feature-auth .worktrees/feature-auth docs/plans/auth.md
```

For Bash-launched PowerShell adapters, keep the command simple and literal: pass the full adapter path to `pwsh -File` and use the documented public parameters only. If the caller's current directory matters, run the command from that directory or pass an absolute `-Cwd` path.

| Script | Purpose | Parameters |
| --- | --- | --- |
| `spawn-session.sh` | Create worktree-backed agent session | `<workspace> <branch> <worktree-path> <plan-file>` |
| `start-codex-worktree.ps1` | Create Windows Codex worktree session | `<workspace> <branch> <worktree-path> <plan-file>` |
| `poll.sh` | Monitor worktree status | `<worktrees-dir> <timeout>` |
| `restore-session.sh` | Recover worktree session | `<worktree-path> [--force]` |
| `restore-codex-worktree.ps1` | Recover Windows Codex worktree session | `<worktree-path> [-Force]` |
| `wo-send-command.sh` | Send to worktree session | `<worktree-path> "<cmd>" [--peek N]` |
| `send-to-session.sh` | Send to any pane | `<pane_id> "<cmd>" [--peek N]` |
| `capture-screen.sh` | Read terminal output | `<worktree-path>` or `--pane-id <id>` |
| `list-sessions.sh` | List sessions | `[workspace]` |
| `close-session.sh` | Terminate session | `<worktree_path>` or `--pane-id <id>` |
| `run-background.sh` | Background command | `<name> "<cmd>" [--cwd <dir>]` |
| `spawn-agent.sh` | Claude Code adapter | `<name> --prompt "<task>" --report <path> --cwd <dir>` |
| `spawn-codex.sh` | Codex CLI adapter | `<name> --prompt "<task>" --cwd <dir> [--model <name>] [--output <path>]` |
| `start-codex-investigation.ps1` | Windows Codex investigation adapter | `<name> -Prompt "<task>" -Cwd <dir> [-Output <path>]` |
| `spawn-gemini.sh` | Gemini CLI adapter | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |

## Recovery and Cleanup

Use `capture-screen.sh` to inspect, `restore-session.sh` to recover worktree sessions, and `send-to-session.sh` or `wo-send-command.sh` to intervene.

Cleanup order:

1. `close-session.sh`
2. `list-sessions.sh` to verify closure
3. `git worktree remove`
4. `git worktree prune`
5. Optional branch deletion after human confirmation

Never remove `.worktrees/...` with direct filesystem deletion.

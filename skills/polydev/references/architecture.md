# Polydev Architecture

Polydev orchestrates Git worktrees and terminal-hosted coding agents. The core model is agent-neutral and should stay usable from Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and future adapters.

## Design Principles

- Windows-first: WezTerm on Windows is a first-class path.
- Semi-automated: sessions remain visible, inspectable, interruptible, and recoverable.
- Adapter boundary: provider-specific launch commands, model flags, prompt wrappers, and environment variables stay in launcher scripts.

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

## Provider Adapter Matrix

| Provider | Investigation | Worktree | Notes |
| --- | --- | --- | --- |
| Claude Code | `spawn-agent.sh` | `spawn-session.sh` | Existing bash path; Claude-specific model/env handling stays in adapter |
| Codex CLI | `start-codex-investigation.ps1` | `start-codex-worktree.ps1` | Windows PowerShell path; prompt-file handoff; no hook emulation |
| Gemini CLI | `spawn-gemini.sh` | future adapter | Existing investigation path |

Codex PowerShell defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use dangerous bypass only when a human explicitly requests unattended execution.

## Script Reference

Call every bash script through `$POLYDEV_SCRIPTS`.

For PowerShell scripts on Windows, use `$env:POLYDEV_SCRIPTS`:

```powershell
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" research -Prompt "..." -Cwd .
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" myproject codex-auth .worktrees/codex-auth docs/plans/auth.md
```

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
| `spawn-codex.sh` | Codex CLI adapter | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |
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

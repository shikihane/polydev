# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project Overview

Polydev is an agent orchestration toolkit for parallel development. It uses Git worktrees plus terminal sessions to let multiple coding agents work on independent branches at the same time, with progress coordinated through `task.toon` files.

The design should remain agent-tool neutral. Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and similar coding agents should be able to use the same worktree, terminal, status, and intervention model through thin adapters.

Cross-platform terminal backends:

- Linux/macOS: tmux, using an isolated socket at `/tmp/polydev.sock`
- Windows: WezTerm

## Design Principles

Polydev is Windows-first. Linux/macOS support matters, but many agent orchestration tools already assume Unix-like terminals; this project should treat Windows and WezTerm as first-class design targets rather than compatibility afterthoughts.

Polydev is semi-automated and human-intervenable. It should automate repetitive orchestration, session handling, polling, and scheduling, while keeping the human able to inspect terminal state, send commands, resolve `hil` decisions, recover sessions, and stop or redirect work.

Avoid designing opaque full automation. Prefer workflows that expose state, make intervention cheap, and leave clear recovery paths.

Avoid baking one agent vendor into core concepts. Keep provider-specific launch commands, model flags, environment variables, and prompt wrappers at the adapter/script boundary.

## Repository Layout

```text
polydev/
├── commands/                  # Agent command entry points
│   └── polydev-brainstorm.md  # /polydev-brainstorm task decomposition
├── skills/                    # Agent workflow instructions
│   ├── using-polydev/         # Entry point and skill selection guide
│   ├── polydev/               # Main orchestration skill
│   ├── writing-plans/         # Implementation plan generation
│   ├── worktree-executor/     # Sub-agent execution in worktrees
│   ├── terminal-task-runner/  # Background command hosting
│   ├── polycron/              # Scheduled task automation
│   └── agent-investigator/    # Read-only investigation agents
├── scripts/                   # Runtime scripts; call through $POLYDEV_SCRIPTS
├── hooks/                     # Tool-specific hook integration
└── templates/                 # Task templates
```

## Critical Rules

### Script Path

Always call scripts through `$POLYDEV_SCRIPTS`.

Do not call scripts with `./scripts/...` in agent instructions, examples, or implementation code unless you are explicitly testing path discovery itself. Bash scripts use `$POLYDEV_SCRIPTS`; Windows-native PowerShell scripts use `$env:POLYDEV_SCRIPTS` with `pwsh`.

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/auth ../worktrees/auth plan.md
```

```powershell
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" research -Prompt "Inspect repository only." -Cwd .
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" my-project codex/auth .worktrees/codex-auth docs/plans/auth.md
```

On Windows/Git Bash, if a script silently exits with code 0 and no output, use the fallback pattern:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/list-sessions.sh")"
```

If `~/.polydev/scripts-path` does not exist, the hook has not initialized the path. Set it from the plugin root:

```bash
POLYDEV_SCRIPTS="$CLAUDE_PLUGIN_ROOT/scripts"
```

### Workspace Names

The `workspace` parameter controls terminal window grouping. Use one consistent workspace name for parallel tasks in the same project.

```bash
# Correct: one workspace, multiple tabs
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/auth ...
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/api ...
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/ui ...
```

Different workspace names create separate windows.

### Tool-Specific Cost Control

Do not make cost-control rules globally vendor-specific. Put model choices and pricing safeguards in the adapter that launches a given agent.

Claude Code `Task` sub-agents should use `model: "sonnet"` unless the user explicitly requests otherwise. Add equivalent cost controls beside each future adapter instead of making this a core Polydev rule.

```javascript
Task({
  prompt: "...",
  subagent_type: "general-purpose",
  model: "sonnet"
})
```

### Provider Adapter Boundary

| Provider | Investigation | Worktree |
| --- | --- | --- |
| Claude Code | `spawn-agent.sh` | `spawn-session.sh` |
| Codex CLI on Windows | `start-codex-investigation.ps1` | `start-codex-worktree.ps1` |
| Gemini CLI | `spawn-gemini.sh` | future adapter |

The Codex PowerShell adapter defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use `-DangerousBypass` only when the human explicitly requests a fully unattended run. Do not add Codex hook emulation; status is initialized by the launcher and then maintained through explicit `task.toon` updates.

### Status Communication

Sub-agents communicate through `task.toon` files. The main agent monitors with `poll.sh`.

Important statuses:

- `blocked`: main agent may be able to resolve the issue
- `hil`: human-in-the-loop decision required

### Pane IDs

`pane_id` is the primary terminal session identifier.

| Backend | Format | Example |
| --- | --- | --- |
| WezTerm | numeric | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

Debug output goes to stderr and may include `[D]` prefixes with worktree, branch, or pane context.

## Script Reference

All scripts below must be invoked via `$POLYDEV_SCRIPTS`.

### Core Workflow

| Scenario | Script | Parameters |
| --- | --- | --- |
| Create worktree-backed agent session | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Create Codex worktree session on Windows | `start-codex-worktree.ps1` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status loop | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |
| Restore Codex worktree session on Windows | `restore-codex-worktree.ps1` | `<worktree-path> [-Force]` |

### Session Management

| Scenario | Script | Parameters |
| --- | --- | --- |
| Send to worktree session | `wo-send-command.sh` | `<worktree-path> "<cmd>" [--peek N]` |
| Send to any session | `send-to-session.sh` | `<pane_id> "<cmd>" [--peek N]` |
| Read terminal output | `capture-screen.sh` | `<worktree-path> [--lines N]` or `--pane-id <id>` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<worktree-path>` or `--pane-id <id>` |

### Background Tasks

| Scenario | Script | Parameters |
| --- | --- | --- |
| Start background command | `run-background.sh` | `<name> "<cmd>" [--cwd <dir>] [--peek N]` |
| Start Claude Code session | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path> --cwd <dir> [--peek N]` |
| Start Codex CLI session | `spawn-codex.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |
| Start Codex CLI session on Windows | `start-codex-investigation.ps1` | `<name> -Prompt "<task>" -Cwd <dir> [-Output <path>]` |
| Start Gemini CLI session | `spawn-gemini.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |

### Scheduled Tasks

| Scenario | Script | Parameters |
| --- | --- | --- |
| Add scheduled task | `polycron-add.sh` | `<job-id> --schedule "..." --prompt "..." --cwd <dir>` |
| Remove scheduled task | `polycron-remove.sh` | `<job-id>` |
| List scheduled tasks | `polycron-list.sh` | `[--all|--enabled|--disabled]` |
| View task history | `polycron-history.sh` | `[job-id] [--last N]` |

### Cleanup

| Scenario | Script | Parameters |
| --- | --- | --- |
| Clean worktree + session | `cleanup-worktree.sh` | `<worktree-path>` |

### `--peek`

Scripts that return a `pane_id` support `--peek N`.

- `--peek 0`: capture immediately
- `--peek 5`: wait 5 seconds, then capture
- omitted: do not capture

```bash
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps" --peek 3
"$POLYDEV_SCRIPTS/run-background.sh" build "npm test" --peek 10
```

## Development Workflow

1. Brainstorm with `/polydev-brainstorm` for task decomposition.
2. Plan with `polydev:writing-plans`.
3. Execute with `polydev:polydev`.
4. Monitor with `poll.sh` and handle `blocked` or `hil` states.
5. Verify according to the selected verification level.
6. Clean up worktrees only after human confirmation.

Use `polydev:using-polydev` to choose the right skill or command for a task.

## Verification Levels

| Level | Name | Scope |
| --- | --- | --- |
| L0 | skip | No verification, suitable for docs/config only |
| L1 | compile | Build only |
| L2 | unit | Build plus unit tests |
| L3 | integration | Integration tests included |
| L4 | e2e | End-to-end tests included |
| L5 | manual | Human verification required |

## Polycron

Polycron schedules agent sessions through OS schedulers.

- Linux/macOS: crontab
- Windows: schtasks

Data lives under `~/.polydev/cron/`:

- job definitions: `~/.polydev/cron/jobs/`
- trigger history: `~/.polydev/cron/history.jsonl`

Examples:

```bash
"$POLYDEV_SCRIPTS/polycron-add.sh" daily-report \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report" \
  --cwd /path/to/project

"$POLYDEV_SCRIPTS/polycron-list.sh"
"$POLYDEV_SCRIPTS/polycron-history.sh" --last 10
"$POLYDEV_SCRIPTS/polycron-remove.sh" daily-report
```

## Windows Notes

- Use `python`, not `python3`; backend detection handles this.
- Always quote paths with spaces.
- Scripts handle path conversion automatically.
- Use PowerShell 7 (`pwsh`) for `*.ps1` Codex adapter scripts.
- WezTerm may need a cold-start retry after system boot.

## Terminal Backend Guardrails

Do not shorten the `sleep 2` before sending Enter in WezTerm send-text helpers. Interactive coding agents need time to process large text input before Enter is sent.

Do not remove `--no-paste` from `wezterm cli send-text` calls. Without it, bracketed paste markers can make Enter arrive as literal text instead of executing the command.

The Claude adapter must unset `CLAUDECODE` using shell-appropriate logic. Prefer `tb_launch_claude()` for that adapter instead of sending raw `unset CLAUDECODE && ...` commands. Keep equivalent tool-specific environment handling inside that tool's launcher.

## Inline Python Escaping

When passing shell values to inline Python, use environment variables instead of string interpolation.

```bash
PANE_ID="$pane_id" $PYTHON -c "
import os
pid = os.environ.get('PANE_ID', '')
"
```

Avoid:

```bash
$PYTHON -c "if pid == '$pane_id': ..."
```

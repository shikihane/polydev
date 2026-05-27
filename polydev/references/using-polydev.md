# Using Polydev

Polydev is a Windows-first, agent-neutral orchestration layer for terminal-hosted coding agents. It should work through thin adapters for Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and similar tools.

Use this reference to select the right Polydev workflow before launching sessions, scheduling work, or intervening in terminals.

## Design Rules

- Treat Windows and WezTerm as first-class targets, not compatibility fallbacks.
- Prefer semi-automation: keep sessions visible, inspectable, interruptible, and recoverable.
- Use Polydev scripts instead of direct tmux/WezTerm commands.
- Resolve the Polydev scripts root once from the installed skill directory for the active runtime, then paste literal full script paths in commands.
- Do not invent usernames, home directories, repository-relative script paths, or environment-variable script roots.
- Keep provider-specific commands, model flags, prompt wrappers, and environment handling inside adapter scripts.
- Treat root-level scripts as stable public wrappers. Internal provider/platform implementations live under `scripts/adapters/` and `scripts/backends/`.
- Do not run internal implementation files: `terminal-backend.sh`, `terminal-backend.ps1`, `scripts/backends/*`, or `scripts/adapters/*`.

## Entry Selection Order

Choose in this order:

1. Pick the workflow: `bg` for background terminal work, `ag` for read-only agent investigation, `wo` for worktree-backed implementation, `cron` for scheduled work, or dashboard for monitoring.
2. Pick the runtime dimension: D1, D2, D3, or D4.
3. Resolve the installed skill scripts root for that runtime and call only public root-level scripts by literal full path.

Do not infer that Polydev was unused just because a session did not use `start-codex-*.ps1` or `task.toon`. Background sessions use `run-background.sh` and `pane_id`; investigation sessions are also pane-only unless launched as worktrees.

## Four Runtime Dimensions

Before choosing a script, identify the active runtime dimension. Path style, shell syntax, and adapter selection must all match that dimension.

| Dimension | Runtime | Backend | Shell | Agent | Scripts root and flow-specific entry points |
| --- | --- | --- | --- | --- | --- |
| D1 | Windows Codex | WezTerm | PowerShell | Codex CLI | `C:\Users\<user>\.codex\skills\polydev\scripts`; `ag` uses `start-codex-investigation.ps1`, `wo` uses `start-codex-worktree.ps1`; `bg` uses the public Bash wrappers only after explicitly selecting and verifying a Bash caller |
| D2 | Windows Claude Code | WezTerm | Git Bash | Claude Code | `/c/Users/<user>/.claude/skills/polydev/scripts`; `bg` uses `run-background.sh`, `ag` uses `spawn-agent.sh` or `spawn-codex.sh`, `wo` uses `spawn-session.sh` |
| D3 | Linux/macOS Codex | tmux | bash | Codex CLI | `/home/<user>/.codex/skills/polydev/scripts`; `bg` uses `run-background.sh`, `ag` uses `spawn-codex.sh` |
| D4 | Linux/macOS Claude Code | tmux | bash | Claude Code | `/home/<user>/.claude/skills/polydev/scripts`; `bg` uses `run-background.sh`, `ag` uses `spawn-agent.sh`, `wo` uses `spawn-session.sh` |

Hard boundaries:

- Do not call PowerShell from shared Bash scripts or Bash-only examples.
- Do not call Bash from PowerShell scripts or D1 examples.
- Do not solve D1 by adding PowerShell syntax to shared Bash scripts.
- Do not solve D2/D3/D4 by requiring `pwsh`, Windows paths, or PowerShell cmdlets.

## Script Root Resolution

State the resolved scripts root as a literal fact before running scripts:

```text
Polydev scripts root: /c/Users/<actual-user>/.claude/skills/polydev/scripts
```

The scripts root is the installed skill directory for the active runtime, not the repository checkout. If the loaded skill path is available, derive the scripts root from that path. Otherwise, verify the target install directory exists before using it.

Do not rely on `POLYDEV_SCRIPTS`, shell profiles, inherited process environments, generated links, or workspace-relative paths. After resolution, every command should hard-code the full script path.

## Routing

| Need | Flow |
| --- | --- |
| Complex or unclear parallel request | `/polydev-brainstorm` |
| Detailed task plan or `PLAN.md` | `references/writing-plans.md` |
| 2+ independent implementation branches | `references/worktree-executor.md` |
| Long build, test, server, SSH, or REPL | `references/terminal-task-runner.md` |
| Scheduled or recurring agent session | `references/polycron.md` |
| Read-only investigation agent | `references/agent-investigator.md` |
| Dashboard or Kanban monitor | `references/kanban.md` |

Prefix convention:

- `wo:` worktree development, requires Git, uses worktree execution.
- `bg:` background terminal task, no Git required, uses terminal task runner.
- `ag:` investigation agent, no Git required, uses agent investigator.

## Workflow Entry Matrix

| Flow | D1 Windows Codex | D2 Windows Claude Code | D3 Linux/macOS Codex | D4 Linux/macOS Claude Code |
| --- | --- | --- | --- | --- |
| `bg` background task | If using a Bash caller, `run-background.sh` from `/c/Users/<user>/.codex/skills/polydev/scripts`; do not present this as a PowerShell example | `run-background.sh` | `run-background.sh` | `run-background.sh` |
| `bg` inspect/control | If using a Bash caller, `list-sessions.sh`, `capture-screen.sh`, `send-to-session.sh`, `close-session.sh` from `/c/Users/<user>/.codex/skills/polydev/scripts` | same Bash scripts | same Bash scripts | same Bash scripts |
| `ag` read-only investigation | `start-codex-investigation.ps1`, then `send-prompt.ps1` | `spawn-agent.sh` or `spawn-codex.sh`, then `send-prompt.sh` | `spawn-codex.sh`, then `send-prompt.sh` | `spawn-agent.sh`, then `send-prompt.sh` |
| `wo` worktree implementation | `start-codex-worktree.ps1` | `spawn-session.sh` | future adapter | `spawn-session.sh` |

## Windows Claude Code

D2 Windows Claude Code uses Git Bash under WezTerm. Use Bash paths and Bash wrappers from the installed Claude skill directory.

D2 uses `spawn-codex.sh` from the installed Claude skill directory when a Windows Claude Code coordinator starts a Codex CLI investigation.

Examples:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/list-sessions.sh"
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" research --cwd .
"/c/Users/<user>/.claude/skills/polydev/scripts/send-prompt.sh" <pane_id> --file /tmp/research-prompt.md --peek 5
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-codex.sh" codex-research --cwd .
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" myproject feature-auth .worktrees/feature-auth docs/plans/auth.md
```

For D2, prompt spawned agents that they are running in a Windows Claude Code environment using Git Bash paths. Use `/e/...` and `/c/...` path forms in Bash commands.

## Windows Codex

D1 Windows Codex uses native PowerShell 7 under WezTerm for Codex investigation and worktree adapters. Use Windows paths and PowerShell wrappers for `ag` and `wo` flows.

For `bg` background terminal tasks and pane control, first decide the caller shell. If a Bash caller is explicitly selected and verified, use the public Bash wrappers from the installed Codex skill directory converted to `/c/...` path form. This is still a D1 Polydev flow; do not reclassify it as D2 just because the wrapper command is Bash. Keep Bash commands in Bash examples, not PowerShell examples.

Examples:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-investigation.ps1" research -Cwd .
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\send-prompt.ps1" <pane_id> -Text "Inspect repository only." -Peek 5
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-worktree.ps1" myproject codex-auth .worktrees\codex-auth docs\plans\auth.md
```

D1 background examples after explicitly selecting a Bash caller:

```bash
"/c/Users/<user>/.codex/skills/polydev/scripts/run-background.sh" build "npm run build" --cwd "/e/project" --peek 10
"/c/Users/<user>/.codex/skills/polydev/scripts/close-session.sh" --pane-id 5
```

Tell Codex it is running in a Windows PowerShell-oriented environment. Use Windows paths and `$env:TEMP`, not `/tmp`, unless the prompt explicitly verified Bash.

## Linux/macOS Claude Code

D4 Linux/macOS Claude Code uses Bash under tmux. Use POSIX paths and the installed Claude skill directory.

```bash
"/home/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" research --cwd .
"/home/<user>/.claude/skills/polydev/scripts/send-prompt.sh" <pane_id> --file /tmp/research-prompt.md --peek 5
"/home/<user>/.claude/skills/polydev/scripts/spawn-session.sh" myproject feature-auth .worktrees/feature-auth docs/plans/auth.md
```

## Linux/macOS Codex

D3 Linux/macOS Codex uses Bash under tmux. Use POSIX paths and Codex Bash adapters.

```bash
"/home/<user>/.codex/skills/polydev/scripts/spawn-codex.sh" research --cwd .
"/home/<user>/.codex/skills/polydev/scripts/send-prompt.sh" <pane_id> --file /tmp/research-prompt.md --peek 5
```

## Script Quick Reference

| Scenario | Script | Parameters |
| --- | --- | --- |
| Create worktree-backed Claude Code session | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Create Windows Codex worktree session | `start-codex-worktree.ps1` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor worktree status | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore Claude Code worktree session | `restore-session.sh` | `<worktree-path> [--force]` |
| Restore Windows Codex worktree session | `restore-codex-worktree.ps1` | `<worktree-path> [-Force]` |
| Send to worktree session | `wo-send-command.sh` | `<worktree-path> "<cmd>" [--peek N]` |
| Send to any pane | `send-to-session.sh` | `<pane_id> "<cmd>" [--peek N]` |
| Capture screen | `capture-screen.sh` | `<worktree-path>` or `--pane-id <id>` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<worktree-path>` or `--pane-id <id>` |
| Background command | `run-background.sh` | `<name> "<cmd>" [--cwd <dir>] [--peek N]` |
| Claude Code investigation session | `spawn-agent.sh` | `<name> --cwd <dir> [--model <name>] [--ready-timeout 15]` |
| Codex CLI Bash investigation session | `spawn-codex.sh` | `<name> --cwd <dir> [--model <name>] [--ready-timeout 15]` |
| Send investigation prompt | `send-prompt.sh` | `<pane_id> (--text <prompt> | --file <path>) [--peek N]` |
| Capture investigation output | `capture-screen.sh` | `--pane-id <id> [--lines N]` |
| Windows Codex investigation | `start-codex-investigation.ps1` | `<name> -Cwd <dir> [--model <name>] [--ready-timeout 15]` |
| Windows investigation prompt | `send-prompt.ps1` | `<pane_id> (-Text <prompt> \| -File <path>) [-Peek N]` |
| Gemini CLI investigation | `spawn-gemini.sh` | `<name> --cwd <dir> [--ready-timeout 15]` |
| Add scheduled job | `polycron-add.sh` | `<job-id> --schedule "..." --prompt "..." --cwd <dir>` |

Scripts that return a `pane_id` usually support `--peek N`:

- `--peek 0`: capture immediately.
- `--peek 5`: wait 5 seconds, then capture.
- omitted: do not capture.

## Decision Guide

- User gives 2+ independent code tasks: write a plan, then execute with worktree sessions.
- User gives one long command, dev server, test run, SSH, or REPL: use `terminal-task-runner`.
- User asks for read-only research: start an investigation through the adapter for the active runtime.
- User asks for a future or recurring run: use `polycron`.
- User wants direct control or a terminal is stuck: use `list-sessions.sh`, `capture-screen.sh`, `send-to-session.sh`, `restore-session.sh`, and `close-session.sh`.

## Cost Controls

Cost controls are adapter-specific.

- Claude Code Task sub-agents should specify `model: "sonnet"` unless the user requests a different model.
- Codex PowerShell defaults to `--sandbox workspace-write --ask-for-approval on-request`.
- Use dangerous bypass only when explicitly requested.
- Do not apply one provider's model, pricing, or approval policy globally to Codex, Cursor, OpenCode, Gemini CLI, or future adapters.

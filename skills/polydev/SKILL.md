---
name: polydev
description: "Use when executing two or more independent implementation tasks in parallel with Git worktrees and terminal-hosted coding agents"
---

# Polydev

Polydev coordinates parallel development with Git worktrees, visible terminal sessions, and `task.toon` status files. It is Windows-first, agent-neutral, and intentionally semi-automated so a human can inspect, interrupt, recover, and redirect work.

Use this skill for `wo:` worktree development. For `bg:` background commands, use `terminal-task-runner`. For `ag:` read-only investigation, use `agent-investigator`.

## Non-Negotiable Rules

- Use this skill only in a Git repository.
- Call bash Polydev scripts through `$POLYDEV_SCRIPTS` and Windows PowerShell scripts through `$env:POLYDEV_SCRIPTS`; never use `./scripts/...`.
- Do not call tmux or WezTerm directly from the agent path.
- Do not hand-write `git worktree add/remove` orchestration while creating sessions.
- Do not delete `.worktrees` directly.
- Keep the same workspace name for all parallel branches in one project.
- Monitor after spawning; do not launch sessions and hope they finish.
- Cleanup order is close session, verify closed, then remove worktree after human confirmation.

## Script Path

Use:

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

If unset:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
```

Windows/Git Bash fallback for silent no-output script runs:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/list-sessions.sh")"
```

## Create Worktree-Backed Agent Sessions

Worktree paths must be `.worktrees/<branch-name>`.

Use one workspace name for all related branches so Windows/WezTerm opens one window with multiple tabs:

```bash
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature-auth .worktrees/feature-auth docs/plans/auth.md
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature-api .worktrees/feature-api docs/plans/api.md
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature-ui .worktrees/feature-ui docs/plans/ui.md
```

On Windows with Codex CLI, use the native PowerShell adapter:

```powershell
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" myproject codex-auth .worktrees/codex-auth docs/plans/auth.md
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" myproject codex-api .worktrees/codex-api docs/plans/api.md
```

Wrong: using `ws1`, `ws2`, `ws3` for the same project, which creates separate windows.

## Monitor and Intervene

Start monitoring immediately after launching sessions:

```bash
"$POLYDEV_SCRIPTS/poll.sh" .worktrees 10
```

Trust `task.toon` for worktree status. Use terminal capture for diagnosis and human intervention, not as the source of truth for task state.

Common intervention commands:

```bash
"$POLYDEV_SCRIPTS/capture-screen.sh" .worktrees/feature-auth --lines 80
"$POLYDEV_SCRIPTS/wo-send-command.sh" .worktrees/feature-auth "npm test" --peek 5
"$POLYDEV_SCRIPTS/restore-session.sh" .worktrees/feature-auth --force
"$POLYDEV_SCRIPTS/close-session.sh" .worktrees/feature-auth
```

Status handling:

- `completed`: verify branch output before merge.
- `blocked`: main agent may resolve dependencies, environment issues, or cross-branch coordination.
- `hil`: human must decide; do not guess.
- `idle` or `crashed`: inspect, then restore if appropriate.

## Cleanup

Close the terminal before deleting a worktree, especially on Windows where the terminal may hold a directory lock:

```bash
"$POLYDEV_SCRIPTS/close-session.sh" .worktrees/feature-auth
"$POLYDEV_SCRIPTS/list-sessions.sh" myproject
git worktree remove .worktrees/feature-auth --force
git worktree prune
```

Ask the human before deleting worktrees or branches. Never use `rm -rf .worktrees/...`.

## Agent Adapters

Polydev core concepts are not tied to one provider. Existing scripts include:

```bash
"$POLYDEV_SCRIPTS/spawn-agent.sh" research --prompt "..." --report .agent-reports/research.md --cwd .
"$POLYDEV_SCRIPTS/spawn-codex.sh" codex-research --prompt "..." --cwd . --output .agent-reports/codex.md
"$POLYDEV_SCRIPTS/spawn-gemini.sh" gemini-research --prompt "..." --cwd . --output .agent-reports/gemini.md
```

Windows Codex PowerShell adapters:

```powershell
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" research -Prompt "..." -Cwd . -Output .agent-reports\codex.md
pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\restore-codex-worktree.ps1" .worktrees\codex-auth -Force
```

Claude Code model cost rules apply only to Claude Code adapters. Codex PowerShell sessions default to `--sandbox workspace-write --ask-for-approval on-request`; `-DangerousBypass` is only for explicitly approved unattended runs. Keep provider-specific model flags, approval policy, and environment variables at the launcher boundary.

## References

- `references/architecture.md`: session types, status values, scripts, cleanup, and recovery.
- `references/verification-levels.md`: L0-L5 verification levels and workflow.

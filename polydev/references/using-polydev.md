# Using Polydev

Use this reference when choosing the right Polydev flow.

## Routing

- `wo:` worktree development -> `worktree-executor`
- `bg:` background terminal task -> `terminal-task-runner`
- `ag:` read-only investigation -> `agent-investigator`
- recurring or delayed runs -> `polycron`

## Before Running Scripts

- First state the resolved scripts root, for example `Polydev scripts root: /c/Users/<actual-user>/.claude/skills/polydev/scripts`.
- Do not invent or normalize the username. Use the actual loaded skill path or an existing install directory.
- Do not run internal implementation files: `terminal-backend.sh`, `terminal-backend.ps1`, `scripts/backends/*`, or `scripts/adapters/*`.
- Use only public root-level entry scripts for smoke tests and user actions.
- For a skill smoke test, prefer `list-sessions.sh` with a short timeout; do not launch agents, create worktrees, schedule jobs, or clean up sessions unless requested.

## Windows Codex

- Use `start-codex-investigation.ps1` or `start-codex-worktree.ps1`.
- Use the D1 Codex PowerShell scripts root, for example `C:\Users\<user>\.codex\polydev\scripts`, when launching Codex from PowerShell.
- If invoking a D1 PowerShell adapter from Bash, still pass the literal full adapter path to `pwsh -File`; do not store it in `POLYDEV_SCRIPTS`.
- Tell Codex it is running in a Windows PowerShell-oriented environment.
- Use Windows paths and `$env:TEMP`, not `/tmp`, unless the prompt explicitly verified Bash.

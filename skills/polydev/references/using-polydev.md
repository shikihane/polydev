# Using Polydev

Use this reference when choosing the right Polydev flow.

## Routing

- `wo:` worktree development -> `worktree-executor`
- `bg:` background terminal task -> `terminal-task-runner`
- `ag:` read-only investigation -> `agent-investigator`
- recurring or delayed runs -> `polycron`

## Windows Codex

- Use `start-codex-investigation.ps1` or `start-codex-worktree.ps1`.
- Use the D1 Codex PowerShell scripts root, for example `C:\Users\<user>\.codex\polydev\scripts`, when launching Codex from PowerShell.
- If invoking a D1 PowerShell adapter from Bash, still pass the literal full adapter path to `pwsh -File`; do not store it in `POLYDEV_SCRIPTS`.
- Tell Codex it is running in a Windows PowerShell-oriented environment.
- Use Windows paths and `$env:TEMP`, not `/tmp`, unless the prompt explicitly verified Bash.

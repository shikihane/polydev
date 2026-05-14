# Using Polydev

Use this reference when choosing the right Polydev flow.

## Routing

- `wo:` worktree development -> `worktree-executor`
- `bg:` background terminal task -> `terminal-task-runner`
- `ag:` read-only investigation -> `agent-investigator`
- recurring or delayed runs -> `polycron`

## Windows Codex

- Use `start-codex-investigation.ps1` or `start-codex-worktree.ps1`.
- Tell Codex it is running in a Windows PowerShell-oriented environment.
- Use Windows paths and `$env:TEMP`, not `/tmp`, unless the prompt explicitly verified Bash.


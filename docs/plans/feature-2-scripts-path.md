# Feature 2: Absolute Script Path Guidance

## Status

This plan supersedes the older `POLYDEV_SCRIPTS` shortcut idea. Polydev documentation and skills must require full absolute script paths in every script invocation.

## Core Rule

Agents resolve the installed Polydev scripts directory once when first needed, keep that resolved directory as plain prompt/context text, and then paste complete absolute script paths in commands.

For Claude Code, the installed Polydev scripts directory is the Claude skill directory. D2 and D4 must use `.claude/skills/polydev/scripts`; never use a repository checkout, `.claudecode`, or `.claude/plugins/cache/...` path.

Do not use:

- `$POLYDEV_SCRIPTS`
- `$env:POLYDEV_SCRIPTS`
- `./scripts/...`
- repository-relative script paths
- shell profiles or inherited process environments as path transport

## Runtime Examples

D1 Windows Codex PowerShell:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-worktree.ps1" polydev-test codex-smoke .worktrees\codex-smoke docs\plans\feature-2-scripts-path.md
```

D2 Windows Claude Code Git Bash:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" polydev-test feature-auth .worktrees/feature-auth docs/plans/feature-2-scripts-path.md
```

D3 Linux/macOS Codex:

```bash
"/home/<user>/.codex/skills/polydev/scripts/spawn-codex.sh" research --prompt "Inspect repository only." --cwd . --output .agent-reports/codex.md
```

D4 Linux/macOS Claude Code:

```bash
"/home/<user>/.claude/skills/polydev/scripts/spawn-session.sh" polydev-test feature-auth .worktrees/feature-auth docs/plans/feature-2-scripts-path.md
```

## Completion Criteria

- [ ] `AGENTS.md` requires full absolute script paths.
- [ ] `CLAUDE.md` requires full absolute script paths.
- [ ] All Polydev skills require full absolute script paths.
- [ ] Agent YAML prompts mention full absolute script paths where they can produce script commands.
- [ ] README examples use full absolute script paths.
- [ ] No user-facing script invocation example teaches environment variables as the path mechanism.

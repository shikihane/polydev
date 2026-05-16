# Terminal Task Runner

Use this reference for `bg:` background terminal work. It hosts commands in tmux or WezTerm through Polydev scripts so the user and agent can inspect output, send input, and close sessions cleanly.

This is a core part of Polydev's semi-automated design: long work should remain visible and interruptible, especially on Windows/WezTerm.

## Rules

- Use this for SSH, dev servers, builds, tests, package installs, REPLs, and commands likely to exceed 30 seconds.
- Resolve the scripts root once from the installed skill directory for the active runtime, then call scripts by literal full absolute path.
- Use only the installed Polydev skill scripts directory, not the repository checkout.
- Do not use `&`, `nohup`, shell backgrounding, or direct tmux/WezTerm commands.
- Do not pass human-readable `session_id` to scripts; use `pane_id`.
- Close sessions when work is finished.

## Script Path

D2 Windows Claude Code example:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" build "npm run build" --cwd . --peek 10
```

D1 Windows Codex still uses Bash wrappers for generic background tasks only when the current shell is Bash. If the active flow is Codex-specific investigation or worktree execution, use the Codex PowerShell adapters described in `using-polydev.md`.

## Core Commands

Start a command:

```bash
pane_id=$("/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" build "npm run build" --cwd . --peek 10)
```

Send input to an existing pane:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/send-to-session.sh" "$pane_id" "docker ps" --peek 3
"/c/Users/<user>/.claude/skills/polydev/scripts/send-to-session.sh" "$pane_id" "password" --no-enter
```

Read output:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/capture-screen.sh" --pane-id "$pane_id" --lines 80
```

List and close:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/list-sessions.sh"
"/c/Users/<user>/.claude/skills/polydev/scripts/close-session.sh" --pane-id "$pane_id"
```

## Monitoring Pattern

Capture output periodically and decide from actual terminal text:

```bash
output=$("/c/Users/<user>/.claude/skills/polydev/scripts/capture-screen.sh" --pane-id "$pane_id" --lines 80)
```

If output shows a prompt, use `send-to-session.sh`. If it is stuck or no longer needed, use `close-session.sh`.

On Windows/WezTerm, do not assume the pane shell. Probe with a harmless command before sending shell-specific syntax.

## pane_id Format

| Backend | Format | Example |
| --- | --- | --- |
| WezTerm | numeric | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

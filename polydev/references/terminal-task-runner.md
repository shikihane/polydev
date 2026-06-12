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

Always resolve the installed Polydev scripts root for the active runtime first. For D1 Windows Codex, use the public PowerShell wrappers from the installed Codex skill directory. For D2/D3/D4 Bash runtimes, use the public Bash wrappers.

D1 Windows Codex example:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\run-background.ps1" build -Command "npm run build" -Cwd "E:\project" -Peek 10
```

D2 Windows Claude Code example:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" build "npm run build" --cwd . --peek 10
```

If the active flow is Codex-specific investigation or worktree execution, use the Codex PowerShell adapters described in `using-polydev.md` instead of `run-background.sh`.

## Core Commands

Start a command:

```bash
pane_id=$("/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" build "npm run build" --cwd . --peek 10)
```

D1 Windows Codex:

```powershell
$paneId = pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\run-background.ps1" build -Command "npm run build" -Cwd .
```

Send input to an existing pane:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\send-to-session.ps1" $paneId "docker ps" -Peek 3
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\send-to-session.ps1" $paneId "password" -NoEnter
```

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

D1 Windows Codex inspect and close:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\capture-screen.ps1" -PaneId $paneId -Lines 80
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\close-session.ps1" -PaneId $paneId
```

## Monitoring Pattern

Capture output periodically and decide from actual terminal text:

```powershell
$output = pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\capture-screen.ps1" -PaneId $paneId -Lines 80
```

```bash
output=$("/c/Users/<user>/.claude/skills/polydev/scripts/capture-screen.sh" --pane-id "$pane_id" --lines 80)
```

If output shows a prompt, use `send-to-session.ps1` on D1 or `send-to-session.sh` on Bash runtimes. If it is stuck or no longer needed, use `close-session.ps1` on D1 or `close-session.sh` on Bash runtimes.

On Windows/WezTerm, do not assume the pane shell. Probe with a harmless command before sending shell-specific syntax.

## pane_id Format

| Backend | Format | Example |
| --- | --- | --- |
| WezTerm | numeric | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

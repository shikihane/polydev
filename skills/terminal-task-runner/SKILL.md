---
name: terminal-task-runner
description: "Use when running long commands, builds, tests, dev servers, SSH sessions, REPLs, or other terminal work that should stay visible, monitorable, and recoverable"
---

# Terminal Task Runner

Use this skill for `bg:` background terminal work. It hosts commands in tmux or WezTerm through Polydev scripts so the user and agent can inspect output, send input, and close sessions cleanly.

This is a core part of Polydev's semi-automated design: long work should remain visible and interruptible, especially on Windows/WezTerm.

## Rules

- Use this for SSH, dev servers, builds, tests, package installs, REPLs, and commands likely to exceed 30 seconds.
- Call scripts via `$POLYDEV_SCRIPTS`.
- Do not use `&`, `nohup`, shell backgrounding, or direct tmux/WezTerm commands.
- Do not pass human-readable `session_id` to scripts; use `pane_id`.
- Close sessions when work is finished.

## Script Path

```bash
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

If `$POLYDEV_SCRIPTS` is unset, initialize it:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
```

On Windows/Git Bash, if a script exits with no output:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/list-sessions.sh")"
```

## Core Commands

Start a command:

```bash
pane_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build" --cwd . --peek 10)
```

Send input to an existing pane:

```bash
"$POLYDEV_SCRIPTS/send-to-session.sh" "$pane_id" "docker ps" --peek 3
"$POLYDEV_SCRIPTS/send-to-session.sh" "$pane_id" "password" --no-enter
```

Read output:

```bash
"$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id "$pane_id" --lines 80
```

List and close:

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/close-session.sh" --pane-id "$pane_id"
```

## Monitoring Pattern

Capture output periodically and decide from actual terminal text:

```bash
output=$("$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id "$pane_id" --lines 80)
```

If output shows a prompt, use `send-to-session.sh`. If it is stuck or no longer needed, use `close-session.sh`.

## pane_id Format

| Backend | Format | Example |
| --- | --- | --- |
| WezTerm | numeric | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

---
name: terminal-task-runner
description: This skill should be used when running commands that take >30 seconds (builds, tests, servers) - hosts in terminal session for monitoring and recovery.
version: 0.1.0
---

# Terminal Task Runner

Host background commands in terminal (tmux/wezterm) and monitor their status.

---

## Session Type: bg: (Background Task)

**Prefix `bg:` = Background command** (SSH, build, test, server, etc.)

Choose skill by prefix:
- `bg:` → **terminal-task-runner** (this skill) - NO git required
- `ag:` → **agent-investigator** - NO git required (research, analysis)
- `wo:` → **polydev** - REQUIRES git repo

---

## ⛔ Mandatory Constraints - Violation = Failure

```
┌─────────────────────────────────────────────────────────────────┐
│ USE THIS SKILL FOR:                                             │
│ - ANY SSH connection                                            │
│ - ANY command that takes >10 seconds                            │
│ - ANY background/long-running task                              │
│ - ANY build, test, or dev server                                │
│                                                                 │
│ ABSOLUTELY PROHIBITED:                                          │
│ - Using Bash tool's run_in_background parameter                 │
│ - Using & or nohup to background commands                       │
│ - Calling tmux/wezterm commands directly                        │
│ - Trying to "do it faster myself" without this skill            │
│                                                                 │
│ NO GIT REPO REQUIRED - This skill works anywhere                │
│                                                                 │
│ FOR SUB-AGENTS (ag:) → Use agent-investigator skill             │
│ FOR PARALLEL DEV (wo:) → Use polydev skill (requires git)       │
└─────────────────────────────────────────────────────────────────┘
```

**If these rules are violated, the task WILL FAIL.**

---

## Script Path

**All scripts MUST be called via `$POLYDEV_SCRIPTS` variable. NEVER use relative path `./scripts/`**

```bash
# Set path variable before calling any script
POLYDEV_SCRIPTS="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")")/scripts"
# Or if in skill context, use skill base directory:
# POLYDEV_SCRIPTS="<skill-base-dir>/../scripts"

# Then call scripts using the variable
"$POLYDEV_SCRIPTS/run-background.sh" <name> "<command>"
```

**When called from Claude Code**: Use the plugin installation path
```bash
# Plugin path example (based on actual installation location)
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

---

## When to Use

- Build commands (`npm run build`, `cargo build`, `go build`)
- Test commands (`npm test`, `pytest`, `cargo test`)
- Dev servers (`npm run dev`, `cargo watch`)
- Install dependencies (`npm install`, `pip install`)
- **SSH remote connections** (interactive sessions)
- Any command that might take more than 30 seconds

---

## Script Usage Constraints (Must Follow)

### Scenario A: Start Background Task
**Script**: `run-background.sh`
**Parameters**: `<name> "<command>" [--cwd <dir>]`
**Returns**: session_id (format: `bg:<workspace>:<name>.0`)

```bash
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")
# Returns: bg:bg-myproject:build.0
```

### Scenario B: Send Command to Existing Session (SSH, REPL, etc.)
**Script**: `send-to-session.sh`
**Parameters**: `<session_id> "<command>" [--no-enter]`
**session_id format**: `bg:xxx`, `wo:xxx`, `ag:xxx`

```bash
# Send command to SSH session
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh-remote.0 "docker ps"

# Send password (without pressing Enter)
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh-remote.0 "mypassword" --no-enter
```

### Scenario C: Monitor Output
**Script**: `capture-screen.sh`
**Parameters**: `--session <wo:session_id> --lines <N>`

```bash
# Convert bg: to wo: prefix for capture
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 50
```

### Scenario D: Close Task
**Script**: `close-session.sh`
**Parameters**: `<session_id>`

```bash
"$POLYDEV_SCRIPTS/close-session.sh" bg:bg-myproj:build.0
```

### Scenario E: List All Sessions
**Script**: `list-sessions.sh`
**Parameters**: `[workspace]` (optional filter)

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/list-sessions.sh" myproject
```

---

## Prohibited Actions

```
DO NOT use relative path ./scripts/ (breaks when leaving plugin directory)
DO NOT use Bash tool's run_in_background parameter
DO NOT use & to background
DO NOT use nohup
DO NOT call tmux/wezterm commands directly
DO NOT use wrong script (e.g., wo-send-command.sh for bg: session - it's for wo: only)

MUST call scripts via $POLYDEV_SCRIPTS variable
MUST monitor task status
MUST clean up session when done
```

---

## Typical Workflows

### Workflow A: Build Task (Monitor Output)

```bash
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"

# Start
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")

# Monitor output periodically
while true; do
  output=$("$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 30)

  if echo "$output" | grep -q "BUILD_SUCCESS\|completed\|passed"; then
    echo "Task completed"
    break
  fi

  if echo "$output" | grep -q "BUILD_FAILED\|Error\|failed"; then
    echo "Task failed"
    break
  fi

  sleep 10
done

# Cleanup
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

### Workflow B: SSH Interactive Session

```bash
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"

# 1. Start SSH connection
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" ssh-server "ssh user@host")

# 2. Wait for connection (may need password)
sleep 3
"$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 20

# 3. If password needed
"$POLYDEV_SCRIPTS/send-to-session.sh" "$session_id" "mypassword"

# 4. Send commands
"$POLYDEV_SCRIPTS/send-to-session.sh" "$session_id" "docker ps"

# 5. View results
sleep 2
"$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 30

# 6. Close when done
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

---

## Session ID Format

```
bg:<workspace>:<name>.0
|  |          |      |
|  |          |      +-- pane index (always 0)
|  |          +-- task name
|  +-- workspace (default: bg-<current-dir-name>)
+-- prefix (background task)
```

**Prefix Conversion Rules**:
- `capture-screen.sh` `--session` parameter requires `wo:` prefix
- Other scripts accept original `bg:` prefix
- Conversion method: `${session_id/bg:/wo:}`

---

## Troubleshooting

### Command Not Executed
```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

### Cannot See Output
```bash
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 100
```

### Session Stuck
```bash
"$POLYDEV_SCRIPTS/close-session.sh" bg:myproj:build.0
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

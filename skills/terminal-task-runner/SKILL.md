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
# 自动由 SessionStart hook 写入，无需手动设置路径
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)

# Then call scripts using the variable
"$POLYDEV_SCRIPTS/run-background.sh" <name> "<command>"
```

> 如果 `~/.polydev/scripts-path` 不存在，说明 hook 未执行。手动设置:
> `POLYDEV_SCRIPTS="$CLAUDE_PLUGIN_ROOT/scripts"`

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
**Parameters**: `<name> "<command>" [--cwd <dir>] [--peek N]`
**Returns**: pane_id (numeric identifier for the terminal pane)

```bash
pane_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")
# Returns: numeric pane_id, e.g. 5

# With auto-screenshot after 10 seconds
pane_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build" --peek 10)
```

### Scenario B: Send Command to Existing Session (SSH, REPL, etc.)
**Script**: `send-to-session.sh`
**Parameters**: `<pane_id> "<command>" [--no-enter] [--peek N]`

```bash
# Send command to SSH session (use pane_id from run-background.sh return value)
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps"

# Send password (without pressing Enter)
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "mypassword" --no-enter

# Send command and auto-screenshot after 3 seconds
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps" --peek 3
```

### Scenario C: Monitor Output
**Script**: `capture-screen.sh`
**Parameters**: `--pane-id <pane_id> [--lines N]`

```bash
"$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id 5 --lines 50
```

### Scenario D: Close Task
**Script**: `close-session.sh`
**Parameters**: `--pane-id <pane_id>`

```bash
"$POLYDEV_SCRIPTS/close-session.sh" --pane-id 5
```

### Scenario E: List All Sessions
**Script**: `list-sessions.sh`
**Parameters**: `[workspace]` (optional filter)

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/list-sessions.sh" myproject
```

### --peek: 执行后自动截屏

所有返回 pane_id 的脚本均支持 `--peek N` 选项:
- `--peek 0`: 立即截屏
- `--peek 5`: 等 5 秒后截屏
- 不传: 不截屏

示例:
```bash
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps" --peek 3
"$POLYDEV_SCRIPTS/run-background.sh" build "npm test" --peek 10
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
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)

# Start
pane_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")

# Monitor output periodically
while true; do
  output=$("$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id "$pane_id" --lines 30)

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
"$POLYDEV_SCRIPTS/close-session.sh" --pane-id "$pane_id"
```

### Workflow B: SSH Interactive Session

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)

# 1. Start SSH connection
pane_id=$("$POLYDEV_SCRIPTS/run-background.sh" ssh-server "ssh user@host")

# 2. Wait for connection (may need password)
sleep 3
"$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id "$pane_id" --lines 20

# 3. If password needed
"$POLYDEV_SCRIPTS/send-to-session.sh" "$pane_id" "mypassword"

# 4. Send commands
"$POLYDEV_SCRIPTS/send-to-session.sh" "$pane_id" "docker ps"

# 5. View results
sleep 2
"$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id "$pane_id" --lines 30

# 6. Close when done
"$POLYDEV_SCRIPTS/close-session.sh" --pane-id "$pane_id"
```

---

## pane_id Format

Scripts return and accept `pane_id` — the physical terminal identifier:

| Backend | Format | Example |
|---------|--------|---------|
| WezTerm | Numeric | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

**Note**: `list-sessions.sh` also outputs a human-readable `session_id` (e.g. `bg:workspace:name.0`) for debugging purposes. This is display-only — **never pass `session_id` to scripts**. Always use `pane_id`.

---

## Troubleshooting

### Command Not Executed
```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

### Cannot See Output
```bash
"$POLYDEV_SCRIPTS/capture-screen.sh" --pane-id 5 --lines 100
```

### Session Stuck
```bash
"$POLYDEV_SCRIPTS/close-session.sh" --pane-id 5
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

---
name: polydev-runner
description: |
  Run background commands in terminal (tmux/wezterm) for monitoring and recovery.
  WHEN: Builds >30s, test suites, dev servers, SSH sessions, long-running commands
  WHEN NOT: Quick commands <10s, simple file operations
  TRIGGERS: run build, run tests, start server, ssh, background task, npm run, cargo build
---

# Terminal Task Runner

Host background commands in terminal sessions (tmux/wezterm) and monitor their status.

---

## Script Path

**All scripts MUST be called via `$POLYDEV_SCRIPTS` variable.**

```bash
# Verify path is set
echo "$POLYDEV_SCRIPTS"

# Call scripts
"$POLYDEV_SCRIPTS/run-background.sh" <name> "<command>"
```

---

## When to Use

- Build commands (`npm run build`, `cargo build`, `go build`)
- Test suites (`npm test`, `pytest`, `cargo test`)
- Dev servers (`npm run dev`, `cargo watch`)
- Install dependencies (`npm install`, `pip install`)
- **SSH remote connections** (interactive sessions)
- Any command that might take more than 30 seconds

---

## Script Reference

### Start Background Task

```bash
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")
# Returns: bg:bg-myproject:build.0
```

### Send Command to Session (SSH, REPL)

```bash
# Send command
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh.0 "docker ps"

# Send password (without pressing Enter)
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh.0 "mypassword" --no-enter
```

### Analyze Output Status

```bash
result=$("$POLYDEV_SCRIPTS/analyze-output.sh" bg:bg-myproj:build.0 --lines 20 --json)
# Returns: status (running|idle|success|failed|done)
```

### Wait for Pattern Match

```bash
"$POLYDEV_SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300
# Exit: 0=success, 1=fail, 2=timeout
```

### View Raw Output

```bash
# Note: requires wo: prefix for --session
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 50
```

### Close Task

```bash
"$POLYDEV_SCRIPTS/close-session.sh" bg:bg-myproj:build.0
```

### List All Sessions

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

---

## Prohibited Actions

```
DO NOT use Bash tool's run_in_background parameter
DO NOT use & to background
DO NOT use nohup
DO NOT call tmux/wezterm commands directly
DO NOT use relative path ./scripts/

MUST call scripts via $POLYDEV_SCRIPTS variable
MUST monitor task status
MUST clean up session when done
```

---

## Typical Workflows

### Build Task (Polling)

```bash
# Start
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")

# Poll and check
while true; do
  result=$("$POLYDEV_SCRIPTS/analyze-output.sh" "$session_id" --lines 20 --json)
  status=$(echo "$result" | jq -r '.status')

  case "$status" in
    success|done)
      echo "Task completed"
      break
      ;;
    failed)
      echo "Task failed"
      "$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 50
      break
      ;;
  esac

  sleep 10
done

# Cleanup
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

### SSH Interactive Session

```bash
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

### Wait for Pattern

```bash
# Start and wait
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" test "npm test")

# Wait for success or failure
"$POLYDEV_SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300

exit_code=$?
case $exit_code in
  0) echo "Tests passed" ;;
  1) echo "Tests failed" ;;
  2) echo "Timeout" ;;
esac

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

**Prefix Conversion for capture-screen.sh:**
- `capture-screen.sh --session` requires `wo:` prefix
- Other scripts accept original `bg:` prefix
- Conversion: `${session_id/bg:/wo:}`

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

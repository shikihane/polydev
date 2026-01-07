---
name: polydev-runner
description: |
  MUST USE for: SSH connections, long-running commands, background tasks, builds, tests, dev servers.
  This skill runs commands in a persistent terminal session that survives disconnection.
  NO git repo required. Works anywhere.
  TRIGGERS: ssh, remote, background, long-running, build, test, server, npm, cargo, docker, watch
  WHEN NOT: Quick commands <10s that complete immediately
---

# Terminal Task Runner

Host background commands in terminal sessions (tmux/wezterm) and monitor their status.

---

## Session Type: bg: (Background Task)

**Prefix `bg:` = Background command** (SSH, build, test, server, etc.)

Choose skill by prefix:
- `bg:` → **polydev-runner** (this skill) - NO git required
- `ag:` → **polydev-agent** - NO git required
- `wo:` → **polydev** - REQUIRES git repo

---

## ⛔ MANDATORY CONSTRAINTS - VIOLATION = FAILURE

```
┌─────────────────────────────────────────────────────────────────┐
│ YOU MUST USE THIS SKILL FOR:                                    │
│ - ANY SSH connection                                            │
│ - ANY command that takes >10 seconds                            │
│ - ANY background/long-running task                              │
│ - ANY build, test, or dev server                                │
│                                                                 │
│ ABSOLUTELY PROHIBITED:                                          │
│ - Using Bash tool's run_in_background parameter                 │
│ - Using & or nohup to background commands                       │
│ - Calling tmux/wezterm commands directly                        │
│ - Running .sh files without 'bash' prefix on Windows            │
│ - Trying to "do it faster myself" without this skill            │
│                                                                 │
│ NO GIT REPO REQUIRED - This skill works anywhere                │
│                                                                 │
│ FOR SUB-AGENTS (ag:) → Use polydev-agent skill                  │
│ FOR PARALLEL DEV (wo:) → Use polydev skill (requires git)       │
└─────────────────────────────────────────────────────────────────┘
```

**If you violate these rules, the task WILL FAIL.**

---

## Script Path (MANDATORY)

**Scripts location:** `$HOME/.codex/polydev/scripts`

**Windows MUST use `bash` prefix:**

```bash
bash "$HOME/.codex/polydev/scripts/run-background.sh" <name> "<command>"
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

**All commands below use Windows format (with `bash` prefix).** On Linux/macOS, you can omit `bash`.

### Start Background Task

```bash
session_id=$(bash "$HOME/.codex/polydev/scripts/run-background.sh" build "npm run build")
# Returns: bg:bg-myproject:build.0
```

### Send Command to Session (SSH, REPL)

```bash
# Send command
bash "$HOME/.codex/polydev/scripts/send-to-session.sh" bg:bg-polydev:ssh.0 "docker ps"

# Send password (without pressing Enter)
bash "$HOME/.codex/polydev/scripts/send-to-session.sh" bg:bg-polydev:ssh.0 "mypassword" --no-enter
```

### Analyze Output Status

```bash
result=$(bash "$HOME/.codex/polydev/scripts/analyze-output.sh" bg:bg-myproj:build.0 --lines 20 --json)
# Returns: status (running|idle|success|failed|done)
```

### Wait for Pattern Match

```bash
bash "$HOME/.codex/polydev/scripts/wait-for-pattern.sh" "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300
# Exit: 0=success, 1=fail, 2=timeout
```

### View Raw Output

```bash
# Note: requires wo: prefix for --session
bash "$HOME/.codex/polydev/scripts/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 50
```

### Close Task

```bash
bash "$HOME/.codex/polydev/scripts/close-session.sh" bg:bg-myproj:build.0
```

### List All Sessions

```bash
bash "$HOME/.codex/polydev/scripts/list-sessions.sh"
```

---

## Typical Workflows

**All examples use Windows format (with `bash` prefix).** On Linux/macOS, you can omit `bash`.

### Build Task (Polling)

```bash
SCRIPTS="$HOME/.codex/polydev/scripts"

# Start
session_id=$(bash "$SCRIPTS/run-background.sh" build "npm run build")

# Poll and check
while true; do
  result=$(bash "$SCRIPTS/analyze-output.sh" "$session_id" --lines 20 --json)
  status=$(echo "$result" | jq -r '.status')

  case "$status" in
    success|done)
      echo "Task completed"
      break
      ;;
    failed)
      echo "Task failed"
      bash "$SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 50
      break
      ;;
  esac

  sleep 10
done

# Cleanup
bash "$SCRIPTS/close-session.sh" "$session_id"
```

### SSH Interactive Session

```bash
SCRIPTS="$HOME/.codex/polydev/scripts"

# 1. Start SSH connection
session_id=$(bash "$SCRIPTS/run-background.sh" ssh-server "ssh user@host")

# 2. Wait for connection (may need password)
sleep 3
bash "$SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 20

# 3. If password needed
bash "$SCRIPTS/send-to-session.sh" "$session_id" "mypassword"

# 4. Send commands
bash "$SCRIPTS/send-to-session.sh" "$session_id" "docker ps"

# 5. View results
sleep 2
bash "$SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 30

# 6. Close when done
bash "$SCRIPTS/close-session.sh" "$session_id"
```

### Wait for Pattern

```bash
SCRIPTS="$HOME/.codex/polydev/scripts"

# Start and wait
session_id=$(bash "$SCRIPTS/run-background.sh" test "npm test")

# Wait for success or failure
bash "$SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300

exit_code=$?
case $exit_code in
  0) echo "Tests passed" ;;
  1) echo "Tests failed" ;;
  2) echo "Timeout" ;;
esac

bash "$SCRIPTS/close-session.sh" "$session_id"
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
bash "$HOME/.codex/polydev/scripts/list-sessions.sh"
```

### Cannot See Output
```bash
bash "$HOME/.codex/polydev/scripts/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 100
```

### Session Stuck
```bash
bash "$HOME/.codex/polydev/scripts/close-session.sh" bg:myproj:build.0
bash "$HOME/.codex/polydev/scripts/run-background.sh" build "npm run build"
```

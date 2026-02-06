---
name: polydev
description: This skill should be used when executing 2+ independent tasks in parallel - orchestrates git worktrees with terminal sessions (tmux/wezterm).
version: 0.1.0
---

# Polydev

Parallel development orchestration using Git worktrees and terminal sessions.

---

## Session Type: wo: (Worktree Development)

**Prefix `wo:` = Parallel development** (git worktree + sub-Claude)

Choose skill by prefix:
- `bg:` → **terminal-task-runner** - NO git required (SSH, builds, tests)
- `ag:` → **agent-investigator** - NO git required (research, analysis)
- `wo:` → **polydev** (this skill) - REQUIRES git repo

---

## ⛔ Mandatory Constraints - Violation = Failure

```
┌─────────────────────────────────────────────────────────────────┐
│ THIS SKILL REQUIRES GIT REPOSITORY                              │
│ For non-git tasks, use other skills by prefix                   │
├─────────────────────────────────────────────────────────────────┤
│ USE THIS SKILL FOR:                                             │
│ - Parallel development on 2+ independent branches               │
│ - Spawning sub-Claude instances in isolated worktrees           │
│                                                                 │
│ ABSOLUTELY PROHIBITED:                                          │
│ - Calling wezterm/tmux commands directly                        │
│ - Writing git worktree add/remove commands yourself             │
│ - Deleting anything under .worktrees directory                  │
│ - Trying to "do it faster myself" without this skill            │
│                                                                 │
│ FOR BACKGROUND TASKS (bg:) → Use terminal-task-runner skill     │
│ FOR SUB-AGENTS (ag:) → Use agent-investigator skill             │
└─────────────────────────────────────────────────────────────────┘
```

**If these rules are violated, the task WILL FAIL.**

---

## Script Path (Must Follow)

**All scripts MUST be called via `$POLYDEV_SCRIPTS` variable. NEVER use relative path `./scripts/`**

### ⚠️ Windows Compatibility - CRITICAL

**On Windows (Git Bash/MINGW), scripts MUST be executed using `bash -c "$(cat ...)"` pattern:**

```bash
# Set script path variable (use plugin installation location)
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"

# Define helper function for Windows compatibility
run_polydev() {
    local script="$1"
    shift
    SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/$script")" -- "$@"
}

# ✅ CORRECT - Use run_polydev helper (works on all platforms)
run_polydev spawn-session.sh <workspace> <branch> <worktree-path> <plan-file>
run_polydev poll.sh .worktrees 10
run_polydev list-sessions.sh

# ❌ WRONG - Direct execution FAILS SILENTLY on Windows
"$POLYDEV_SCRIPTS/spawn-session.sh" args...  # Silent failure!
```

**Why this pattern?** Claude Code's Bash tool on Windows has an issue where direct script execution (`./script.sh` or `bash script.sh`) returns exit code 0 but produces no output and doesn't actually execute. The `bash -c "$(cat ...)"` pattern with `SCRIPT_DIR` env var reliably works.

**Why?** `./scripts/` relative path breaks when leaving plugin directory.

---

## Cost Control - Save Money

**Parallel agents (sub-agents) MUST use `sonnet` model!**

```
WILL BANKRUPT USER - The following will drain funds:
- Spawn multiple parallel agents with opus model
- Not specifying model parameter (inherits expensive main agent model)
- Using haiku for tasks requiring code capability (will fail repeatedly, wasting more)

CORRECT USAGE:
- Task tool: MUST specify model: "sonnet"
- Only exception: User explicitly says "use opus/haiku"
- Default is always sonnet, no matter how important the task
```

**Code Example:**
```javascript
// WRONG - will inherit main agent's opus model
Task({ prompt: "...", subagent_type: "general-purpose" })

// CORRECT - explicitly specify sonnet
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })
```

---

## Absolute Prohibition

**Use scripts. Absolutely forbidden to write terminal commands yourself.**

```
BANNED FOREVER - The following are permanently prohibited:
- Calling wezterm cli spawn / tmux new-session yourself
- Calling wezterm cli send-text / tmux send-keys yourself
- Calling wezterm cli list / tmux list-sessions yourself
- Calling wezterm cli kill-pane / tmux kill-session yourself
- Reading terminal output yourself to determine status
- Writing git worktree add/remove commands yourself
- Deleting anything under .worktrees directory yourself
- Using relative path ./scripts/ (breaks when leaving directory)
- Any thought of "scripts are too cumbersome, I'll write it faster myself"

CLEANUP ORDER VIOLATION - Will cause "Permission denied":
- Deleting worktree before closing session (terminal holds directory lock!)
- Using rm -rf .worktrees/xxx instead of git worktree remove
- Skipping list-sessions.sh verification before deletion
```

---

## Script Usage Constraints (Scenario to Script Mapping)

### Scenario A: Create Worktree + Claude Session
**Script**: `spawn-session.sh`
**Parameters**: `<workspace> <branch> <worktree-path> <plan-file> [verify] [fallback] [--verbose]`
**Output**: TOON event log lines
**Returns**: pane_id (numeric identifier for the terminal pane)

**⚠️ WORKTREE PATH RULE - MUST FOLLOW:**
```
worktree-path MUST be: .worktrees/<branch-name>

✅ CORRECT: .worktrees/feature-auth
✅ CORRECT: .worktrees/fix-login-bug
❌ WRONG:   /some/other/path
❌ WRONG:   ./src/components
❌ WRONG:   feature-auth (missing .worktrees/ prefix)
```

**⚠️ WORKSPACE RULE - CRITICAL FOR WINDOW GROUPING:**
```
workspace determines window grouping. Same workspace = same window with multiple tabs.

✅ CORRECT - All parallel tasks use SAME workspace name:
   run_polydev spawn-session.sh my-project feature/auth ...
   run_polydev spawn-session.sh my-project feature/api ...
   run_polydev spawn-session.sh my-project feature/ui ...
   → Creates 1 window with 3 tabs

❌ WRONG - Different workspace names create separate windows:
   run_polydev spawn-session.sh ws1 feature/auth ...
   run_polydev spawn-session.sh ws2 feature/api ...
   run_polydev spawn-session.sh ws3 feature/ui ...
   → Creates 3 separate windows (BAD!)

Rule: Use project name as workspace for all parallel tasks.
```

```bash
run_polydev spawn-session.sh myproject feature/auth .worktrees/feature-auth PLAN.md
```

### Scenario B: Monitor All Worktree Status (Must Call in Loop)
**Script**: `poll.sh`
**Parameters**: `<worktrees-dir> <timeout-seconds> [--verbose]`
**Output**: TOON status lines (one per worktree)
**Returns**: Exits with status info when needs attention

```bash
# Output format (TOON):
# worktree=.worktrees/feature,branch=feature,overall_status=in_progress,agent_status=active,last_update=2025-01-09T10:30:00Z,pane_id=5

result=$(run_polydev poll.sh .worktrees 10)
```

### Scenario C: Restore Crashed Session
**Script**: `restore-session.sh`
**Parameters**: `<worktree-path> [--force]`

```bash
run_polydev restore-session.sh .worktrees/auth
run_polydev restore-session.sh .worktrees/auth --force  # Force restart
```

### Scenario D: Send Command to Worktree Session (Has task.toon)
**Script**: `wo-send-command.sh`
**Parameters**: `<worktree-path> "<command>" [--no-enter]`
**Prerequisite**: Worktree must have task.toon file

```bash
run_polydev wo-send-command.sh .worktrees/auth "npm test"
run_polydev wo-send-command.sh .worktrees/auth "password" --no-enter
```

### Scenario E: Send Command to Any Session (SSH, REPL, etc.)
**Script**: `send-to-session.sh`
**Parameters**: `<pane_id> "<command>" [--no-enter]`

```bash
# Send command to SSH session (use pane_id from list-sessions.sh)
run_polydev send-to-session.sh 5 "docker ps"
```

### Scenario F: Focus on a Session (Manual)
Use wezterm/tmux directly to focus on a session. This is a manual operation for humans only.

### Scenario G: List All Active Sessions
**Script**: `list-sessions.sh`
**Parameters**: `[workspace]` (optional filter)
**Output**: TOON status lines

```bash
# Output format (TOON):
# session_id=wo:myproject:feature.0,status=alive,cwd=/path/to/worktree

run_polydev list-sessions.sh
run_polydev list-sessions.sh myproject
```

### Scenario H: Close/Terminate Session
**Script**: `close-session.sh`
**Parameters**: `<worktree_path>` or `--pane-id <pane_id>`
**Output**: TOON event log

```bash
# By worktree path (preferred for wo: sessions)
run_polydev close-session.sh .worktrees/feature-auth

# By pane_id (for bg:/ag: sessions without worktree)
run_polydev close-session.sh --pane-id 5
```

### Scenario I: Read Session Current Screen Content
**Script**: `capture-screen.sh`
**Parameters**: `<worktree_path> [--lines N]` or `--pane-id <pane_id> [--lines N]`

```bash
# Output: Terminal screen content (no headers)

# Via worktree path (preferred for wo: sessions)
run_polydev capture-screen.sh .worktrees/auth --lines 50

# Via pane_id (for bg:/ag: sessions without worktree)
run_polydev capture-screen.sh --pane-id 5 --lines 50
```

### Scenario J: Cleanup Worktree (After Completion)

**⚠️ CLEANUP ORDER IS MANDATORY - VIOLATION CAUSES "Permission denied" ERROR:**

```
┌─────────────────────────────────────────────────────────────────┐
│ CLEANUP MUST FOLLOW THIS EXACT ORDER:                           │
│                                                                 │
│ 1. close-session.sh  → Close terminal (releases directory lock) │
│ 2. list-sessions.sh  → Verify session is gone                   │
│ 3. git worktree remove → Delete worktree                        │
│ 4. git branch -D     → Delete branch (optional)                 │
│                                                                 │
│ ❌ SKIPPING STEP 1 = "Permission denied" error                  │
│ ❌ Direct rm -rf .worktrees/xxx = FORBIDDEN                     │
└─────────────────────────────────────────────────────────────────┘
```

**Step 1**: Close session (releases directory lock)
```bash
run_polydev close-session.sh .worktrees/feature-auth
```

**Step 2**: Verify session is closed
```bash
run_polydev list-sessions.sh  # Should show "(No sessions found)" or not include your session
```

**Step 3**: Ask user for confirmation before deleting worktree

**Step 4**: Remove worktree with git command
```bash
git worktree remove .worktrees/auth --force
git worktree prune  # Clean up stale references
```

**Step 5**: Delete branch (optional)
```bash
git branch -D feature-auth
```

**NEVER use `cleanup-worktree.sh`** - it has interactive prompts that cause automation to hang.

**NEVER use `rm -rf .worktrees/xxx`** - always use `git worktree remove` after closing sessions.

### Scenario K: Start Background Command (No Sub-Claude)
**Script**: `run-background.sh`
**Parameters**: `<name> "<command>" [--cwd <dir>] [--verbose]`
**Returns**: pane_id (numeric identifier)

```bash
pane_id=$(run_polydev run-background.sh build "npm run build")
```

### Scenario L: Start Investigation Agent
**Script**: `spawn-agent.sh`
**Parameters**: `<name> --prompt "<task>" --report <report-path> --cwd <project-dir>`

**Note**: `--cwd` is **required** - the script will fail without it.

```bash
pane_id=$(run_polydev spawn-agent.sh auth-research \
  --prompt "Analyze authentication mechanism in project" \
  --report ./.agent-reports/auth.md \
  --cwd "$(git rev-parse --show-toplevel)")
```

---

## Three Terminal Hosting Scenarios

| Scenario | Script | Sub-Claude | Status Communication |
|----------|--------|------------|---------------------|
| **Parallel Dev** | spawn-session.sh | Yes | task.toon |
| **Background Cmd** | run-background.sh | No | Terminal output analysis |
| **Agent Investigation** | spawn-agent.sh | Yes | Report file + [AGENT_DONE] |

### Session ID Format (Human-Readable Only)

**Note**: `session_id` is for human debugging only. Scripts use `pane_id` or `worktree_path`.

```
wo:workspace:branch.0    # Parallel dev (worktree)
bg:workspace:name.0      # Background cmd (background)
ag:workspace:name.0      # Agent investigation (agent)
```

Use `list-sessions.sh` to see both session_id (for humans) and pane_id (for scripts).

---

## Poll Loop - Must Monitor Continuously After Starting

```bash
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"

# Define helper function for Windows compatibility
run_polydev() {
    local script="$1"
    shift
    SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/$script")" -- "$@"
}

# After starting all sessions, immediately enter monitoring loop - cannot skip!
while branches_remaining; do
  result=$(run_polydev poll.sh .worktrees 10)  # Must call!

  # Parse TOON output lines
  echo "$result" | while IFS=',' read -r key1 rest; do
    worktree=$(echo "$key1" | cut -d'=' -f2)
    # Extract other fields: overall_status, agent_status, session_id, etc.
  done

  # Handle each worktree based on status
  # overall_status: in_progress, completed, hil, blocked, conflict, rejected
  # agent_status: active, idle, crashed

  case "$agent_status" in
    crashed) run_polydev restore-session.sh "$worktree" --force ;;
    idle)    # Check if restart needed
  esac

  case "$overall_status" in
    completed) # Verify and merge
    hil)       # Human intervention (human must decide)
    blocked)   # Needs help (main agent tries to solve, escalate to hil if fails)
  esac
done
```

**Prohibited:** Starting sessions and then ignoring them, expecting sub-agents to complete on their own.

---

## Status Source: Only Trust task.toon

- Read `<worktree>/task.toon` to get `overall_status` and `agent_status`
- Do NOT guess sub-agent status
- Do NOT read terminal output to determine status

---

## Related Skills

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `polydev:brainstorming` | Explore requirements, decompose tasks | Before complex parallel work |
| `polydev:writing-plans` | Create detailed implementation plans | For each parallel task |
| `polydev:worktree-executor` | Execute plans in worktrees | Automatically by sub-agents |
| `polydev:agent-investigator` | Run investigation tasks | For read-only research |
| `polydev:terminal-task-runner` | Run background commands | For builds, tests, servers |

---

## Core Flow

```
User request
    |
Phase 0: Brainstorming (Optional)
    - Use polydev:brainstorming for complex/unclear requests
    |
Phase 1: Verification Strategy Research
    |
Phase 2: Task Decomposition
    |
Phase 3: User Confirmation
    |
Phase 4: Parallel Execution (spawn-session.sh + poll.sh loop)
    |
Phase 5: Incremental Verify & Merge
    |
Phase 6: Cleanup (Human Confirms)
```

---

## Verification Levels

| Level | Name | Verification Scope | Use Case |
|-------|------|-------------------|----------|
| L0 | skip | No verification | Docs, comments, config |
| L1 | compile | Build only | Minor changes, formatting |
| L2 | unit | Build + unit tests | Regular features, utilities |
| L3 | integration | + integration tests | Module interaction, API endpoints |
| L4 | e2e | + end-to-end tests | Core user flows |
| L5 | manual | + human verification | Cannot automate, critical features |

---

## Session Recovery

| Scenario | agent_status | Solution |
|----------|--------------|----------|
| **Session crashed** | crashed | `run_polydev restore-session.sh <worktree> --force` |
| **Claude stopped** | idle | `run_polydev restore-session.sh <worktree>` |
| **Claude stuck** | active (no update for long time) | `run_polydev restore-session.sh <worktree> --force` |

---

## Status Values

### overall_status

| Status | Meaning |
|--------|---------|
| `pending` | Assigned, not started |
| `in_progress` | Branch agent working |
| `completed` | Branch done, awaiting verification |
| `blocked` | Needs help (main agent might solve) |
| `hil` | Human intervention required (human must decide) |
| `merged` | Merge successful |

### agent_status

| Status | Meaning |
|--------|---------|
| `active` | Claude active |
| `idle` | Claude unexpectedly stopped |
| `crashed` | Process does not exist |

---

## Iron Rules

1. **All scripts via `$POLYDEV_SCRIPTS`, never `./scripts/`**
2. **Research verification strategy first, then decompose tasks**
3. **Execute by verification level, no skipping**
4. **Restore session first when crashed, then continue**
5. **Parallel agents MUST use sonnet! Unless user explicitly requests another model!**
6. **Cleanup order: close-session → verify → git worktree remove (NEVER skip close-session!)**

---

## Additional Resources

### Reference Files

- **`references/architecture.md`** - Detailed architecture, directory structure, and session types
- **`references/verification-levels.md`** - Verification level definitions and workflows

### Related Skills

| Skill | Purpose |
|-------|---------|
| `polydev:brainstorming` | Explore requirements, decompose tasks |
| `polydev:writing-plans` | Create detailed implementation plans |
| `polydev:worktree-executor` | Execute plans in worktrees |
| `polydev:agent-investigator` | Run investigation tasks |
| `polydev:terminal-task-runner` | Run background commands |

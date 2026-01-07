---
name: polydev
description: "You MUST use this when executing 2+ independent tasks in parallel - orchestrates git worktrees with terminal sessions (tmux/wezterm)"
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

## ⛔ MANDATORY CONSTRAINTS - VIOLATION = FAILURE

```
┌─────────────────────────────────────────────────────────────────┐
│ THIS SKILL REQUIRES GIT REPOSITORY                              │
│ For non-git tasks, use other skills by prefix                   │
├─────────────────────────────────────────────────────────────────┤
│ YOU MUST USE THIS SKILL FOR:                                    │
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

**If you violate these rules, the task WILL FAIL.**

---

## Script Path (Must Follow)

**All scripts MUST be called via `$POLYDEV_SCRIPTS` variable. NEVER use relative path `./scripts/`**

```bash
# Set script path variable (use plugin installation location)
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# Then call using the variable
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```

**Why?** `./scripts/` relative path breaks when leaving plugin directory.

---

## COST CONTROL - Save Money

**Parallel agents (sub-agents) MUST use `sonnet` model! Otherwise you will bankrupt your user!**

```
WILL BANKRUPT YOUR USER - The following will drain funds:
- Spawn multiple parallel agents with opus model
- Not specifying model parameter (inherits expensive main agent model)
- Using haiku for tasks requiring code capability (will fail repeatedly, wasting more)
- "This task is important, opus is better" -- WRONG! sonnet is good enough!

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

## ABSOLUTE PROHIBITION

**You MUST use scripts. Absolutely forbidden to write terminal commands yourself.**

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
```

---

## Script Usage Constraints (Scenario to Script Mapping)

### Scenario A: Create Worktree + Claude Session
**Script**: `spawn-session.sh`
**Parameters**: `<workspace> <branch> <worktree-path> <plan-file>`
**Returns**: session_id (format: `wo:<workspace>:<branch>.0`)

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
   spawn-session.sh my-project feature/auth ...
   spawn-session.sh my-project feature/api ...
   spawn-session.sh my-project feature/ui ...
   → Creates 1 window with 3 tabs

❌ WRONG - Different workspace names create separate windows:
   spawn-session.sh ws1 feature/auth ...
   spawn-session.sh ws2 feature/api ...
   spawn-session.sh ws3 feature/ui ...
   → Creates 3 separate windows (BAD!)

Rule: Use project name as workspace for all parallel tasks.
```

```bash
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature/auth .worktrees/feature-auth PLAN.md
```

### Scenario B: Monitor All Worktree Status (Must Call in Loop)
**Script**: `poll.sh`
**Parameters**: `<worktrees-dir> <timeout-seconds>`
**Returns**: Status change information

```bash
result=$("$POLYDEV_SCRIPTS/poll.sh" .worktrees 10)
```

### Scenario C: Restore Crashed Session
**Script**: `restore-session.sh`
**Parameters**: `<worktree-path> [--force]`

```bash
"$POLYDEV_SCRIPTS/restore-session.sh" .worktrees/auth
"$POLYDEV_SCRIPTS/restore-session.sh" .worktrees/auth --force  # Force restart
```

### Scenario D: Send Command to Worktree Session (Has task.toon)
**Script**: `wo-send-command.sh`
**Parameters**: `<worktree-path> "<command>" [--no-enter]`
**Prerequisite**: Worktree must have task.toon file

```bash
"$POLYDEV_SCRIPTS/wo-send-command.sh" .worktrees/auth "npm test"
"$POLYDEV_SCRIPTS/wo-send-command.sh" .worktrees/auth "password" --no-enter
```

### Scenario E: Send Command to Any Session (SSH, REPL, etc.)
**Script**: `send-to-session.sh`
**Parameters**: `<session_id> "<command>" [--no-enter]`
**session_id format**: `bg:xxx`, `wo:xxx`, `ag:xxx`

```bash
# Send command to SSH session
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh.0 "docker ps"
```

### Scenario F: Focus on a Session
**Script**: `focus-session.sh`
**Parameters**: `<worktree-path>` or `<session_id>`

```bash
"$POLYDEV_SCRIPTS/focus-session.sh" .worktrees/auth
```

### Scenario G: List All Active Sessions
**Script**: `list-sessions.sh`
**Parameters**: `[workspace]` (optional filter)

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/list-sessions.sh" myproject
```

### Scenario H: Close/Terminate Session
**Script**: `close-session.sh`
**Parameters**: `<session_id>`

```bash
"$POLYDEV_SCRIPTS/close-session.sh" wo:myproject:feature-auth.0
"$POLYDEV_SCRIPTS/close-session.sh" bg:bg-polydev:build.0
```

### Scenario I: Read Session Current Screen Content
**Script**: `capture-screen.sh`
**Parameters**: `--session <wo:session_id> --lines <N>` or `<worktree-path> [--lines N]`
**Note**: `--session` parameter requires `wo:` prefix!

```bash
# Via worktree path
"$POLYDEV_SCRIPTS/capture-screen.sh" .worktrees/auth --lines 50

# Via session ID (must use wo: prefix)
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-polydev:build.0 --lines 50
```

### Scenario J: Cleanup Worktree (After Completion)
**Script**: `cleanup-worktree.sh`
**Parameters**: `<worktree-path>`

```bash
"$POLYDEV_SCRIPTS/cleanup-worktree.sh" .worktrees/auth
```

### Scenario K: Start Background Command (No Sub-Claude)
**Script**: `run-background.sh`
**Parameters**: `<name> "<command>" [--cwd <dir>]`
**Returns**: session_id (format: `bg:<workspace>:<name>.0`)

```bash
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")
```

### Scenario L: Analyze Background Task Output Status
**Script**: `analyze-output.sh`
**Parameters**: `<session_id> --lines <N> [--json]`

```bash
result=$("$POLYDEV_SCRIPTS/analyze-output.sh" bg:bg-myproj:build.0 --lines 20 --json)
```

### Scenario M: Wait for Pattern Match
**Script**: `wait-for-pattern.sh`
**Parameters**: `<session_id> --success "<pattern>" [--fail "<pattern>"] [--timeout <seconds>]`

```bash
"$POLYDEV_SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "Build completed" \
  --fail "Error" \
  --timeout 300
```

### Scenario N: Start Investigation Agent
**Script**: `spawn-agent.sh`
**Parameters**: `<name> --prompt "<task>" --report <report-path>`

```bash
session_id=$("$POLYDEV_SCRIPTS/spawn-agent.sh" auth-research \
  --prompt "Analyze authentication mechanism in project" \
  --report ./.agent-reports/auth.md)
```

---

## Three Terminal Hosting Scenarios

| Scenario | Script | Sub-Claude | Status Communication |
|----------|--------|------------|---------------------|
| **Parallel Dev** | spawn-session.sh | Yes | task.toon |
| **Background Cmd** | run-background.sh | No | Terminal output analysis |
| **Agent Investigation** | spawn-agent.sh | Yes | Report file + [AGENT_DONE] |

### Session ID Format

```
wo:workspace:branch.0    # Parallel dev (worktree)
bg:workspace:name.0      # Background cmd (background)
ag:workspace:name.0      # Agent investigation (agent)
```

---

## Poll Loop - Must Monitor Continuously After Starting

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# After starting all sessions, immediately enter monitoring loop - cannot skip!
while branches_remaining; do
  result=$("$POLYDEV_SCRIPTS/poll.sh" .worktrees 10)  # Must call!

  worktree=$(echo "$result" | cut -d',' -f1)
  overall_status=$(echo "$result" | cut -d',' -f3)
  agent_status=$(echo "$result" | cut -d',' -f4)

  case "$agent_status" in
    crashed) "$POLYDEV_SCRIPTS/restore-session.sh" "$worktree" --force ;;
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
| **Session crashed** | crashed | `"$POLYDEV_SCRIPTS/restore-session.sh" <worktree> --force` |
| **Claude stopped** | idle | `"$POLYDEV_SCRIPTS/restore-session.sh" <worktree>` |
| **Claude stuck** | active (no update for long time) | `"$POLYDEV_SCRIPTS/restore-session.sh" <worktree> --force` |

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

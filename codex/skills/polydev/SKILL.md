---
name: polydev
description: |
  Parallel development: spawn multiple Codex instances on separate git branches.
  REQUIRES: Git repository (uses worktrees for isolation)
  WHEN: 2+ independent coding tasks that can run in parallel on different branches
  WHEN NOT: Single task, background commands (use polydev-runner), non-git work
  TRIGGERS: parallel development, multiple features, implement X Y and Z, worktree
---

# Polydev - Parallel Development Orchestration

Spawn multiple Codex CLI instances in isolated Git worktrees to work on independent tasks simultaneously.

---

## Session Type: wo: (Worktree Development)

**Prefix `wo:` = Parallel development** (git worktree + sub-Codex)

Choose skill by prefix:
- `bg:` → **polydev-runner** - NO git required
- `ag:` → **polydev-agent** - NO git required
- `wo:` → **polydev** (this skill) - REQUIRES git repo

---

## ⛔ MANDATORY CONSTRAINTS - VIOLATION = FAILURE

```
┌─────────────────────────────────────────────────────────────────┐
│ THIS SKILL REQUIRES GIT REPOSITORY                              │
│ For non-git tasks, use polydev-runner instead                   │
├─────────────────────────────────────────────────────────────────┤
│ YOU MUST USE THIS SKILL FOR:                                    │
│ - Parallel development on 2+ independent branches               │
│ - Spawning sub-Codex instances in isolated worktrees            │
│                                                                 │
│ ABSOLUTELY PROHIBITED:                                          │
│ - Calling wezterm/tmux commands directly                        │
│ - Writing git worktree add/remove commands yourself             │
│ - Running .sh files without 'bash' prefix on Windows            │
│ - Deleting anything under .worktrees directory                  │
│ - Trying to "do it faster myself" without this skill            │
│                                                                 │
│ FOR BACKGROUND TASKS (bg:) → Use polydev-runner skill           │
│ FOR SUB-AGENTS (ag:) → Use polydev-agent skill                  │
└─────────────────────────────────────────────────────────────────┘
```

**If you violate these rules, the task WILL FAIL.**

---

## Script Path (MANDATORY)

**Scripts location:** `$HOME/.codex/polydev/scripts`

**Windows MUST use `bash` prefix:**

```bash
bash "$HOME/.codex/polydev/scripts/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
bash "$HOME/.codex/polydev/scripts/poll.sh" .worktrees 10
bash "$HOME/.codex/polydev/scripts/list-sessions.sh"
```

---

## Core Workflow

```
User request with 2+ independent tasks
    |
Phase 1: Task Decomposition
    - Identify independent tasks
    - Determine verification level for each
    |
Phase 2: Plan Creation
    - Create PLAN.md for each task
    - Plans go in .worktrees/<branch>/PLAN.md
    |
Phase 3: User Confirmation
    - Show task breakdown and verification strategy
    - Wait for approval before spawning
    |
Phase 4: Parallel Execution
    - spawn-session.sh for each task
    - poll.sh loop for monitoring
    |
Phase 5: Verify & Merge
    - Run verification per level
    - Merge completed branches
    |
Phase 6: Cleanup (Human Confirms)
```

---

## Script Usage Reference

### Spawn Worktree + Codex Session

```bash
# Windows (MUST use bash prefix):
bash "$HOME/.codex/polydev/scripts/spawn-session.sh" myproject feature/auth .worktrees/auth PLAN.md

# With approval mode:
CODEX_APPROVAL=full-auto bash "$HOME/.codex/polydev/scripts/spawn-session.sh" ...

# Returns: session_id (format: wo:workspace:branch.0)
```

### Monitor All Worktrees (MUST call in loop)

```bash
# Windows monitoring loop:
while branches_remaining; do
  result=$(bash "$HOME/.codex/polydev/scripts/poll.sh" .worktrees 10)

  worktree=$(echo "$result" | cut -d',' -f1)
  overall_status=$(echo "$result" | cut -d',' -f3)
  agent_status=$(echo "$result" | cut -d',' -f4)

  case "$agent_status" in
    crashed) bash "$HOME/.codex/polydev/scripts/restore-session.sh" "$worktree" --force ;;
    idle)    # Check if restart needed
  esac

  case "$overall_status" in
    completed) # Verify and merge
    hil)       # Human intervention required
    blocked)   # Main agent tries to solve
  esac
done
```

### Other Scripts

All scripts via `bash "$HOME/.codex/polydev/scripts/<name>.sh"`:

| Scenario | Command |
|----------|---------|
| Restore crashed session | `bash "$HOME/.codex/polydev/scripts/restore-session.sh" <worktree-path> [--force]` |
| Send command to worktree | `bash "$HOME/.codex/polydev/scripts/wo-send-command.sh" <worktree-path> "<cmd>"` |
| Capture terminal output | `bash "$HOME/.codex/polydev/scripts/capture-screen.sh" --session <id> --lines N` |
| List active sessions | `bash "$HOME/.codex/polydev/scripts/list-sessions.sh" [workspace]` |
| Close session | `bash "$HOME/.codex/polydev/scripts/close-session.sh" <session_id>` |
| Cleanup worktree | `bash "$HOME/.codex/polydev/scripts/cleanup-worktree.sh" <worktree-path>` |

---

## Status Communication

Sub-Codex instances communicate via `task.toon` files in each worktree.

**Status Source:** Only trust `<worktree>/task.toon`

### overall_status Values

| Status | Meaning | Main Agent Action |
|--------|---------|-------------------|
| `pending` | Not started | Wait |
| `in_progress` | Working | Monitor |
| `completed` | Done | Verify and merge |
| `blocked` | Needs help | Try to solve, escalate if fails |
| `hil` | Human needed | Alert user |
| `merged` | Successfully merged | Cleanup |

### agent_status Values

| Status | Meaning | Action |
|--------|---------|--------|
| `active` | Codex running | Continue monitoring |
| `idle` | Codex stopped | `restore-session.sh` |
| `crashed` | Process gone | `restore-session.sh --force` |

---

## Verification Levels

| Level | Name | Verification Scope | Use Case |
|-------|------|-------------------|----------|
| L0 | skip | None | Docs, config |
| L1 | compile | Build only | Minor changes |
| L2 | unit | Build + unit tests | Features |
| L3 | integration | + integration tests | API endpoints |
| L4 | e2e | + end-to-end tests | User flows |
| L5 | manual | + human verification | Critical features |

---

## Session ID Format

```
wo:workspace:branch.0    # Worktree sessions (parallel dev)
bg:workspace:name.0      # Background commands
ag:workspace:name.0      # Investigation agents
```

---

## Example Session

```
User: "Implement user auth, add dark mode, and fix the login bug"

Codex:
1. Decompose into 3 independent tasks
2. Create PLAN.md for each:
   - .worktrees/feature-auth/PLAN.md
   - .worktrees/feature-dark-mode/PLAN.md
   - .worktrees/fix-login-bug/PLAN.md
3. Spawn 3 worktree sessions
4. Monitor via poll.sh loop
5. Verify and merge as each completes
```

---

## Iron Rules

1. **Windows: ALWAYS use `bash "$HOME/.codex/polydev/scripts/<name>.sh"` to run scripts**
2. **Never spawn without creating PLAN.md first**
3. **Always monitor with poll.sh loop after spawning**
4. **Restore crashed sessions before continuing**
5. **Human confirms cleanup before deleting worktrees**

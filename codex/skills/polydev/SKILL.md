---
name: polydev
description: |
  Parallel development orchestration using Git worktrees.
  WHEN: User has 2+ independent tasks, mentions "parallel", "simultaneously", "multiple features/tasks"
  WHEN NOT: Single task, sequential work, simple file edits
  TRIGGERS: parallel, worktree, multiple tasks, simultaneously, independent branches
---

# Polydev - Parallel Development Orchestration

Spawn multiple Codex CLI instances in isolated Git worktrees to work on independent tasks simultaneously.

---

## Script Path (MANDATORY)

**All scripts via `$POLYDEV_SCRIPTS`. NEVER use relative paths.**

```bash
# Verify path is set
echo "$POLYDEV_SCRIPTS"

# Spawn worktree session
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>

# Monitor
"$POLYDEV_SCRIPTS/poll.sh" .worktrees 10
```

---

## ABSOLUTE PROHIBITION

```
BANNED FOREVER - The following are permanently prohibited:
- Calling wezterm/tmux commands yourself
- Writing git worktree add/remove commands yourself
- Using relative path ./scripts/
- Deleting anything under .worktrees directory
- Any thought of "scripts are too cumbersome, I'll write it faster myself"
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
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
# Example:
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature/auth .worktrees/auth PLAN.md
# Returns: session_id (format: wo:workspace:branch.0)

# Control approval mode via environment variable:
CODEX_APPROVAL=full-auto "$POLYDEV_SCRIPTS/spawn-session.sh" ...
```

### Monitor All Worktrees (MUST call in loop)

```bash
while branches_remaining; do
  result=$("$POLYDEV_SCRIPTS/poll.sh" .worktrees 10)

  worktree=$(echo "$result" | cut -d',' -f1)
  overall_status=$(echo "$result" | cut -d',' -f3)
  agent_status=$(echo "$result" | cut -d',' -f4)

  case "$agent_status" in
    crashed) "$POLYDEV_SCRIPTS/restore-session.sh" "$worktree" --force ;;
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

| Scenario | Script | Parameters |
|----------|--------|------------|
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |
| Send command to session | `send-command.sh` | `<worktree-path> "<cmd>"` |
| Capture terminal output | `capture-screen.sh` | `--session <session_id> --lines N` |
| List active sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<session_id>` |
| Cleanup worktree | `cleanup-worktree.sh` | `<worktree-path>` |

All via `$POLYDEV_SCRIPTS/`.

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

1. **All scripts via `$POLYDEV_SCRIPTS`, never relative paths**
2. **Never spawn without creating PLAN.md first**
3. **Always monitor with poll.sh loop after spawning**
4. **Restore crashed sessions before continuing**
5. **Human confirms cleanup before deleting worktrees**

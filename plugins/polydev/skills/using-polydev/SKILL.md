---
name: using-polydev
description: This skill should be used at conversation start when user mentions parallel, multiple tasks/features, worktrees, lists 2+ independent work items, or similar keywords - determines which polydev skill to use.
version: 0.1.0
---

# Using Polydev Skills

## When to Use This Skill

Use polydev skills when the user mentions:
- "parallel" / "simultaneously" / "at the same time"
- "multiple features" / "multiple tasks"
- Lists 2+ independent work items
- "worktree" / "branch" (in context of parallel work)
- "background" / "long-running command"

## Script Path (Main Agent Must Follow)

**All scripts MUST be called via `$POLYDEV_SCRIPTS` variable. NEVER use `./scripts/`**

```bash
# 自动由 SessionStart hook 写入，无需手动设置路径
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)

"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```

> 如果 `~/.polydev/scripts-path` 不存在，说明 hook 未执行。手动设置:
> `POLYDEV_SCRIPTS="$CLAUDE_PLUGIN_ROOT/scripts"`

---

## Skill Selection Flow

```
User message received
    |
Contains parallel/multiple keywords?
    | YES
Is it complex/unclear? --YES--> Run /polydev-brainstorm
    | NO
Ready to execute? --YES--> Use polydev:polydev skill
    |
Need detailed plans? --YES--> Use polydev:writing-plans skill
    |
Running background command? --YES--> Use polydev:terminal-task-runner skill
```

## Available Skills

| Skill | When to Use | Who Uses |
|-------|-------------|----------|
| `/polydev-brainstorm` | Complex/unclear requirements, need to decompose | Main Agent |
| `polydev:polydev` | Ready to execute parallel tasks | Main Agent |
| `polydev:writing-plans` | Need detailed implementation plans | Main Agent |
| `polydev:terminal-task-runner` | Long-running commands (builds, tests, servers, SSH) | Main Agent |
| `polydev:worktree-executor` | Execute in isolated worktree | Sub-Agent only |
| `polydev:agent-investigator` | Read-only research tasks | Sub-Agent only |

---

## Script Quick Reference (For Main Agent)

**All scripts must be called via `$POLYDEV_SCRIPTS` variable.**

| Scenario | Script | Parameters |
|----------|--------|------------|
| Create worktree + Claude | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |
| Send to worktree | `wo-send-command.sh` | `<worktree-path> "<cmd>"` |
| Send to any session | `send-to-session.sh` | `<pane_id> "<cmd>"` |
| Read screen output | `capture-screen.sh` | `--pane-id <id> --lines N` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<worktree_path>` or `--pane-id <id>` |
| Start background command | `run-background.sh` | `<name> "<cmd>"` |
| Start Claude sub-agent | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path> --cwd <dir>` |
| Start Codex CLI session | `spawn-codex.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |
| Start Gemini CLI session | `spawn-gemini.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |

**Example calls:**
```bash
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature/auth .worktrees/feature-auth PLAN.md
"$POLYDEV_SCRIPTS/poll.sh" .worktrees 10
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

---

## Red Flags - STOP and Check Polydev

If the main agent thinks:

| Thought | Reality |
|---------|---------|
| "Execute these sequentially" | If independent, parallelize. Check polydev. |
| "Simple enough to do directly" | 2+ tasks = potential parallelism. Check. |
| "Don't need the overhead" | Polydev saves time on multi-task work. |
| "Explore first" | Run /polydev-brainstorm to explore properly. |
| "Parallelize later" | Parallelize NOW if tasks are independent. |

**All of these mean: Check polydev skills first.**

## Quick Decision Guide

**User says "implement X, Y, and Z":**
1. Are X, Y, Z independent? -> polydev:polydev
2. Need clarification? -> /polydev-brainstorm
3. Need detailed plans? -> polydev:writing-plans first

**User says "run this build/test":**
1. Will it take > 30 seconds? -> polydev:terminal-task-runner
2. Need to monitor output? -> polydev:terminal-task-runner

**User says "SSH to server and run commands":**
1. Use polydev:terminal-task-runner
2. Use `run-background.sh` to start SSH
3. Use `send-to-session.sh` to send subsequent commands
4. Use `capture-screen.sh` to read output

**User says "research X":**
1. Read-only analysis? -> Use spawn-agent.sh (Claude), spawn-codex.sh (Codex), or spawn-gemini.sh (Gemini)
2. Need parallel research? -> Multiple agents with different AI backends

## Cost Control Reminder

**Sub-agents MUST use `model: "sonnet"`** unless user explicitly requests otherwise.

```javascript
// Correct
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })

// Wrong - will bankrupt user
Task({ prompt: "...", subagent_type: "general-purpose" })
```

## Integration

This skill is the entry point. After determining which skill to use:

```
using-polydev (this skill)
    |
/polydev-brainstorm (if complex)
    |
polydev:writing-plans (if need plans)
    |
polydev:polydev (execution)
    |
polydev:worktree-executor (per-branch, sub-agent)
```

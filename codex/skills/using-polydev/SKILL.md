---
name: using-polydev
description: |
  Entry point for polydev skills. Use when user mentions: parallel, multiple tasks, worktrees, background, SSH, or lists 2+ independent work items.
  Determines which polydev skill to use based on task type.
  TRIGGERS: parallel, simultaneously, multiple features, background, long-running, SSH, build, test, server
---

<CRITICAL>
If the user mentions ANY of these, you MUST check polydev skills:

- "parallel" / "simultaneously" / "at the same time"
- "multiple features" / "multiple tasks"
- Lists 2+ independent work items
- "worktree" / "branch" (in context of parallel work)
- "background" / "long-running command"
- "SSH" / "remote server"

This is NOT optional. If there's even a 10% chance polydev applies, CHECK IT.
</CRITICAL>

# Using Polydev Skills

---

## Session Type Selection by Prefix

| Prefix | Skill | Git Required | Use Case |
|--------|-------|:------------:|----------|
| `bg:` | **polydev-runner** | ❌ | SSH, builds, tests, servers |
| `ag:` | **polydev-agent** | ❌ | Research, analysis, investigation |
| `wo:` | **polydev** | ✅ | Parallel development on branches |

---

## Script Path (MANDATORY)

**Scripts location:** `$HOME/.codex/polydev/scripts`

**Windows MUST use `bash` prefix:**

```bash
bash "$HOME/.codex/polydev/scripts/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
bash "$HOME/.codex/polydev/scripts/run-background.sh" <name> "<command>"
```

---

## Skill Selection Flow

```
User message received
    |
Contains parallel/multiple keywords?
    | YES
Is it complex/unclear? --YES--> Clarify requirements first
    | NO
Ready to execute? --YES--> Use polydev skill
    |
Need detailed plans? --YES--> Use polydev-plans skill
    |
Running background command? --YES--> Use polydev-runner skill
    |
Need investigation/research? --YES--> Use polydev-agent skill
```

---

## Available Skills

| Skill | Session Type | When to Use |
|-------|:------------:|-------------|
| **polydev** | `wo:` | Execute 2+ independent tasks in parallel (requires git) |
| **polydev-plans** | - | Create detailed implementation plans |
| **polydev-runner** | `bg:` | Long-running commands (builds, tests, servers, SSH) |
| **polydev-agent** | `ag:` | Spawn investigation/research sub-agents |
| **polydev-executor** | - | Sub-agent only: execute in isolated worktree |

---

## Script Quick Reference

All scripts via `bash "$HOME/.codex/polydev/scripts/<name>.sh"`:

| Scenario | Script | Parameters |
|----------|--------|------------|
| Create worktree + Codex | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |
| Send to worktree | `wo-send-command.sh` | `<worktree-path> "<cmd>"` |
| Send to any session | `send-to-session.sh` | `<session_id> "<cmd>"` |
| Read screen output | `capture-screen.sh` | `--session <wo:id> --lines N` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<session_id>` |
| Start background command | `run-background.sh` | `<name> "<cmd>"` |
| Analyze output | `analyze-output.sh` | `<session_id> --lines N` |
| Wait for pattern | `wait-for-pattern.sh` | `<session_id> --success "<pattern>"` |
| Start investigation agent | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path>` |

---

## Quick Decision Guide

**User says "implement X, Y, and Z":**
1. Are X, Y, Z independent? → **polydev** skill
2. Need detailed plans? → **polydev-plans** skill first

**User says "run this build/test":**
1. Will it take > 30 seconds? → **polydev-runner** skill
2. Need to monitor output? → **polydev-runner** skill

**User says "SSH to server and run commands":**
1. Use **polydev-runner** skill
2. Use `run-background.sh` to start SSH
3. Use `send-to-session.sh` to send subsequent commands
4. Use `capture-screen.sh` to read output

**User says "research/investigate X":**
1. Read-only analysis? → **polydev-agent** skill
2. Need parallel research? → Multiple agents via `spawn-agent.sh`

---

## Red Flags - STOP and Use Polydev

If you catch yourself thinking:

| Thought | Reality |
|---------|---------|
| "I'll just do these sequentially" | If independent, parallelize. Check polydev. |
| "This is simple enough to do directly" | 2+ tasks = potential parallelism. Check. |
| "I don't need the overhead" | Polydev saves time on multi-task work. |
| "I'll parallelize later" | Parallelize NOW if tasks are independent. |

**All of these mean: Check polydev skills first.**

---

## Integration Flow

```
using-polydev (this skill)
    |
polydev-plans (if need plans)
    |
polydev (execution) ──────────────────┐
    |                                 |
polydev-runner (bg: tasks)     polydev-agent (ag: tasks)
    |                                 |
polydev-executor (per-branch, sub-agent)
```

---
name: using-polydev
description: "Use at conversation start when user mentions: parallel, 同时, multiple tasks/features, worktrees, or lists 2+ independent work items - determines which polydev skill to use"
---

<CRITICAL>
If the user mentions ANY of these, you MUST check polydev skills:

- "并行" / "parallel" / "同时做" / "一起做"
- "多个功能" / "多个任务" / "multiple features/tasks"
- Lists 2+ independent work items
- "worktree" / "分支" / "branch" (in context of parallel work)
- "后台运行" / "background" / "长时间命令"

This is NOT optional. If there's even a 10% chance polydev applies, CHECK IT.
</CRITICAL>

# Using Polydev Skills

## 脚本路径（主 Agent 必须遵守）

**所有脚本必须通过 `$POLYDEV_SCRIPTS` 变量调用，禁止 `./scripts/`**

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```

---

## Skill Selection Flow

```
User message received
    ↓
Contains parallel/multiple/同时 keywords?
    ↓ YES
Is it complex/unclear? ──YES──→ Run /polydev-brainstorm
    ↓ NO
Ready to execute? ──YES──→ Use polydev:polydev skill
    ↓
Need detailed plans? ──YES──→ Use polydev:writing-plans skill
    ↓
Running background command? ──YES──→ Use polydev:terminal-task-runner skill
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

## 脚本场景速查（主 Agent 用）

| 场景 | 脚本 | 参数 |
|------|------|------|
| 创建 worktree + Claude | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| 监控状态 | `poll.sh` | `<worktrees-dir> <timeout>` |
| 恢复崩溃会话 | `restore-session.sh` | `<worktree-path> [--force]` |
| 向 worktree 发命令 | `send-command.sh` | `<worktree-path> "<cmd>"` |
| 向任意 session 发命令 | `send-to-session.sh` | `<session_id> "<cmd>"` |
| 读取屏幕输出 | `capture-screen.sh` | `--session <wo:id> --lines N` |
| 列出会话 | `list-sessions.sh` | `[workspace]` |
| 关闭会话 | `close-session.sh` | `<session_id>` |
| 启动后台命令 | `run-background.sh` | `<name> "<cmd>"` |
| 分析输出 | `analyze-output.sh` | `<session_id> --lines N` |
| 等待模式匹配 | `wait-for-pattern.sh` | `<session_id> --success "<pattern>"` |
| 启动调查 Agent | `spawn-agent.sh` | `<name> --prompt "<任务>" --report <path>` |

---

## Red Flags - STOP and Use Polydev

If you catch yourself thinking:

| Thought | Reality |
|---------|---------|
| "I'll just do these sequentially" | If independent, parallelize. Check polydev. |
| "This is simple enough to do directly" | 2+ tasks = potential parallelism. Check. |
| "I don't need the overhead" | Polydev saves time on multi-task work. |
| "Let me explore first" | Run /polydev-brainstorm to explore properly. |
| "I'll parallelize later" | Parallelize NOW if tasks are independent. |

**All of these mean: Check polydev skills first.**

## Quick Decision Guide

**User says "implement X, Y, and Z":**
1. Are X, Y, Z independent? → polydev:polydev
2. Need clarification? → /polydev-brainstorm
3. Need detailed plans? → polydev:writing-plans first

**User says "run this build/test":**
1. Will it take > 30 seconds? → polydev:terminal-task-runner
2. Need to monitor output? → polydev:terminal-task-runner

**User says "SSH to server and run commands":**
1. Use polydev:terminal-task-runner
2. Use `run-background.sh` to start SSH
3. Use `send-to-session.sh` to send subsequent commands
4. Use `capture-screen.sh` to read output

**User says "research X":**
1. Read-only analysis? → polydev:agent-investigator (via spawn-agent.sh)
2. Need parallel research? → Multiple agent-investigators

## Cost Control Reminder

**Sub-agents MUST use `model: "sonnet"`** unless user explicitly requests otherwise.

```javascript
// ✅ Correct
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })

// ❌ Wrong - will bankrupt user
Task({ prompt: "...", subagent_type: "general-purpose" })
```

## Integration

This skill is the entry point. After determining which skill to use:

```
using-polydev (this skill)
    ↓
/polydev-brainstorm (if complex)
    ↓
polydev:writing-plans (if need plans)
    ↓
polydev:polydev (execution)
    ↓
polydev:worktree-executor (per-branch, sub-agent)
```

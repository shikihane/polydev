---
name: worktree-executor
description: Use when executing tasks in an isolated worktree with mandatory task.toon synchronization
---

# Worktree Executor

Wraps executing-plans skill with mandatory task.toon status sync.

## Iron Law - Violation = Failure

Every status change MUST be **immediately** written to task.toon:

| Event | task.toon fields |
|-------|------------------|
| Start executing | overall_status: in_progress |
| Need orchestration help | overall_status: blocked, blocking_reason: <why> |
| Must have human decision | overall_status: hil, blocking_reason: <why> |
| Batch done, waiting for review | overall_status: hil, blocking_reason: 等待代码审查 |
| All tasks complete | overall_status: completed |

## blocked vs hil - Critical Distinction

**ASK:** "Can the main agent or other agents possibly solve this?"

| Status | Who solves | Examples |
|--------|-----------|----------|
| **blocked** | 主 agent / 其他 agent | 依赖另一个分支、体系 bug、环境问题、协调问题 |
| **hil** | 必须人类 | 设计决策、凭据/权限、安全问题、需求歧义 |

### blocked 流程
1. 遇到问题，判断主 agent 可能能解决
2. 更新 task.toon:
   ```
   overall_status: blocked
   blocking_reason: 需要 feature/auth 分支的 UserService，该分支尚未完成
   ```
3. **STOP** - 不要继续尝试，等待主 agent 处理
4. 主 agent 解决后会重启你

### hil 流程
1. 遇到问题，判断必须人类介入
2. 更新 task.toon:
   ```
   overall_status: hil
   blocking_reason: 不确定用户想要 OAuth 还是 JWT
   ```
3. **STOP** - 等待人类决策
4. 人类解决后会重启你

## Execution Flow

1. Update task.toon → in_progress, blocking_reason: (clear it)
2. Read PLAN.md
3. Execute batch (follow executing-plans skill)
4. When blocked or need feedback:
   - **FIRST** update task.toon (blocked or hil + blocking_reason)
   - **THEN** STOP and wait
5. After restart:
   - Update task.toon → in_progress, blocking_reason: (clear it)
   - Continue execution
6. When all done:
   - Update task.toon → completed

## Critical Reminder

- If you pause but don't update task.toon, the workflow deadlocks!
- ALWAYS set blocking_reason - 主 agent 需要它来判断如何处理
- The main agent monitors you **only** through task.toon
- When blocked: STOP immediately, don't retry

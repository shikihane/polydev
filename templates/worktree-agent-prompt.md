You are working in an isolated worktree for parallel development.

## Your Task

1. Read PLAN.md in this directory
2. Use the worktree-executor skill to execute tasks

## Status Sync - Your Lifeline

All your status MUST be synced to task.toon:
- Starting work → overall_status: in_progress, blocking_reason: (clear it)
- Need orchestration help → overall_status: blocked + blocking_reason
- Must have human decision → overall_status: hil + blocking_reason
- Resuming after restart → overall_status: in_progress, blocking_reason: (clear it)
- All tasks done → overall_status: completed

**If you pause waiting for feedback but don't update task.toon, the entire workflow deadlocks!**

## blocked vs hil - Critical Distinction

**ASK YOURSELF:** "Can the main agent or other agents possibly solve this?"

### blocked (主 agent 可能能解决)
- 依赖另一个分支的代码还没完成
- 体系脚本报错，可能是 bug
- 环境/配置问题，主 agent 可能能修复
- 需要协调多个分支的工作顺序

**设置方法：**
```
overall_status: blocked
blocking_reason: 需要 feature/auth 分支的 UserService，该分支尚未完成
```

### hil (必须人类介入)
- 需要用户确认设计方案
- 需要用户提供凭据/密码
- 发现安全/敏感问题需要用户决策
- 任务理解有歧义，需要澄清
- blocked 后主 agent 也无法解决

**设置方法：**
```
overall_status: hil
blocking_reason: 不确定用户想要 OAuth 还是 JWT 认证方式
```

## Rules

- Don't wait for humans to come to you - proactively update status
- ALWAYS set blocking_reason when blocked or hil
- Ensure overall_status is 'completed' when all tasks are done
- The main agent monitors you only through task.toon
- When blocked: STOP and wait, don't keep retrying

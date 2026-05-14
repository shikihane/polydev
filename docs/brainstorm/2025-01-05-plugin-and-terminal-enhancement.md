# Brainstorm: Plugin化 + 终端托管增强

**日期**: 2025-01-05
**状态**: 方案确认中

---

## 1. 需求总结

1. **插件化**: 符合 Claude Code 插件标准
2. **后台命令托管**: 主 Agent 在 tmux/wezterm 中执行后台命令（无子 Claude）
3. **Agent 调查任务**: 启动子 Claude 执行调查，通过报告文件交付结果

---

## 2. 四种场景架构

| 场景 | Worktree | 子 Claude | 状态通信 | Skill |
|------|----------|-----------|----------|-------|
| **并行开发** | ✅ | ✅ | task.toon | polydev + worktree-executor |
| **后台命令** | ❌ | ❌ | 终端输出分析 | terminal-task-runner (新) |
| **Agent 调查** | ❌ | ✅ | 报告文件 + 完成标记 | agent-investigator (新) |
| **交互命令** | ❌ | ❌ | 直接终端 | (手动/现有脚本) |

---

## 3. 场景详细设计

### 3.1 并行开发 (现有，保持)

```
主 Agent (polydev)
    │
    ├── 分解任务、创建 worktrees
    ├── spawn-session.sh → 启动带 Claude 的会话
    └── poll.sh → 监控 task.toon
          │
          ▼
子 Agent (worktree-executor)
    │
    ├── 读取 PLAN.md，执行任务
    └── 同步状态到 task.toon
```

### 3.2 后台命令 (新增)

```
主 Agent (terminal-task-runner skill)
    │
    ├── run-background.sh "build" "npm run build"
    │     → 返回 session_id
    │
    └── 循环监控:
          │
          ├── analyze-output.sh $session_id --lines 20
          │     → { "status": "running|success|failed", ... }
          │
          └── 或 wait-for-pattern.sh --success "Done" --fail "Error"
                → 阻塞直到匹配
```

**用途**: 构建、测试、安装依赖、开发服务器等

### 3.3 Agent 调查 (新增)

```
主 Agent
    │
    ├── spawn-agent.sh "auth-research" \
    │     --prompt "分析项目的认证机制" \
    │     --report ./reports/auth.md
    │
    └── 监控终端末尾几行 (capture-screen.sh --lines 5)
          │
          ▼
子 Agent (agent-investigator skill)
    │
    ├── 执行调查 (搜索、阅读、分析)
    ├── 生成报告 → ./reports/auth.md
    └── 输出完成标记:
          ┌─────────────────────────────────────────┐
          │ [AGENT_DONE]                            │
          │ report: ./reports/auth.md               │
          │ timestamp: 2025-01-05T10:30:00Z         │
          │ summary: JWT认证, 3个中间件, 2个隐患    │
          └─────────────────────────────────────────┘
                │
                ▼
主 Agent 检测到 [AGENT_DONE]
    │
    └── 读取报告文件 (精简结果，节省 token)
```

**用途**: 代码分析、问题调研、文档查询、架构理解

---

## 4. 插件目录结构

```
polydev/
├── .claude-plugin/
│   └── plugin.json                    # 插件 manifest
│
├── skills/
│   ├── polydev/         # 主编排 (现有 SKILL.md 移入)
│   │   └── SKILL.md
│   │
│   ├── worktree-executor/             # worktree 内执行 (保持)
│   │   └── SKILL.md
│   │
│   ├── terminal-task-runner/          # 后台命令托管 (新增)
│   │   └── SKILL.md
│   │
│   └── agent-investigator/            # Agent 调查任务 (新增)
│       └── SKILL.md
│
├── scripts/
│   ├── terminal-backend.sh            # 核心抽象层 (保持)
│   │
│   │ # 现有脚本 (保持)
│   ├── spawn-session.sh               # worktree + Claude
│   ├── poll.sh
│   ├── capture-screen.sh              # 增强: --json 输出
│   ├── send-command.sh
│   ├── list-sessions.sh
│   ├── close-session.sh
│   ├── focus-session.sh
│   ├── restore-session.sh
│   ├── cleanup-worktree.sh
│   ├── git-info.sh
│   │
│   │ # 新增脚本
│   ├── run-background.sh              # 后台命令 (无 Claude)
│   ├── spawn-agent.sh                 # Agent 调查 (Claude, 无 worktree)
│   ├── analyze-output.sh              # 分析终端输出状态
│   └── wait-for-pattern.sh            # 等待模式匹配
│
├── templates/
│   ├── claude-settings.json
│   ├── worktree-agent-prompt.md
│   ├── investigator-prompt.md         # 新增: 调查 Agent 提示词
│   └── task.toon.template
│
├── hooks/
│   ├── on-stop.sh
│   └── on-session-start.sh
│
└── docs/
```

---

## 5. 新增脚本规格

### 5.1 run-background.sh

```bash
# 在终端后台启动命令（无 Claude）
#
# Usage: run-background.sh <name> "<command>" [--cwd <dir>] [--workspace <ws>]
#
# 返回: session_id (格式: bg:<workspace>:<name>.0)
#
# 示例:
#   "/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" build "npm run build"
#   "/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" dev "npm run dev" --cwd ./frontend
```

### 5.2 spawn-agent.sh

```bash
# 启动调查 Agent（Claude, 无 worktree）
#
# Usage: spawn-agent.sh <name> --prompt "<任务>" --report <报告路径> [--cwd <dir>]
#
# 返回: session_id (格式: ag:<workspace>:<name>.0)
#
# 示例:
#   "/c/Users/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" auth-research \
#     --prompt "分析项目的认证机制，找出安全隐患" \
#     --report ./reports/auth-analysis.md
```

### 5.3 analyze-output.sh

```bash
# 分析终端输出状态
#
# Usage: analyze-output.sh <session_id> [--lines N] [--json]
#
# 输出 (JSON):
# {
#   "status": "running|idle|success|failed|done",
#   "idle_seconds": 30,
#   "last_lines": ["...", "..."],
#   "detected": {
#     "agent_done": true,
#     "report_path": "./reports/auth.md",
#     "errors": [],
#     "success_markers": ["Build completed"]
#   }
# }
```

### 5.4 wait-for-pattern.sh

```bash
# 等待终端输出匹配模式
#
# Usage: wait-for-pattern.sh <session_id> \
#          --success <pattern> [--fail <pattern>] \
#          [--timeout <sec>] [--interval <sec>]
#
# 返回值:
#   0 = success pattern matched
#   1 = fail pattern matched
#   2 = timeout
#
# 输出 (JSON):
# { "result": "success|fail|timeout", "matched_line": "...", "elapsed": 45 }
```

---

## 6. 新增 Skill 规格

### 6.1 terminal-task-runner SKILL.md

```markdown
---
name: terminal-task-runner
description: Use when executing long-running background commands. Prefer tmux/wezterm over Claude Code's built-in background.
---

# Terminal Task Runner

在终端中托管后台命令并监控状态。

## 使用时机

- 构建命令 (npm run build, cargo build)
- 测试命令 (npm test, pytest)
- 开发服务器 (npm run dev)
- 安装依赖 (npm install, pip install)
- 任何可能超过 30 秒的命令

## 为什么不用 Claude Code 内置后台？

| 特性 | 内置后台 | 终端托管 |
|------|---------|---------|
| 稳定性 | 可能中断 | 持久运行 |
| 输出查看 | 等结束 | 随时查看 |
| 恢复能力 | 丢失 | session 可恢复 |

## 核心流程

1. 启动: `"/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" <name> "<command>"`
2. 监控: `"/c/Users/<user>/.claude/skills/polydev/scripts/analyze-output.sh" <session_id> --lines 20`
3. 或等待: `"/c/Users/<user>/.claude/skills/polydev/scripts/wait-for-pattern.sh" <session_id> --success "Done"`
4. 清理: `"/c/Users/<user>/.claude/skills/polydev/scripts/close-session.sh" <session_id>`

## 状态判断

读取末尾 N 行，根据模式判断:

| 命令类型 | 行数 | 成功模式 | 失败模式 |
|---------|------|---------|---------|
| npm install | 10 | "added .* packages" | "ERR!" |
| npm run build | 20 | "Build completed" | "error" |
| npm test | 30 | "passed" | "failed" |
| cargo build | 15 | "Finished" | "error\\[E" |

## 禁止事项

❌ 不要使用 Bash 的 run_in_background 参数
❌ 不要使用 & 放入后台
✅ 必须通过 scripts 脚本操作
```

### 6.2 agent-investigator SKILL.md

```markdown
---
name: agent-investigator
description: Use when you need to investigate/research something. Generates a structured report file.
---

# Agent Investigator

执行调查任务并生成结构化报告。

## 使用时机

被 spawn-agent.sh 启动后自动激活。

## 核心职责

1. 理解调查任务
2. 搜索、阅读、分析相关代码/文档
3. 生成报告到指定文件
4. 输出完成标记

## 完成标记格式（必须遵守）

任务完成时，在终端输出：

```
[AGENT_DONE]
report: <报告文件路径>
timestamp: <ISO时间戳>
summary: <20字以内摘要>
```

## 报告模板

```markdown
# 调查报告: <主题>

生成时间: <timestamp>

## 摘要
<3-5句话概括核心发现>

## 发现

### 1. <发现点1>
<详细说明>

### 2. <发现点2>
<详细说明>

## 关键文件
- `path/to/file1.ts` - <说明>
- `path/to/file2.ts` - <说明>

## 建议
1. ...
2. ...
```

## 禁止事项

❌ 不要等待人类输入（你是后台运行的）
❌ 不要在终端输出大量过程信息
✅ 过程信息写日志，结果写报告
✅ 必须输出 [AGENT_DONE] 标记
```

---

## 7. plugin.json

```json
{
  "name": "polydev",
  "description": "Parallel development orchestration with terminal-hosted background tasks and agent investigations",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  },
  "keywords": [
    "git",
    "worktree",
    "parallel",
    "tmux",
    "wezterm",
    "background-tasks",
    "agent"
  ]
}
```

---

## 8. Session ID 命名规范

| 场景 | 前缀 | 格式 | 示例 |
|------|------|------|------|
| Worktree 开发 | `wo:` | `wo:<workspace>:<branch>.0` | `wo:myproj:feature-auth.0` |
| 后台命令 | `bg:` | `bg:<workspace>:<name>.0` | `bg:myproj:build.0` |
| Agent 调查 | `ag:` | `ag:<workspace>:<name>.0` | `ag:myproj:auth-research.0` |

---

## 9. 实施阶段

### Phase 1: 插件化基础 (P0)

- [ ] 创建 `.claude-plugin/plugin.json`
- [ ] 移动 `SKILL.md` → `skills/polydev/SKILL.md`
- [ ] 验证插件加载

### Phase 2: 后台命令支持 (P1)

- [ ] 实现 `run-background.sh`
- [ ] 实现 `analyze-output.sh`
- [ ] 实现 `wait-for-pattern.sh`
- [ ] 创建 `skills/terminal-task-runner/SKILL.md`
- [ ] 测试后台命令流程

### Phase 3: Agent 调查支持 (P1)

- [ ] 实现 `spawn-agent.sh`
- [ ] 创建 `templates/investigator-prompt.md`
- [ ] 创建 `skills/agent-investigator/SKILL.md`
- [ ] 测试调查流程

### Phase 4: 增强与优化 (P2)

- [ ] 增强 `capture-screen.sh` 添加 `--json`
- [ ] 更新主 Skill 提示词，添加后台任务策略
- [ ] 添加更多模式匹配规则
- [ ] 文档完善

---

## 10. 待确认问题

1. **workspace 默认值**: 后台命令和调查任务的 workspace 用什么？
   - 建议: 使用当前目录名，如 `$(basename $(pwd))`

2. **报告目录**: 调查报告默认放哪？
   - 建议: `./reports/` 或 `./.agent-reports/`

3. **模型选择**: 调查 Agent 默认用什么模型？
   - 建议: 默认 sonnet（省钱），可通过参数指定

---

## 11. 下一步

等待用户确认后开始 Phase 1。

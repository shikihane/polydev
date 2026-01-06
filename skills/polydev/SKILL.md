---
name: polydev
description: "You MUST use this when executing 2+ independent tasks in parallel - orchestrates git worktrees with terminal sessions (tmux/wezterm)"
---

# Polydev

Parallel development orchestration using Git worktrees and terminal sessions.

---

## 脚本路径（必须遵守）

**所有脚本必须通过 `$POLYDEV_SCRIPTS` 变量调用，禁止使用相对路径 `./scripts/`**

```bash
# 设置脚本路径变量（使用插件安装位置）
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# 然后使用变量调用
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```

**为什么？** `./scripts/` 相对路径离开插件目录就失效。

---

## 💸💸💸 COST CONTROL - 省钱原则 💸💸💸

**并行代理（子Agent）必须使用 `sonnet` 模型！否则你会让用户破产！**

```
❌ WILL BANKRUPT YOUR USER - 以下行为会让用户破产：
├── 用 opus 模型 spawn 多个并行代理
├── 不指定 model 参数（默认继承主 agent 的昂贵模型）
├── 用 haiku 处理需要代码能力的任务（会反复失败浪费更多）
└── "这个任务很重要，用 opus 更好" —— 错！sonnet 足够好！

✅ CORRECT USAGE - 正确做法：
├── Task 工具: 必须指定 model: "sonnet"
├── 唯一例外: 用户主动声明 "用 opus/haiku"
└── 默认永远是 sonnet，无论任务多重要
```

**代码示例：**
```javascript
// ❌ 错误 - 会继承主 agent 的 opus 模型
Task({ prompt: "...", subagent_type: "general-purpose" })

// ✅ 正确 - 明确指定 sonnet
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })
```

---

## 🚨🚨🚨 ABSOLUTE PROHIBITION 🚨🚨🚨

**你必须使用脚本。绝对禁止自己写终端命令。**

```
❌ BANNED FOREVER - 以下行为永久禁止：
├── 自己调用 wezterm cli spawn / tmux new-session
├── 自己调用 wezterm cli send-text / tmux send-keys
├── 自己调用 wezterm cli list / tmux list-sessions
├── 自己调用 wezterm cli kill-pane / tmux kill-session
├── 自己读取终端输出判断状态
├── 自己写 git worktree add/remove 命令
├── 自己删除 .worktrees 目录下的任何东西
├── 使用相对路径 ./scripts/（离开目录会失效）
└── 任何"我觉得脚本太麻烦，自己写更快"的想法
```

---

## 🛠️ 脚本使用约束（场景 → 脚本映射）

### 🔴 场景 A: 创建 worktree + Claude 会话
**脚本**: `spawn-session.sh`
**参数**: `<workspace> <branch> <worktree-path> <plan-file>`
**返回**: session_id (格式: `wo:<workspace>:<branch>.0`)

```bash
"$POLYDEV_SCRIPTS/spawn-session.sh" myproject feature/auth .worktrees/auth PLAN.md
```

### 🔴 场景 B: 监控所有 worktree 状态（必须在循环中调用）
**脚本**: `poll.sh`
**参数**: `<worktrees-dir> <timeout-seconds>`
**返回**: 状态变化信息

```bash
result=$("$POLYDEV_SCRIPTS/poll.sh" .worktrees 10)
```

### 🔴 场景 C: 恢复崩溃的会话
**脚本**: `restore-session.sh`
**参数**: `<worktree-path> [--force]`

```bash
"$POLYDEV_SCRIPTS/restore-session.sh" .worktrees/auth
"$POLYDEV_SCRIPTS/restore-session.sh" .worktrees/auth --force  # 强制重启
```

### 🔴 场景 D: 向 worktree 会话发送命令（有 task.toon）
**脚本**: `send-command.sh`
**参数**: `<worktree-path> "<command>" [--no-enter]`
**前提**: worktree 中必须有 task.toon 文件

```bash
"$POLYDEV_SCRIPTS/send-command.sh" .worktrees/auth "npm test"
"$POLYDEV_SCRIPTS/send-command.sh" .worktrees/auth "password" --no-enter
```

### 🔴 场景 E: 向任意 session 发送命令（SSH、REPL 等交互场景）
**脚本**: `send-to-session.sh`
**参数**: `<session_id> "<command>" [--no-enter]`
**session_id 格式**: `bg:xxx`, `wo:xxx`, `ag:xxx`

```bash
# 向 SSH 会话发送命令
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh.0 "docker ps"
```

### 🔴 场景 F: 聚焦到某个会话
**脚本**: `focus-session.sh`
**参数**: `<worktree-path>` 或 `<session_id>`

```bash
"$POLYDEV_SCRIPTS/focus-session.sh" .worktrees/auth
```

### 🔴 场景 G: 列出所有活动会话
**脚本**: `list-sessions.sh`
**参数**: `[workspace]` (可选过滤)

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/list-sessions.sh" myproject
```

### 🔴 场景 H: 关闭/终结会话
**脚本**: `close-session.sh`
**参数**: `<session_id>`

```bash
"$POLYDEV_SCRIPTS/close-session.sh" wo:myproject:feature-auth.0
"$POLYDEV_SCRIPTS/close-session.sh" bg:bg-polydev:build.0
```

### 🔴 场景 I: 读取会话当前屏幕内容
**脚本**: `capture-screen.sh`
**参数**: `--session <wo:session_id> --lines <N>` 或 `<worktree-path> [--lines N]`
**注意**: `--session` 参数需要 `wo:` 前缀！

```bash
# 通过 worktree 路径
"$POLYDEV_SCRIPTS/capture-screen.sh" .worktrees/auth --lines 50

# 通过 session ID（必须用 wo: 前缀）
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-polydev:build.0 --lines 50
```

### 🔴 场景 J: 清理 worktree（完成后使用）
**脚本**: `cleanup-worktree.sh`
**参数**: `<worktree-path>`

```bash
"$POLYDEV_SCRIPTS/cleanup-worktree.sh" .worktrees/auth
```

### 🔴 场景 K: 启动后台命令（无子 Claude）
**脚本**: `run-background.sh`
**参数**: `<name> "<command>" [--cwd <dir>]`
**返回**: session_id (格式: `bg:<workspace>:<name>.0`)

```bash
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")
```

### 🔴 场景 L: 分析后台任务输出状态
**脚本**: `analyze-output.sh`
**参数**: `<session_id> --lines <N> [--json]`

```bash
result=$("$POLYDEV_SCRIPTS/analyze-output.sh" bg:bg-myproj:build.0 --lines 20 --json)
```

### 🔴 场景 M: 等待模式匹配
**脚本**: `wait-for-pattern.sh`
**参数**: `<session_id> --success "<pattern>" [--fail "<pattern>"] [--timeout <seconds>]`

```bash
"$POLYDEV_SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "Build completed" \
  --fail "Error" \
  --timeout 300
```

### 🔴 场景 N: 启动调查 Agent
**脚本**: `spawn-agent.sh`
**参数**: `<name> --prompt "<任务>" --report <报告路径>`

```bash
session_id=$("$POLYDEV_SCRIPTS/spawn-agent.sh" auth-research \
  --prompt "分析项目的认证机制" \
  --report ./.agent-reports/auth.md)
```

---

## 🔄 三种终端托管场景

| 场景 | 脚本 | 子 Claude | 状态通信 |
|------|------|-----------|----------|
| **并行开发** | spawn-session.sh | Yes | task.toon |
| **后台命令** | run-background.sh | No | 终端输出分析 |
| **Agent 调查** | spawn-agent.sh | Yes | 报告文件 + [AGENT_DONE] |

### Session ID 格式

```
wo:workspace:branch.0    # 并行开发 (worktree)
bg:workspace:name.0      # 后台命令 (background)
ag:workspace:name.0      # Agent 调查 (agent)
```

---

## ⚠️ Poll Loop - 启动后必须持续监控

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# 启动所有会话后，立即进入监控循环 - 不能省略！
while branches_remaining; do
  result=$("$POLYDEV_SCRIPTS/poll.sh" .worktrees 10)  # 必须调用！

  worktree=$(echo "$result" | cut -d',' -f1)
  overall_status=$(echo "$result" | cut -d',' -f3)
  agent_status=$(echo "$result" | cut -d',' -f4)

  case "$agent_status" in
    crashed) "$POLYDEV_SCRIPTS/restore-session.sh" "$worktree" --force ;;
    idle)    # 检查是否需要重启
  esac

  case "$overall_status" in
    completed) # 验收并合并
    hil)       # 人工介入（必须人类决策）
    blocked)   # 需要协助（主 agent 尝试解决，失败则升级为 hil）
  esac
done
```

**禁止：** 启动会话后就不管了，期望子 agent 自己完成。

---

## 📊 状态来源：只信任 task.toon

- ✅ 读取 `<worktree>/task.toon` 获取 `overall_status` 和 `agent_status`
- ❌ 不要猜测子 agent 状态
- ❌ 不要读取终端输出判断状态

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
    ↓
Phase 0: Brainstorming (Optional)
    - Use polydev:brainstorming for complex/unclear requests
    ↓
Phase 1: Verification Strategy Research
    ↓
Phase 2: Task Decomposition
    ↓
Phase 3: User Confirmation
    ↓
Phase 4: Parallel Execution (spawn-session.sh + poll.sh loop)
    ↓
Phase 5: Incremental Verify & Merge
    ↓
Phase 6: Cleanup (Human Confirms)
```

---

## 验收深度级别

| 级别 | 名称 | 验收内容 | 适用场景 |
|------|------|---------|---------|
| L0 | skip | 无验收 | 文档、注释、配置 |
| L1 | compile | 仅编译通过 | 微小改动、代码格式化 |
| L2 | unit | 编译 + 单元测试 | 普通功能、工具函数 |
| L3 | integration | + 集成测试 | 模块交互、API端点 |
| L4 | e2e | + 端到端测试 | 核心用户流程 |
| L5 | manual | + 人工验证 | 无法自动化、关键功能 |

---

## Session Recovery（会话恢复）

| 场景 | agent_status | 解决方案 |
|------|--------------|----------|
| **会话崩溃** | crashed | `"$POLYDEV_SCRIPTS/restore-session.sh" <worktree> --force` |
| **Claude 停止** | idle | `"$POLYDEV_SCRIPTS/restore-session.sh" <worktree>` |
| **Claude 卡住** | active (长时间无更新) | `"$POLYDEV_SCRIPTS/restore-session.sh" <worktree> --force` |

---

## Status Values

### overall_status

| Status | Meaning |
|--------|---------|
| `pending` | 已分配，未开始 |
| `in_progress` | 分支 agent 工作中 |
| `completed` | 分支完成，待验收 |
| `blocked` | 需要协助（主 agent 可能能解决） |
| `hil` | 需要人类介入（必须人类决策） |
| `merged` | 合并成功 |

### agent_status

| Status | Meaning |
|--------|---------|
| `active` | Claude 活跃 |
| `idle` | Claude 意外停止 |
| `crashed` | 进程不存在 |

---

## Iron Rules

1. **所有脚本通过 `$POLYDEV_SCRIPTS` 调用，禁止 `./scripts/`**
2. **先研究验收策略，再分解任务**
3. **按验收级别执行，不跳级**
4. **会话崩溃时先恢复再继续**
5. **💸 并行代理必须用 sonnet！除非用户主动声明其他模型！**

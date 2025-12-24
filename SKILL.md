---
name: worktree-orchestrator
description: Use when parallelizing development across multiple git worktrees with terminal sessions (tmux on Linux/macOS, wezterm on Windows)
---

# Worktree Orchestrator

Parallel development orchestration using Git worktrees and terminal sessions.

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

**成本对比（估算）：**
| 模型 | 相对成本 | 并行5个任务成本 |
|------|---------|----------------|
| Opus | 15x | 💀💀💀 |
| Sonnet | 1x | ✅ 合理 |
| Haiku | 0.2x | ⚠️ 能力不足可能重试 |

**代码示例：**
```javascript
// ❌ 错误 - 会继承主 agent 的 opus 模型
Task({ prompt: "...", subagent_type: "general-purpose" })

// ✅ 正确 - 明确指定 sonnet
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })
```

**记住：用户用 opus 调用你，不代表子 agent 也要用 opus！**

---

## 🚨🚨🚨 ABSOLUTE PROHIBITION 🚨🚨🚨

**你必须使用 `./scripts/*.sh` 脚本。绝对禁止自己写终端命令。**

```
❌ BANNED FOREVER - 以下行为永久禁止：
├── 自己调用 wezterm cli spawn / tmux new-session
├── 自己调用 wezterm cli send-text / tmux send-keys
├── 自己调用 wezterm cli list / tmux list-sessions
├── 自己调用 wezterm cli kill-pane / tmux kill-session
├── 自己读取终端输出判断状态
├── 自己写 git worktree add/remove 命令
├── 自己删除 .worktrees 目录下的任何东西
└── 任何"我觉得脚本太麻烦，自己写更快"的想法

✅ MUST USE - 必须使用：
├── ./scripts/spawn-session.sh    → 创建会话
├── ./scripts/poll.sh             → 监控状态（循环调用）
├── ./scripts/restore-session.sh  → 恢复会话
├── ./scripts/send-command.sh     → 向会话发送命令（带回车）
├── ./scripts/focus-session.sh    → 聚焦会话
├── ./scripts/list-sessions.sh    → 列出所有会话
├── ./scripts/close-session.sh    → 关闭/终结会话
├── ./scripts/capture-screen.sh   → 读取会话当前屏幕内容
└── ./scripts/cleanup-worktree.sh → 清理 worktree
```

**为什么这么严格？**
1. 脚本处理了 Windows/Linux 兼容、路径转换、备份、状态同步等几十个边界情况
2. 你自己写的命令会崩溃，然后整个并行流程卡死
3. 不用脚本 = 脚本没人测试 = bug 永远发现不了 = 系统永远不稳定

**如果你觉得脚本有问题，正确做法是：修复脚本，而不是绕过它。**

---

**Supported Backends:**
- **tmux** (Linux/macOS) - uses isolated socket at `/tmp/worktree-orchestrator.sock`
- **wezterm** (Windows) - uses workspace-based session management

**Announce:** "I'm using the worktree-orchestrator skill to parallelize this work."

## 🛠️ Scripts Quick Reference

```bash
# 创建会话（必须用这个，不要自己 spawn）
./scripts/spawn-session.sh <workspace> <branch> <worktree-path> <plan-file>

# 监控状态（必须在循环中调用）
./scripts/poll.sh <worktrees-dir> <timeout-seconds>

# 恢复崩溃的会话
./scripts/restore-session.sh <worktree-path> [--force]

# 向空闲会话发送命令（带回车执行）
./scripts/send-command.sh <worktree-path> "<command>"
./scripts/send-command.sh <worktree-path> "<text>" --no-enter  # 不按回车

# 聚焦到某个会话
./scripts/focus-session.sh <worktree-path>

# 列出所有活动会话
./scripts/list-sessions.sh              # 列出全部
./scripts/list-sessions.sh <workspace>  # 按 workspace 过滤

# 关闭/终结会话
./scripts/close-session.sh <session_id>

# 读取会话当前屏幕内容（调试用）
./scripts/capture-screen.sh <worktree-path>           # 当前可见屏幕
./scripts/capture-screen.sh <worktree-path> --lines 100  # 最近 100 行

# 清理 worktree（完成后使用）
./scripts/cleanup-worktree.sh <worktree-path>
```

## ⚠️ Poll Loop - 启动后必须持续监控

```bash
# 启动所有会话后，立即进入监控循环 - 不能省略！
while branches_remaining; do
  result=$(./scripts/poll.sh .worktrees 10)  # ← 必须调用！

  worktree=$(echo "$result" | cut -d',' -f1)
  overall_status=$(echo "$result" | cut -d',' -f3)
  agent_status=$(echo "$result" | cut -d',' -f4)

  case "$agent_status" in
    crashed) ./scripts/restore-session.sh "$worktree" --force ;;
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

## 📊 状态来源：只信任 task.toon

- ✅ 读取 `<worktree>/task.toon` 获取 `overall_status` 和 `agent_status`
- ❌ 不要猜测子 agent 状态
- ❌ 不要读取终端输出判断状态

## Core Flow

```
User request
    ↓
Phase 1: Verification Strategy Research
    - 分析项目类型
    - 检测可用基础设施 (MCP、测试框架等)
    - 确定验收能力上限
    ↓
Phase 2: Task Decomposition
    - 分解任务
    - 评估每个任务重要性
    - 分配验收级别
    - 警告基础设施不足
    ↓
Phase 3: User Confirmation
    - 展示任务列表 + 验收策略
    - 用户确认或调整
    ↓
Phase 4: Parallel Execution
    - 创建 N 个 worktrees (spawn-session.sh)
    - 启动 N 个 Claude 会话
    - ⚠️ 【必须】循环调用 poll.sh 监控状态
    ↓
Phase 5: Incremental Verify & Merge
    - poll.sh 返回时处理该分支
    - 按验收级别执行验证
    - 测试通过后合并
    ↓
Phase 6: Cleanup (Human Confirms)
```

---

## Phase 1: Verification Strategy Research

**在分解任务之前，必须先研究验收策略。**

### 1.1 分析项目类型

| 项目类型 | 特征文件 | 默认验收能力 |
|---------|---------|-------------|
| Node.js | package.json | L2 (npm test) |
| Python | pyproject.toml, setup.py | L2 (pytest) |
| Rust | Cargo.toml | L2 (cargo test) |
| Go | go.mod | L2 (go test) |
| C/C++ | CMakeLists.txt, Makefile | L1-L2 |
| Web前端 | vite.config, next.config | L2, L4需浏览器MCP |
| 嵌入式 | platformio.ini, .ioc | L1, L3+需硬件MCP |
| 纯文档 | 只有.md文件 | L0 |

### 1.2 检测可用基础设施

询问或检测：

```
1. 测试框架: 项目中是否有测试？如何运行？
2. 浏览器MCP: 是否有 Playwright/Puppeteer MCP？
3. 硬件MCP: 是否有串口/JTAG/网络设备 MCP？
4. API测试: 是否有 HTTP 客户端或 API 测试工具？
5. 模拟器: 是否有移动端/嵌入式模拟器？
```

### 1.3 确定验收能力上限

```
能力上限 = min(项目支持的级别, 可用基础设施支持的级别)
```

示例：
- Web项目 + 无浏览器MCP → 能力上限 L2
- 嵌入式项目 + 有硬件MCP → 能力上限 L4
- 算法库 + 有测试框架 → 能力上限 L3

---

## Phase 2: Task Decomposition

### 2.1 验收深度级别

| 级别 | 名称 | 验收内容 | 适用场景 |
|------|------|---------|---------|
| L0 | skip | 无验收 | 文档、注释、配置 |
| L1 | compile | 仅编译通过 | 微小改动、代码格式化 |
| L2 | unit | 编译 + 单元测试 | 普通功能、工具函数 |
| L3 | integration | + 集成测试 | 模块交互、API端点 |
| L4 | e2e | + 端到端测试 | 核心用户流程 |
| L5 | manual | + 人工验证 | 无法自动化、关键功能 |

### 2.2 任务重要性评估

| 重要性 | 建议级别 | 判断标准 |
|--------|---------|---------|
| 关键 | L4-L5 | 核心功能、支付、安全相关 |
| 重要 | L3 | 主要功能、用户可见 |
| 普通 | L2 | 辅助功能、内部工具 |
| 次要 | L1 | 重构、优化、小修复 |
| 微小 | L0 | 文档、格式、注释 |

### 2.3 验收级别分配

```
分配级别 = min(任务所需级别, 验收能力上限)

如果 任务所需级别 > 验收能力上限:
  → 警告: "任务 X 需要 L4 验收，但当前能力上限为 L2"
  → 选项:
    a) 降级到 L2，接受风险
    b) 标记为 L5 (人工验证)
    c) 先配置所需基础设施
```

### 2.4 Plan 文件格式

每个任务的 plan 文件应包含验收信息：

```markdown
---
task: 实现用户登录API
branch: feature/auth-api
importance: 重要
verification:
  level: L3
  commands:
    - npm run build
    - npm test -- --grep "auth"
    - npm run test:integration -- --grep "login"
  fallback: L2  # 如果集成测试失败，降级到此级别重试
  notes: 需要测试数据库连接
---

## 任务描述
...
```

---

## Phase 3: User Confirmation

展示验收策略摘要：

```
=== 验收策略 ===

项目类型: Node.js Web应用
验收能力上限: L2 (无浏览器MCP)

任务分配:
  ├─ feature/auth-api     [L3→L2] ⚠️ 降级: 缺少集成测试环境
  ├─ feature/user-profile [L2]    ✓
  ├─ feature/dashboard    [L4→L5] ⚠️ 需人工验证: 缺少浏览器MCP
  └─ feature/utils        [L1]    ✓

⚠️ 警告:
- 2个任务因基础设施不足已降级
- 建议: 配置 Playwright MCP 以支持 L4 验收

确认继续? (y/调整/取消)
```

---

## Phase 4: Parallel Execution

### 4.1 Spawn Sessions

```bash
./scripts/spawn-session.sh <workspace> <branch> <worktree-path> <plan-file>
```

**spawn-session.sh 自动执行：**
1. 创建 git worktree 和分支
2. 复制 .claude 配置和 hooks
3. 生成 task.toon
4. **自动创建首个备份** 🆕
5. 创建终端会话
6. 启动 Claude agent

### 4.2 Poll Loop with Session Management 🆕

```bash
while branches_remaining; do
  result=$(./scripts/poll.sh .worktrees 10)

  # 解析状态
  worktree=$(echo "$result" | cut -d',' -f1)
  overall_status=$(echo "$result" | cut -d',' -f3)
  agent_status=$(echo "$result" | cut -d',' -f4)

  # 处理不同的 agent 状态
  case "$agent_status" in
    crashed)
      # 会话崩溃 → 自动恢复
      echo "🔧 Detected crashed session in $worktree, restoring..."
      ./scripts/restore-session.sh "$worktree" --force
      ;;

    idle)
      # Claude 停止但任务未完成 → 询问是否重启
      if [ "$overall_status" != "completed" ] && [ "$overall_status" != "merged" ]; then
        echo "⚠️  Agent stopped in $worktree (status: $overall_status)"
        echo -n "Restart session? [Y/n] "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
          ./scripts/restore-session.sh "$worktree"
        fi
      fi
      ;;

    active)
      # 检查长时间无更新（可能卡住）
      last_update=$(echo "$result" | cut -d',' -f5)
      minutes_since_update=$(( ($(date +%s) - $(date -d "$last_update" +%s)) / 60 ))

      if [ $minutes_since_update -gt 30 ]; then
        echo "⚠️  No updates for $minutes_since_update minutes in $worktree"
        echo -n "Session might be stuck. Restart? [y/N] "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
          ./scripts/restore-session.sh "$worktree" --force
        fi
      fi
      ;;
  esac

  # 处理完成的分支
  if [ "$overall_status" = "completed" ]; then
    handle_completed_branch "$worktree"
  fi

  # 处理需要协助（主 agent 可能能解决）
  if [ "$overall_status" = "blocked" ]; then
    blocking_reason=$(grep "^blocking_reason:" "$worktree/task.toon" | cut -d' ' -f2-)
    echo "🚫 Task blocked in $worktree: $blocking_reason"
    # 分析原因，尝试解决
    # 如果解决了 → restore-session.sh 重启
    # 如果解决不了 → 升级为 hil，通知人类
  fi

  # 处理需要人工介入（必须人类决策）
  if [ "$overall_status" = "hil" ]; then
    blocking_reason=$(grep "^blocking_reason:" "$worktree/task.toon" | cut -d' ' -f2-)
    echo "🙋 Human input needed in $worktree: $blocking_reason"
    handle_human_in_loop "$worktree"
  fi
done
```

**Poll 监控策略：**

| agent_status | 主 Agent 行为 |
|--------------|---------------|
| `active` | 正常监控；长时间无更新时提示 |
| `idle` | 如果任务未完成，询问是否重启 |
| `crashed` | **自动恢复**（使用 --force） |

**关键原则：**
1. **crashed** → 自动恢复（无需询问）
2. **idle** → 询问用户（可能是正常停止）
3. **active 但长时间无更新** → 询问用户（可能卡住）

---

## Phase 5: Incremental Verify & Merge

**完成一个，验证一个，合并一个。**

### 5.1 验收执行流程

```
Branch 完成 (status: completed)
    ↓
读取 plan 中的 verification.level
    ↓
按级别执行验收:
    L0: 跳过 → 直接合并
    L1: 运行编译命令
    L2: L1 + 运行单元测试
    L3: L2 + 运行集成测试
    L4: L3 + 运行E2E测试
    L5: L2 + 通知人类验证
    ↓
验收结果:
    通过 → 合并到 main
    失败 → 检查 fallback 级别
        有 fallback → 降级重试
        无 fallback → rejected, 分支修复
```

### 5.2 各级别验收命令

```bash
# L1: Compile
cd <worktree>
<build-command>  # npm run build / cargo build / go build

# L2: Unit Tests
<build-command>
<test-command>   # npm test / cargo test / pytest

# L3: Integration Tests
<build-command>
<test-command>
<integration-test-command>

# L4: E2E Tests
<build-command>
<test-command>
<e2e-command>    # 需要浏览器MCP或模拟器MCP

# L5: Manual
<build-command>
<test-command>
→ 暂停，通知人类
→ focus-session.sh 激活窗口
→ 人类验证后继续
```

### 5.3 合并流程

```
验收通过
    ↓
在 worktree 中验证通过
    ↓
切换到 main, pull 最新
    ↓
合并分支
    ↓
在 main 上重新运行验收 (同级别)
    ↓
通过 → status: merged
失败 → revert, status: rejected
```

---

## Phase 6: Cleanup

**只有人类确认后才清理。**

```
所有任务 merged
    ↓
展示合并摘要
    ↓
询问: "确认清理这些 worktrees? (y/n)"
    ↓
确认后，对每个 worktree:
    ./scripts/cleanup-worktree.sh <worktree-path>
      ↓
      - 显示将删除的文件
      - 自动备份 task.toon
      - 要求二次确认（输入目录名）
      - 保留 .task_backups/ 目录
    ↓
    git worktree remove <path>
    git branch -d <branch>
```

**注意**: `cleanup-worktree.sh` 提供安全保护：
- 多重确认防止误删
- 自动备份 task.toon
- 保留备份目录用于审计

---

## Session Recovery（会话恢复）🆕

### 自动备份机制

**task.toon 自动备份：**
- 每次修改 task.toon 前自动备份
- 备份位置：`<worktree>/.task_backups/task.toon.TIMESTAMP.bak`
- 保留最近 10 个版本
- 使用时间戳命名，易于识别

### 会话管理场景

| 场景 | agent_status | 症状 | 解决方案 |
|------|--------------|------|----------|
| **会话崩溃** | crashed | poll.sh 报告 session 不存在 | `restore-session.sh` 自动恢复 |
| **Claude 停止** | idle | Claude 退出但 task 未完成 | `restore-session.sh` 重启 |
| **Claude 卡住** | active | 长时间无更新 | `restore-session.sh --force` 强制重启 |
| **系统重启** | crashed | 所有会话丢失 | 对每个 worktree 运行 `restore-session.sh` |
| **task.toon 丢失** | N/A | 文件被误删或损坏 | `restore-session.sh` 从备份恢复 |
| **主动重启** | active | 想换提示词/重新开始 | `restore-session.sh` 选择重启 |

### 会话管理流程

```bash
# 基本用法（自动检测并处理）
./scripts/restore-session.sh <worktree-path>

# 强制重启活跃会话
./scripts/restore-session.sh <worktree-path> --force
```

**脚本智能处理：**

1. **检测 task.toon 状态**
   - 缺失 → 从 `.task_backups/` 恢复最新备份
   - 存在 → 解析 session_id 和 branch 信息

2. **检测会话状态**
   - `active` → 提示用户选择（附加/重启/取消）
   - `dead/idle` → 自动进入重启流程

3. **会话操作选项**
   - 会话活跃时:
     - `[1]` 附加到现有会话（focus-session.sh）
     - `[2]` 杀掉并重启会话
     - `[3]` 取消
   - 会话死亡时:
     - `[1]` 创建新会话并启动 Claude（推荐）
     - `[2]` 仅创建会话（手动启动）
     - `[3]` 取消

4. **--force 模式**
   - 跳过交互，直接杀掉并重启
   - 适用于自动化脚本

### 恢复后验证

```bash
# 检查 task.toon 是否正确
cat <worktree>/task.toon

# 验证会话存活
source scripts/terminal-backend.sh
tb_is_session_alive "wo:workspace:branch.0"

# 聚焦到会话
./scripts/focus-session.sh <worktree-path>
```

### 预防措施

1. **不要手动删除 `.task_backups/`**
2. **定期检查会话状态**：`./scripts/poll.sh .worktrees 10`
3. **遇到错误时先恢复再调试**
4. **保留备份用于审计**

---

## task.toon 扩展格式

```toon
meta{worktree,branch,session_id,created}:
  .worktrees/auth,feature/auth,wo:myproject-parallel:myproject-feature-auth.0,2024-01-15T10:00:00Z

verification{level,fallback,commands}:
  L3,L2,npm run build && npm test && npm run test:integration

tasks[3]{id,desc,status}:
  1,实现登录API,completed
  2,添加JWT验证,completed
  3,编写测试,in_progress

overall_status: in_progress
agent_status: active
blocking_reason:
last_update: 2024-01-15T10:35:00Z
```

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/terminal-backend.sh` | 终端后端抽象层 (tmux/wezterm) |
| `scripts/spawn-session.sh` | 创建 worktree + 终端会话 + Claude |
| `scripts/poll.sh` | 轮询状态，有变化时返回 |
| `scripts/focus-session.sh` | 激活指定会话 |
| `scripts/send-command.sh` | 向会话发送命令（带回车执行） |
| `scripts/list-sessions.sh` | 列出所有活动会话（支持 workspace 过滤） |
| `scripts/close-session.sh` | 关闭/终结指定会话 |
| `scripts/capture-screen.sh` | 读取会话当前屏幕内容（调试用） |
| `scripts/restore-session.sh` | 恢复崩溃的会话（从备份恢复 task.toon） |
| `scripts/cleanup-worktree.sh` | 安全清理 worktree（带确认和备份） |
| `scripts/git-info.sh` | 只读 git 状态检查 |

---

## Iron Rules

1. **先研究验收策略，再分解任务**
2. **基础设施不足时必须警告**
3. **按验收级别执行，不跳级**
4. **验收通过才能合并**
5. **合并后再次验收**
6. **人工确认才能清理**
7. **会话崩溃时先恢复再继续**
8. **不要手动删除 .task_backups/**
9. **💸 并行代理必须用 sonnet！除非用户主动声明其他模型！** 🆕

---

## Status Values

### overall_status

| Status | Meaning |
|--------|---------|
| `pending` | 已分配，未开始 |
| `in_progress` | 分支 agent 工作中 |
| `completed` | 分支完成，待验收 |
| `verifying` | 主 agent 执行验收 |
| `rejected` | 验收失败，需修复 |
| `merging` | 正在合并 |
| `conflict` | 合并冲突 |
| `merged` | 合并成功 |
| `cleanup_pending` | 等待清理确认 |
| `blocked` | 需要协助（主 agent/其他 agent 可能能解决） |
| `hil` | 需要人类介入（必须人类决策） |

### blocked vs hil

| 状态 | 谁来解决 | 典型场景 |
|------|---------|----------|
| `blocked` | 主 agent / 其他 agent | 依赖另一个分支、体系 bug、环境问题、协调问题 |
| `hil` | 必须人类 | 设计决策、凭据/权限、安全问题、需求歧义 |

**处理流程：**
```
blocked → 主 agent 分析 blocking_reason → 尝试解决
        → 成功 → restore-session.sh 重启
        → 失败 → 升级为 hil，通知人类
```

### agent_status

| Status | Meaning |
|--------|---------|
| `active` | Claude 活跃 |
| `idle` | Claude 意外停止 |
| `crashed` | 进程不存在 |

---

## Terminal Backend

### Session ID Format

```
wo:myproject-parallel:feature-auth.0
│  │                  │            │
│  │                  │            └─ pane index
│  │                  └─ window/tab name (branch)
│  └─ session/workspace name
└─ prefix (worktree-orchestrator)
```

### tmux Backend (Linux/macOS)

- **Socket:** `/tmp/worktree-orchestrator.sock` (isolated from user's tmux)
- **Session:** `{workspace}` (e.g., `myproject-parallel`)
- **Window:** `{project}-{branch}`
- **Debugging:** `tmux -S /tmp/worktree-orchestrator.sock attach`

### wezterm Backend (Windows)

- **Workspace:** `{project}-parallel`
- **Tab names:** `{project}-{branch}`
- 所有并行任务在同一窗口

### Backend API

```bash
source scripts/terminal-backend.sh

# Create session
session_id=$(tb_create_worktree_session "$workspace" "$branch" "$path" "$plan")

# Check alive
tb_is_session_alive "$session_id"

# Send command
tb_send_command "$session_id" "claude --dangerously-skip-permissions"

# Focus session
tb_focus_session "$session_id"

# Cleanup
tb_cleanup_session "$session_id"

# Get current backend
tb_get_backend  # returns "tmux" or "wezterm"
```

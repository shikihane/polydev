---
name: worktree-orchestrator
description: Use when parallelizing development across multiple git worktrees with terminal sessions (tmux on Linux/macOS, wezterm on Windows)
---

# Worktree Orchestrator

Parallel development orchestration using Git worktrees and terminal sessions.

**Supported Backends:**
- **tmux** (Linux/macOS) - uses isolated socket at `/tmp/worktree-orchestrator.sock`
- **wezterm** (Windows) - uses workspace-based session management

**Announce:** "I'm using the worktree-orchestrator skill to parallelize this work."

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
    - 创建 N 个 worktrees
    - 启动 N 个 Claude 会话
    - Poll 监控状态
    ↓
Phase 5: Incremental Verify & Merge
    - 完成一个处理一个
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

### 4.2 Poll Loop

```bash
while branches_remaining; do
  result=$(./scripts/poll.sh .worktrees 10)

  # 检测崩溃并自动恢复 🆕
  if status == "crashed"; then
    ./scripts/restore-session.sh <worktree-path>
  fi

  handle_completed_branch "$result"
done
```

**Poll 监控内容：**
- overall_status: 任务进度
- agent_status: Claude 是否存活
- session_id: 终端会话标识
- last_update: 最后更新时间

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

### 恢复场景

| 场景 | 症状 | 解决方案 |
|------|------|----------|
| **会话崩溃** | poll.sh 报告 agent_status: crashed | `restore-session.sh` |
| **task.toon 丢失** | 文件被误删或损坏 | `restore-session.sh` 自动从备份恢复 |
| **系统重启** | 所有会话丢失 | 对每个 worktree 运行 `restore-session.sh` |
| **终端断开** | 无法连接到会话 | `restore-session.sh` 重建会话 |

### 恢复流程

```bash
./scripts/restore-session.sh <worktree-path>
```

**脚本功能：**
1. 检测 task.toon 是否存在
2. 如缺失，从 `.task_backups/` 恢复最新备份
3. 检查会话是否存活
4. 创建新终端会话并更新 session_id
5. 可选：自动重启 Claude

**交互选项：**
- `[1]` 创建新会话并启动 Claude（推荐）
- `[2]` 仅创建会话（手动启动 Claude）
- `[3]` 取消

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
| `scripts/restore-session.sh` | 🆕 恢复崩溃的会话（从备份恢复 task.toon） |
| `scripts/cleanup-worktree.sh` | 🆕 安全清理 worktree（带确认和备份） |
| `scripts/git-info.sh` | 只读 git 状态检查 |

---

## Iron Rules

1. **先研究验收策略，再分解任务**
2. **基础设施不足时必须警告**
3. **按验收级别执行，不跳级**
4. **验收通过才能合并**
5. **合并后再次验收**
6. **人工确认才能清理**
7. **会话崩溃时先恢复再继续** 🆕
8. **不要手动删除 .task_backups/** 🆕

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
| `hil` | 需要人类介入 |

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

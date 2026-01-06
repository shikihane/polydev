# Polydev

**[English](README.md)**

使用 Git Worktrees 和终端会话实现并行开发编排的 Claude Code 插件。

---

## 为什么选择 Polydev？

### 原生后台任务的局限

Claude Code 的原生后台任务和异步子代理存在根本性限制：

**1. 无法处理交互式 TUI**
- 密码输入提示（SSH、sudo）
- 配置界面（menuconfig、ncurses）
- 嵌套的 Claude Code 会话

**2. 异步子代理难以监控和介入**
- 黑盒执行，无法实时观察进度
- 人类无法中途指导或纠正
- 出错时难以诊断和恢复

**Polydev 的解决方案：** 使用真正的终端复用器（tmux/WezTerm）托管任务，提供：
- 完整的 TTY 支持，处理任何交互式程序
- 实时屏幕捕获，随时查看执行状态
- 人类可以随时附加（attach）到会话进行干预
- 会话崩溃后可从状态文件恢复

### 为什么 Windows 用 WezTerm？

tmux 在 Windows 上的支持复杂且不完善：
- 需要 WSL、Cygwin 或 MSYS2 环境
- 性能开销大，路径转换问题多
- 与原生 Windows 工具链集成困难

**WezTerm** 是更好的选择：
- 原生 Windows 支持，无需虚拟层
- 提供完整的 CLI 控制 API
- GPU 加速渲染，性能优异
- 跨平台一致的行为

### 基于 Git Worktrees 的真并行

传统的分支切换是串行的——同一时间只能在一个分支上工作。Polydev 使用 Git Worktrees 实现真正的并行：

- **独立工作目录**：每个任务有自己的文件系统空间
- **无切换开销**：不需要 stash、checkout、restore
- **真并行执行**：N 个 Claude 代理同时工作在 N 个分支
- **自动合并**：任务完成后自动合并回主分支
- **冲突处理**：检测并报告合并冲突，支持人工介入

### 严格的验收策略

软件质量不能靠运气。Polydev 提供 L0-L5 六级验收策略，确保每个任务达到期望的质量标准：

| 级别 | 适用场景 | 验收内容 |
|------|---------|---------|
| L0 | 文档、配置 | 无需验收 |
| L1 | 微小改动 | 编译通过 |
| L2 | 普通功能 | + 单元测试 |
| L3 | 模块交互 | + 集成测试 |
| L4 | 核心流程 | + 端到端测试 |
| L5 | 关键功能 | + 人工验证 |

任务分解时自动评估重要性并分配验收级别，确保重要功能得到充分验证。

### 未来计划

**情景记忆系统 (Episodic Memory)**

当前子代理通过 task.toon 文件同步状态，但只能传递"结果"，无法传递"过程"。我们计划实现情景记忆系统：

- **时序事件流**：记录发现、假设、决策、教训的完整时间线
- **跨代理知识共享**：一个代理踩过的坑，其他代理不再重复
- **规则反思机制**：从重复性问题中自动提炼规则，写入项目配置
- **经验沉淀**：将高价值经验迁移到项目文档，形成组织记忆

---

## 概述

Polydev 是一个 Claude Code 插件，通过在多个独立 Git 分支上同时生成多个 Claude 代理来实现并行开发。每个代理在隔离的终端会话中运行（Linux/macOS 使用 tmux，Windows 使用 WezTerm），并通过 `task.toon` 文件实时追踪状态。

**核心特性：**
- 跨多个 Git worktrees 并行执行
- 跨平台支持：tmux (Linux/macOS) 或 WezTerm (Windows)
- L0-L5 多级自动化验收
- 后台任务托管（构建、测试、SSH 会话）
- 只读研究任务的调查代理

## 依赖要求

| 组件 | Linux/macOS | Windows |
|------|-------------|---------|
| Claude Code CLI | 必需 | 必需 |
| Git | >= 2.15 | >= 2.15 |
| Bash | >= 4.0 | Git Bash |
| 终端 | tmux | WezTerm + Python 3 |

## 安装

### 从插件市场安装（推荐）

```bash
# 使用 HTTPS URL（SSH 可能因认证问题失败）
claude plugin marketplace add https://github.com/shikihane/polydev
claude plugin install polydev
```

### 手动安装

```bash
# Linux/macOS
mkdir -p ~/.claude/plugins
cp -r /path/to/polydev ~/.claude/plugins/

# Windows (Git Bash)
mkdir -p "$USERPROFILE/.claude/plugins"
cp -r /path/to/polydev "$USERPROFILE/.claude/plugins/"

# 设置权限（仅 Linux/macOS）
chmod +x ~/.claude/plugins/polydev/scripts/*.sh
```

### 验证安装

```bash
cd ~/.claude/plugins/polydev
source scripts/terminal-backend.sh
echo "后端: $(tb_get_backend)"
# 预期输出: tmux (Linux/macOS) 或 wezterm (Windows)
```

## 使用方法

### 快速开始

在 Claude Code 中描述你的并行任务：

```
我需要并行实现以下功能：
1. 用户认证 API
2. 用户资料管理
3. 仪表盘页面

请使用 polydev 同时处理这些任务。
```

Claude 会自动使用相应的 polydev 技能。

### 可用技能

| 技能 | 用途 |
|------|------|
| `polydev:using-polydev` | 入口 - 引导技能选择 |
| `polydev:polydev` | 主编排 - 并行 worktrees |
| `polydev:writing-plans` | 生成实现计划 |
| `polydev:terminal-task-runner` | 托管后台命令（构建、SSH） |
| `polydev:agent-investigator` | 生成只读研究代理 |
| `polydev:worktree-executor` | worktree 中的子代理执行 |

### 斜杠命令

- `/polydev-brainstorm` - 将复杂任务分解为并行工作项

## 工作流程

```
用户请求
    ↓
1. 分析 & 分解任务
    ↓
2. 分配验收级别 (L0-L5)
    ↓
3. 用户确认计划
    ↓
4. 创建 N 个 Worktrees + Claude 会话
    ↓
5. 通过 poll.sh 监控
    ↓
6. 增量验证 & 合并
    ↓
7. 清理（需确认）
```

## 任务状态

| 状态 | 含义 |
|------|------|
| `pending` | 已分配，未开始 |
| `in_progress` | 代理工作中 |
| `completed` | 完成，等待验收 |
| `blocked` | 需要协助（主代理可能解决） |
| `hil` | 需要人类介入 |
| `merged` | 已成功合并 |

## 手动脚本使用

所有脚本必须通过 `$POLYDEV_SCRIPTS` 变量调用：

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# 后台任务
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")

# 向会话发送命令
"$POLYDEV_SCRIPTS/send-to-session.sh" "$session_id" "docker ps"

# 捕获输出
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 50

# 分析状态
"$POLYDEV_SCRIPTS/analyze-output.sh" "$session_id" --lines 20 --json

# 关闭会话
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

## 会话 ID 格式

```
wo:workspace:branch.0    # Worktree 会话
bg:workspace:name.0      # 后台命令
ag:workspace:name.0      # 调查代理
```

## 故障排除

### tmux 会话找不到 (Linux/macOS)

```bash
tmux -S /tmp/polydev.sock list-sessions
tmux -S /tmp/polydev.sock attach
```

### WezTerm CLI 不工作 (Windows)

确保 WezTerm 在 PATH 中且已安装 Python 3。

### 会话崩溃或卡住

```bash
# 自动检测并恢复
./scripts/restore-session.sh .worktrees/your-branch

# 强制重启
./scripts/restore-session.sh .worktrees/your-branch --force
```

### 清理 worktrees

```bash
git worktree list           # 列出所有
git worktree remove <path>  # 移除指定
git worktree prune          # 清理无效引用
```

## 许可证

MIT License

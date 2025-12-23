# Worktree Orchestrator

使用 Git Worktrees 和终端会话实现并行开发编排的 Claude Code 技能。

## 项目简介

Worktree Orchestrator 是一个 Claude Code 技能（Skill），允许你同时在多个 Git 分支上并行执行开发任务。它通过创建多个 Git worktrees 和终端会话，让多个 Claude 代理同时工作，大幅提升复杂任务的完成效率。

### 核心特性

- **并行开发**: 同时在多个分支上运行独立的 Claude 代理
- **跨平台支持**:
  - Linux/macOS: 使用 tmux（隔离 socket）
  - Windows: 使用 WezTerm
- **自动化验收**: 支持 L0-L5 多级验收策略
- **状态监控**: 通过 task.toon 文件实时追踪任务状态
- **增量合并**: 完成一个任务，验证一个，合并一个

---

## 依赖关系

### Claude Code 依赖

| 依赖项 | 必需 | 说明 |
|--------|------|------|
| **Claude Code CLI** | 是 | 必须已安装并登录 |
| **superpowers 插件** | 是 | 提供 `executing-plans` 等核心技能 |

### 系统依赖

| 依赖项 | 版本要求 | 用途 |
|--------|----------|------|
| **Git** | >= 2.15 | Git worktree 功能 |
| **Bash** | >= 4.0 | 运行脚本 |

### 终端复用器（根据平台选择）

| 平台 | 工具 | 安装方式 |
|------|------|----------|
| **Linux** | tmux | `apt install tmux` 或 `yum install tmux` |
| **macOS** | tmux | `brew install tmux` |
| **Windows** | WezTerm + Python 3 | 见下方安装说明 |

---

## 安装步骤

### 第一步：安装 Claude Code CLI

如果尚未安装 Claude Code：

```bash
npm install -g @anthropic-ai/claude-code
claude  # 首次运行需要登录
```

### 第二步：安装 superpowers 插件

在 Claude Code 中执行以下命令：

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

安装后重启 Claude Code 使插件生效。

### 第三步：安装系统依赖

#### Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install git tmux
```

#### Linux (CentOS/RHEL/Fedora)

```bash
sudo dnf install git tmux
```

#### macOS

```bash
brew install git tmux
```

#### Windows

1. **安装 Git for Windows**
   - 下载: [git-scm.com](https://git-scm.com/download/win)
   - 安装时选择 "Git Bash" 选项

2. **安装 WezTerm**
   - 下载: [wezfurlong.org/wezterm](https://wezfurlong.org/wezterm/installation.html)
   - 安装后确保 `wezterm` 命令在 PATH 中

3. **安装 Python 3**
   - 下载: [python.org](https://www.python.org/downloads/)
   - 安装时勾选 "Add Python to PATH"

### 第四步：安装 worktree-orchestrator 技能

#### 方式 A：安装为个人技能（推荐，所有项目可用）

```bash
# Linux/macOS
mkdir -p ~/.claude/skills
cp -r /path/to/worktree-orchestrator ~/.claude/skills/

# Windows (Git Bash)
mkdir -p "$USERPROFILE/.claude/skills"
cp -r /path/to/worktree-orchestrator "$USERPROFILE/.claude/skills/"
```

#### 方式 B：安装为项目技能（仅当前项目可用，可通过 git 共享）

```bash
# 在你的项目根目录
mkdir -p .claude/skills
cp -r /path/to/worktree-orchestrator .claude/skills/
```

### 第五步：设置脚本执行权限（Linux/macOS）

```bash
chmod +x ~/.claude/skills/worktree-orchestrator/scripts/*.sh
chmod +x ~/.claude/skills/worktree-orchestrator/hooks/*.sh
```

### 第六步：验证安装

```bash
# 测试终端后端
cd ~/.claude/skills/worktree-orchestrator
source scripts/terminal-backend.sh
echo "后端类型: $(tb_get_backend)"
```

预期输出:
- Linux/macOS: `后端类型: tmux`
- Windows: `后端类型: wezterm`

---

## 使用方法

### 启动并行开发

在你的项目根目录中启动 Claude，然后描述你想要并行处理的任务：

```
我需要同时实现以下功能:
1. 用户认证 API
2. 用户资料管理
3. 仪表盘页面

请使用 worktree-orchestrator 技能并行开发这些功能。
```

Claude 会自动识别并使用 worktree-orchestrator 技能。

### 核心工作流程

```
用户请求
    ↓
Phase 1: 验收策略研究
    - 分析项目类型（Node.js/Python/Go 等）
    - 检测可用基础设施（测试框架、MCP 等）
    - 确定验收能力上限
    ↓
Phase 2: 任务分解
    - 分解任务并评估重要性
    - 分配验收级别
    ↓
Phase 3: 用户确认
    - 展示任务列表 + 验收策略
    ↓
Phase 4: 并行执行
    - 创建 N 个 worktrees
    - 启动 N 个 Claude 会话
    - 轮询监控状态
    ↓
Phase 5: 增量验证与合并
    - 完成一个，验证一个，合并一个
    ↓
Phase 6: 清理（需人工确认）
```

### 手动操作脚本

```bash
# 创建会话
./scripts/spawn-session.sh <workspace> <branch> <worktree-path> <plan-file>

# 监控状态（每 10 秒轮询）
./scripts/poll.sh .worktrees 10

# 聚焦特定会话
./scripts/focus-session.sh .worktrees/auth

# 检查 Git 状态
./scripts/git-info.sh diff .worktrees/auth
./scripts/git-info.sh conflicts .worktrees/auth
./scripts/git-info.sh status .worktrees/auth
```

### 调试 tmux 会话（Linux/macOS）

```bash
tmux -S /tmp/worktree-orchestrator.sock attach
```

---

## 验收级别说明

| 级别 | 名称 | 验收内容 | 适用场景 |
|------|------|---------|---------|
| L0 | skip | 无验收 | 文档、注释、配置 |
| L1 | compile | 仅编译通过 | 微小改动、代码格式化 |
| L2 | unit | 编译 + 单元测试 | 普通功能、工具函数 |
| L3 | integration | + 集成测试 | 模块交互、API 端点 |
| L4 | e2e | + 端到端测试 | 核心用户流程 |
| L5 | manual | + 人工验证 | 无法自动化、关键功能 |

---

## 状态说明

### 任务状态 (overall_status)

| 状态 | 含义 |
|------|------|
| `pending` | 已分配，未开始 |
| `in_progress` | 分支代理工作中 |
| `completed` | 分支完成，待验收 |
| `verifying` | 主代理执行验收 |
| `rejected` | 验收失败，需修复 |
| `merging` | 正在合并 |
| `conflict` | 合并冲突 |
| `merged` | 合并成功 |
| `cleanup_pending` | 等待清理确认 |
| `hil` | 需要人类介入 |

### 代理状态 (agent_status)

| 状态 | 含义 |
|------|------|
| `active` | Claude 活跃 |
| `idle` | Claude 意外停止 |
| `crashed` | 进程不存在 |

---

## 项目结构

```
worktree-orchestrator/
├── SKILL.md                    # 主技能定义文件
├── README.md                   # 本文档
├── scripts/
│   ├── terminal-backend.sh     # 终端后端抽象层 (tmux/wezterm)
│   ├── spawn-session.sh        # 创建 worktree + 终端会话
│   ├── poll.sh                 # 轮询状态监控
│   ├── focus-session.sh        # 激活指定会话
│   └── git-info.sh             # Git 状态检查
├── hooks/
│   ├── on-session-start.sh     # 会话启动钩子
│   └── on-stop.sh              # 会话停止钩子
├── templates/
│   ├── claude-settings.json    # Claude 设置模板
│   ├── task.toon.template      # 任务状态文件模板
│   └── worktree-agent-prompt.md # 子代理提示词
├── skills/
│   └── worktree-executor/      # 子代理执行技能（依赖 superpowers:executing-plans）
│       └── SKILL.md
└── docs/
    └── plans/                  # 设计文档
```

---

## 常见问题

### Q: 提示找不到 executing-plans 技能？

确保已安装 superpowers 插件：

```
/plugin install superpowers@superpowers-marketplace
```

然后重启 Claude Code。

### Q: tmux 会话找不到？

使用正确的隔离 socket：

```bash
tmux -S /tmp/worktree-orchestrator.sock list-sessions
```

### Q: Windows 上 WezTerm CLI 不工作？

确保 WezTerm 已添加到系统 PATH，并且 Python 3 已安装。

### Q: 如何清理残留的 worktrees？

```bash
git worktree list           # 列出所有 worktrees
git worktree remove <path>  # 移除指定 worktree
git worktree prune          # 清理无效引用
```

---

## 许可证

MIT License

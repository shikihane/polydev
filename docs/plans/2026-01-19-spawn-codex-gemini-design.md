# spawn-codex.sh 和 spawn-gemini.sh 设计文档

**日期**: 2026-01-19
**状态**: 设计完成，待实现

## 概述

创建两个独立脚本，用于在后台启动 Codex 和 Gemini 子代理进行调查任务。

**核心特点**:
- 不需要工作树（worktree）
- 不需要分支
- 与 `spawn-agent.sh`（Claude）功能对应
- 共用 `investigator-prompt.md` 模板

## 脚本参数

两个脚本参数完全相同：

```
<name> --prompt "<task>" --report <path> --cwd <dir> [--verbose]
```

| 参数 | 必需 | 说明 |
|------|------|------|
| `<name>` | 是 | 代理名称 |
| `--prompt` | 是 | 任务描述 |
| `--report` | 是 | 报告输出路径 |
| `--cwd` | 是 | 工作目录 |
| `--verbose` | 否 | 人类可读输出 |

**注意**: 不支持 `--model` 和 `--effort` 参数，由工具自动选择默认值。

## 启动命令

| 脚本 | CLI | 启动命令 |
|------|-----|---------|
| `spawn-codex.sh` | OpenAI Codex | `codex --dangerously-bypass-approvals-and-sandbox` |
| `spawn-gemini.sh` | Google Gemini | `gemini -y` |

对应 `spawn-agent.sh` 的 `claude --dangerously-skip-permissions`。

## 脚本结构

```
spawn-codex.sh / spawn-gemini.sh
├── 参数解析
│   ├── <name>
│   ├── --prompt "<task>"
│   ├── --report <path>
│   ├── --cwd <dir>
│   └── --verbose
│
├── 创建终端会话
│   └── tb_create_worktree_session "$ag_workspace" "$NAME" "$CWD" ""
│
├── 启动 LLM CLI
│   ├── spawn-codex.sh:  codex --dangerously-bypass-approvals-and-sandbox
│   └── spawn-gemini.sh: gemini -y
│
├── 等待 CLI 就绪
│   └── tb_wait_for_claude (通用逻辑，可复用)
│
├── 发送 prompt
│   └── 使用 investigator-prompt.md 模板
│
└── 输出 pane_id
```

## 文件清单

**新增文件**:
- `plugins/polydev/scripts/spawn-codex.sh`
- `plugins/polydev/scripts/spawn-gemini.sh`

**复用文件（不修改）**:
- `plugins/polydev/scripts/terminal-backend.sh`
- `plugins/polydev/templates/investigator-prompt.md`

## TOON 输出格式

与 `spawn-agent.sh` 一致：

```
[I] event=agent_starting,name=...,workspace=...,cwd=...
[I] event=terminal_session_created,pane_id=...,backend=...
[I] event=codex_started,pane_id=...   # 或 gemini_started
[I] event=prompt_sent,template=...
[I] event=agent_ready,pane_id=...,report=...
5  (pane_id on last line)
```

---

## 进度跟踪

| 时间 | 状态 | 说明 |
|------|------|------|
| 2026-01-19 | 设计完成 | 完成需求确认和设计文档 |
| 2026-01-19 | 实现完成 | 完成脚本实现、测试和文档更新 |

## 待办事项

- [x] 实现 `spawn-codex.sh`
- [x] 实现 `spawn-gemini.sh`
- [x] 测试 Codex 脚本
- [x] 测试 Gemini 脚本
- [x] 更新 CLAUDE.md 文档

## 失败经验记录

> 在此记录实现过程中遇到的问题和解决方案

### 设计阶段

1. **Codex 参数调研**
   - 最初考虑支持 `--model` 和 `--effort` 参数
   - 发现 `model_reasoning_effort` 只能通过 `-c` 配置覆盖，没有直接 CLI 参数
   - **决定**: 放弃这些参数，减少不确定性，由工具自动选择

2. **CLI 帮助信息获取**
   - Windows 上直接运行 `codex --help` 无法获取输出
   - **解决**: 通过 `node "path/to/codex.js" --help` 直接调用

---

## 参考

- `plugins/polydev/scripts/spawn-agent.sh` - Claude 版本实现参考
- Codex CLI: `codex --help`
- Gemini CLI: `gemini --help`

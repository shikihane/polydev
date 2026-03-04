# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Polydev is a Claude Code plugin that enables parallel development orchestration using Git worktrees and terminal sessions. It spawns multiple Claude agents to work on independent branches simultaneously, with status tracking via `task.toon` files.

**Cross-platform backends:**
- Linux/macOS: tmux (isolated socket at `/tmp/polydev.sock`)
- Windows: WezTerm

## Architecture

```
polydev/
├── commands/                  # Slash commands
│   └── polydev-brainstorm.md  # /polydev-brainstorm - task decomposition
├── skills/                    # Claude Code skills
│   ├── using-polydev/         # Entry point - skill selection guide
│   ├── polydev/               # Main orchestration skill
│   ├── writing-plans/         # Implementation plan generation
│   ├── worktree-executor/     # Sub-agent execution in worktrees
│   ├── terminal-task-runner/  # Background command hosting
│   ├── polycron/              # Scheduled task automation
│   └── agent-investigator/    # Read-only investigation agents
├── scripts/                   # Shell scripts (MUST use via $POLYDEV_SCRIPTS)
│   │
│   │ # Core (required for parallel dev)
│   ├── spawn-session.sh       # Create worktree + terminal + Claude (returns pane_id)
│   ├── poll.sh                # Status monitoring loop
│   ├── restore-session.sh     # Session recovery
│   ├── terminal-backend.sh    # Backend abstraction (internal)
│   │
│   │ # Session management
│   ├── wo-send-command.sh     # Send commands to worktree sessions
│   ├── send-to-session.sh     # Send commands to any session (via pane_id)
│   ├── capture-screen.sh      # Read terminal output (via worktree path or --pane-id)
│   ├── list-sessions.sh       # List active sessions
│   ├── close-session.sh       # Terminate sessions (via worktree path or --pane-id)
│   │
│   │ # Background tasks
│   ├── run-background.sh      # Background commands (no sub-Claude, returns pane_id)
│   ├── spawn-agent.sh         # Claude sub-agent with prompt (returns pane_id)
│   ├── spawn-codex.sh         # Codex CLI session with prompt (returns pane_id)
│   └── spawn-gemini.sh        # Gemini CLI session with prompt (returns pane_id)
│   │
│   │ # Scheduled tasks
│   ├── polycron-add.sh        # Register scheduled task
│   ├── polycron-remove.sh     # Remove scheduled task
│   ├── polycron-list.sh       # List scheduled tasks
│   ├── polycron-history.sh    # View trigger history
│   └── polycron-trigger.sh    # OS scheduler entry point (internal)
│   │
│   │ # Cleanup
│   └── cleanup-worktree.sh    # Clean up worktree + session
├── hooks/                     # Claude Code hooks
└── templates/                 # Task templates
```

## Critical Rules

### Script Path - MANDATORY

**All scripts must be called via `$POLYDEV_SCRIPTS` variable. NEVER use `./scripts/`**

### Windows Script Execution Fallback

在某些 Claude Code CLI 版本中，Windows (Git Bash/MINGW) 上直接执行脚本可能出现静默失败（返回 exit code 0 但无输出）。**如果遇到脚本执行无输出的情况**，可使用 `bash -c "$(cat ...)"` 模式作为回退方案：

```bash
# 自动由 SessionStart hook 写入，无需手动设置路径
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)

# 正常方式（优先使用）
"$POLYDEV_SCRIPTS/list-sessions.sh"

# 回退方式（仅当上面无输出时使用）
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/list-sessions.sh")"
```

> 如果 `~/.polydev/scripts-path` 不存在，说明 hook 未执行。手动设置:
> `POLYDEV_SCRIPTS="$CLAUDE_PLUGIN_ROOT/scripts"`

**注意**: 这是 Claude Code CLI 工具的已知 bug，在较新版本中已修复。正常情况下直接执行即可。

### Workspace Parameter - CRITICAL

**The `workspace` parameter determines window grouping. Same workspace = same window with multiple tabs.**

```bash
# ❌ WRONG - Creates 3 separate windows
"$POLYDEV_SCRIPTS/spawn-session.sh" project-ws1 feature/auth ...
"$POLYDEV_SCRIPTS/spawn-session.sh" project-ws2 feature/api ...
"$POLYDEV_SCRIPTS/spawn-session.sh" project-ws3 feature/ui ...

# ✅ CORRECT - Creates 1 window with 3 tabs
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/auth ...
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/api ...
"$POLYDEV_SCRIPTS/spawn-session.sh" my-project feature/ui ...
```

**Rule:** Use a consistent workspace name (e.g., project name) for all parallel tasks in the same project.

### Script Usage by Scenario

**All scripts must be called via `$POLYDEV_SCRIPTS` variable.**

**Core workflow:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Create worktree + Claude | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status (loop) | `poll.sh` | `<worktrees-dir> <timeout>` |
| Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` |

**Session management:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Send to worktree (has task.toon) | `wo-send-command.sh` | `<worktree-path> "<cmd>" [--peek N]` |
| Send to any session (SSH, REPL) | `send-to-session.sh` | `<pane_id> "<cmd>" [--peek N]` |
| Read screen output | `capture-screen.sh` | `<worktree-path> [--lines N]` or `--pane-id <id>` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<worktree-path>` or `--pane-id <id>` |

**Background tasks:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Start background command | `run-background.sh` | `<name> "<cmd>" [--cwd <dir>] [--peek N]` |
| Start Claude sub-agent | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path> --cwd <dir> [--peek N]` |
| Start Codex CLI session | `spawn-codex.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |
| Start Gemini CLI session | `spawn-gemini.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |

**Scheduled tasks:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Add scheduled task | `polycron-add.sh` | `<job-id> --schedule "..." --prompt "..." --cwd <dir>` |
| Remove scheduled task | `polycron-remove.sh` | `<job-id>` |
| List scheduled tasks | `polycron-list.sh` | `[--all\|--enabled\|--disabled]` |
| View task history | `polycron-history.sh` | `[job-id] [--last N]` |

**Cleanup:**
| Scenario | Script | Parameters |
|----------|--------|------------|
| Clean up worktree | `cleanup-worktree.sh` | `<worktree-path>` |

### --peek: 执行后自动截屏

所有返回 pane_id 的脚本均支持 `--peek N` 选项:
- `--peek 0`: 立即截屏
- `--peek 5`: 等 5 秒后截屏
- 不传: 不截屏

示例:
```bash
"$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps" --peek 3
"$POLYDEV_SCRIPTS/run-background.sh" build "npm test" --peek 10
```

### Cost Control

**Parallel sub-agents MUST use `model: "sonnet"`:**

```javascript
// WRONG - inherits expensive model
Task({ prompt: "...", subagent_type: "general-purpose" })

// CORRECT
Task({ prompt: "...", subagent_type: "general-purpose", model: "sonnet" })
```

### Status Communication

Sub-agents communicate only via `task.toon` files. Main agent monitors via `poll.sh`.

**Key statuses:**
- `blocked`: Main agent might resolve (dependency, env issue)
- `hil`: Human must decide (credentials, design decisions, ambiguity)

### pane_id Format

pane_id 是主要标识符，格式因后端而异：

| 后端 | pane_id 格式 | 示例 |
|------|-------------|------|
| WezTerm | 数字 | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

**注意**：调试信息输出到 stderr，人类可通过 `[D]` 前缀查看工作树、分支等上下文。

## Development Workflow

1. **Brainstorm** (`/polydev-brainstorm`) - Task decomposition via command
2. **Plan** (`polydev:writing-plans`) - Detailed implementation plans
3. **Execute** (`polydev:polydev`) - Spawn parallel worktrees
4. **Monitor** - Poll loop with `poll.sh`, handle blockers
5. **Verify & Merge** - Per verification level (L0-L5)
6. **Cleanup** - Human confirms before deletion

**Skill selection:** Use `polydev:using-polydev` to determine which skill/command to use.

## Scheduled Tasks (polycron)

Polycron enables scheduling Claude agents to run at specific times using OS-level schedulers:
- **Linux/macOS**: crontab
- **Windows**: schtasks

**Data storage**: `~/.polydev/cron/jobs/` (job definitions), `~/.polydev/cron/history.jsonl` (trigger log)

**Common operations**:
```bash
# Add daily task
"$POLYDEV_SCRIPTS/polycron-add.sh" daily-report \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report" \
  --cwd /path/to/project

# Add one-time task
"$POLYDEV_SCRIPTS/polycron-add.sh" deploy \
  --at "2026-02-15 14:00" \
  --prompt "Deploy to production" \
  --cwd /path/to/app

# List all jobs
"$POLYDEV_SCRIPTS/polycron-list.sh"

# View history
"$POLYDEV_SCRIPTS/polycron-history.sh" --last 10

# Remove job
"$POLYDEV_SCRIPTS/polycron-remove.sh" daily-report
```

**How it works**: OS scheduler triggers `polycron-trigger.sh` → spawns Claude agent via `spawn-agent.sh` → logs to history.

## Testing Scripts

```bash
# Verify terminal backend
source scripts/terminal-backend.sh
echo "Backend: $(tb_get_backend)"
```

## Verification Levels

| Level | Name | Scope |
|-------|------|-------|
| L0 | skip | No verification (docs, config) |
| L1 | compile | Build only |
| L2 | unit | Build + unit tests |
| L3 | integration | + integration tests |
| L4 | e2e | + end-to-end tests |
| L5 | manual | + human verification |

## Windows Git Bash Notes

- Use `python` not `python3` (detection handled by `terminal-backend.sh`)
- Always quote paths with spaces
- Scripts handle path conversion automatically

## Troubleshooting

### WezTerm Cold Start Timeout

After system boot, WezTerm's mux server may not be fully initialized, causing `wezterm cli list` and other commands to timeout or hang.

**Solution**: Wait a few seconds and retry, or manually open a WezTerm window first to initialize the service.

### Nested Session Detection (Claude Code 2.1.39+)

**Background**: Claude Code now blocks nested sessions to prevent crashes from shared runtime resources.

**Error Message**:
```
Error: Claude Code cannot be launched inside another Claude Code session.
Nested sessions share runtime resources and will crash all active sessions.
To bypass this check, unset the CLAUDECODE environment variable.
```

**Polydev Solution**: All spawn scripts (`spawn-session.sh`, `spawn-agent.sh`, `restore-session.sh`) unset `CLAUDECODE` before launching Claude:

```bash
unset CLAUDECODE && claude --dangerously-skip-permissions --model $MODEL
```

**Why This Is Safe**:
- Polydev spawns Claude instances in **completely isolated terminal sessions** (tmux panes / WezTerm tabs)
- This is the official recommended pattern: "use separate terminals/worktrees"
- The `CLAUDECODE` check cannot distinguish between unsafe (same shell) and safe (isolated terminal) scenarios

**Potential Risks**:
- If terminal isolation fails, sessions may conflict ("talking over each other")
- Monitor `task.toon` status for anomalies (unexpected state changes, corrupted data)

**References**:
- GitHub Issue #25803: Nested session check blocks non-interactive subcommands
- GitHub Issue #25434: Session docs missing nested-Claude launch guard behavior

### WezTerm 跨 Shell 支持（PowerShell / Bash 自动检测）

WezTerm 在 Windows 上默认打开 PowerShell，在其他平台可能打开 bash。polydev 通过自动检测 pane 的 shell 类型来适配命令语法。

**实现机制**:
1. `_wezterm_create_session()` 创建 pane 后，捕获初始屏幕输出
2. 检测 `PS C:\` 等 PowerShell 提示符特征 → 标记为 `powershell`，否则 `bash`
3. Shell 类型存储在 `$TMPDIR/polydev-shell-types/<pane_id>`
4. `tb_launch_claude()` 根据 shell 类型自动选择语法：
   - bash: `unset CLAUDECODE && claude ...`
   - PowerShell: `Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue; claude ...`

**使用 `tb_launch_claude()` 的脚本**: `spawn-agent.sh`、`spawn-session.sh`、`restore-session.sh`。
**不要直接用 `tb_send_command()` 发送 `unset CLAUDECODE && ...`**，因为这在 PowerShell 中会失败。

**注意**: `spawn-codex.sh` 和 `spawn-gemini.sh` 不需要改动，因为它们不需要 `unset CLAUDECODE`，且命令本身跨 shell 兼容。

### ⛔ NEVER Optimize: WezTerm Send Text Sleep Time

**terminal-backend.sh 中的 `_wezterm_send_command` 和 `_wezterm_send_multiline_text` 函数里，发送回车键前的 sleep 时间绝对禁止优化！**

```bash
# ⛔ 绝对禁止修改这个 sleep 时间！
if [ "$execute" = "true" ]; then
    sleep 2  # ← 必须 >= 2 秒，否则回车键会失效！
    printf '\r' | wezterm cli send-text --no-paste --pane-id "$pane_id"
fi
```

**原因**: Claude Code 需要足够时间处理大段文本输入。如果 sleep 时间 < 2 秒，回车键会在文本还没完全处理完时发送，导致命令不执行。

**历史教训**: 2026-01-11 曾为"优化启动速度"将 `sleep 2` 改为 `sleep 0.3`，结果导致回车键功能完全失效。

### ⛔ NEVER Remove: WezTerm --no-paste Flag

**所有 `wezterm cli send-text` 调用必须带 `--no-paste` 标志！**

**原因**: `wezterm cli send-text` 默认使用 bracketed paste 模式，发送的文本被 `ESC[200~...ESC[201~` 包裹。如果目标 pane 的 shell（bash/readline/zsh）启用了 bracketed paste mode，`\r` 会被当作粘贴的字面文本而非回车键，导致命令不执行。

**历史教训**: 2026-02-09 发现 `send-to-session.sh` 发送回车无效，根因就是缺少 `--no-paste`。

## Shell Inline Python Escaping

When passing shell variables to inline Python, use environment variables instead of string interpolation to avoid escaping issues with special characters (`/`, `'`, `"`):

```bash
# ✅ Correct - use environment variable
PANE_ID="$pane_id" $PYTHON -c "
import os
pid = os.environ.get('PANE_ID', '')
"

# ❌ Wrong - string interpolation breaks on special chars
$PYTHON -c "if pid == '$pane_id': ..."
```

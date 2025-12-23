# Tmux Support Design

## Overview

为 worktree-orchestrator 添加 tmux 后端支持，通过抽象层实现双后端（tmux/wezterm）兼容。

## Design Decisions

| 决策项 | 选择 |
|-------|------|
| 架构方式 | 抽象层模式 |
| API 级别 | 高级别业务语义封装 |
| 环境检测 | 启动时一次性检测 |
| 会话标识符 | 语义化格式 `wo:session:window.pane` |
| 隔离方式 | Socket 隔离 |
| Socket 路径 | `/tmp/worktree-orchestrator.sock` |
| 后端选择 | 严格按 OS（Windows→wezterm, Linux/macOS→tmux）|

## Architecture

```
scripts/
├── terminal-backend.sh      # 抽象层（新增）
├── spawn-session.sh         # 改造：调用抽象层
├── focus-session.sh         # 改造：调用抽象层
├── poll.sh                  # 改造：调用抽象层
└── git-info.sh              # 不变（无终端依赖）
```

## Session ID Format

```
wo:myproject-parallel:feature-auth.0
│  │                  │            │
│  │                  │            └─ pane index
│  │                  └─ window name (branch)
│  └─ session name (workspace)
└─ 前缀标识 worktree-orchestrator
```

## API Design

### Core APIs

```bash
# 会话生命周期
tb_create_worktree_session(workspace, branch, worktree_path, plan_file)
  # → 返回 session_id

tb_get_session_info(session_id)
  # → 返回 pane_id|status|window_name|cwd

# 状态轮询
tb_poll_sessions(workspace)
  # → 返回所有会话状态

tb_is_session_alive(session_id)
  # → 返回 0 (存活) 或 1 (不存在)

# 会话交互
tb_focus_session(session_id)
tb_send_command(session_id, command, execute=true)

# 清理
tb_cleanup_session(session_id)
```

## Backend Implementations

### tmux Backend

```bash
TB_SOCKET="/tmp/worktree-orchestrator.sock"
_tmux() { tmux -S "$TB_SOCKET" "$@"; }

_parse_session_id() {
  local id="$1"
  id="${id#wo:}"
  SESSION="${id%%:*}"
  local rest="${id#*:}"
  WINDOW="${rest%.*}"
  PANE="${rest##*.}"
  TARGET="$SESSION:$WINDOW.$PANE"
}

_tmux_create_session() {
  local workspace="$1" branch="$2" cwd="$3"

  if ! _tmux has-session -t "$workspace" 2>/dev/null; then
    pane_id=$(_tmux new-session -d -s "$workspace" \
      -n "$branch" -c "$cwd" -P -F "#{pane_id}" bash)
  else
    pane_id=$(_tmux new-window -t "$workspace:" \
      -n "$branch" -c "$cwd" -P -F "#{pane_id}" bash)
  fi

  echo "wo:$workspace:$branch.0"
}

_tmux_is_alive() {
  local target="$1"
  _tmux list-panes -t "$target" &>/dev/null
}
```

### wezterm Backend

```bash
WO_MAP_FILE="/tmp/worktree-orchestrator-map.json"

_wezterm_create_session() {
  local workspace="$1" branch="$2" cwd="$3"

  existing_window=$(wezterm cli list --format json | \
    python3 -c "import sys,json; d=json.load(sys.stdin); \
    w=[x['window_id'] for x in d if x.get('workspace')=='$workspace']; \
    print(w[0] if w else '')")

  if [ -n "$existing_window" ]; then
    pane_id=$(wezterm cli spawn --window-id "$existing_window" \
      --cwd "$cwd" -- bash)
  else
    pane_id=$(wezterm cli spawn --new-window \
      --workspace "$workspace" --cwd "$cwd" -- bash)
  fi

  wezterm cli set-tab-title --pane-id "$pane_id" "$branch"
  _save_mapping "$pane_id" "wo:$workspace:$branch.0"

  echo "wo:$workspace:$branch.0"
}

_wezterm_is_alive() {
  local session_id="$1"
  local pane_id=$(_get_pane_id "$session_id")
  wezterm cli list --format json 2>/dev/null | \
    grep -q "\"pane_id\": *$pane_id"
}
```

## Concept Mapping

| WezTerm | tmux | session_id 对应 |
|---------|------|----------------|
| workspace | session | `wo:SESSION:...` |
| window (tab) | window | `wo:...:WINDOW.pane` |
| pane | pane | `wo:...:window.PANE` |

## Interface Mapping

| WezTerm CLI | tmux 等效命令 |
|------------|--------------|
| `list --format json` | `list-panes -a -F "format"` + 解析 |
| `spawn --window-id --cwd` | `new-window -t SESSION: -c PATH` |
| `spawn --new-window --workspace` | `new-session -d -s NAME` |
| `send-text --pane-id --no-paste` | `send-keys -t ID -l "text"` + `C-m` |
| `set-tab-title --pane-id` | `rename-window -t ID "title"` |
| `activate-pane --pane-id` | `select-pane -t ID` |
| `kill-pane --pane-id` | `kill-pane -t ID` |

## File Changes

**新增：**
- `scripts/terminal-backend.sh` - 抽象层主文件

**修改：**
- `scripts/spawn-session.sh` - 改用抽象层 API
- `scripts/poll.sh` - 改用抽象层 API
- `scripts/focus-session.sh` - 改用抽象层 API
- `SKILL.md` - 更新文档

**不变：**
- `scripts/git-info.sh`
- `hooks/*`
- `templates/*`

## Implementation Order

1. 创建 `terminal-backend.sh` 抽象层框架
2. 实现 tmux 后端
3. 实现 wezterm 后端
4. 改造 `spawn-session.sh`
5. 改造 `poll.sh`
6. 改造 `focus-session.sh`
7. 更新 `SKILL.md` 文档
8. 测试验证

# TOON 输出重构计划 (修订版)

## 目标
1. 将 polydev 脚本输出改为 TOON 格式，减少 agent 上下文浪费
2. **重大变更**：改用 pane_id 替代 session_id，消除重复解析和查找
3. **新增需求**：保留人类调试信息到 stderr

---

## 已完成的变更

### 删除的脚本

| 脚本 | 原因 |
|------|------|
| `analyze-output.sh` | 从未实际调用 |
| `wait-for-pattern.sh` | 设计过度，与实际工作流不符 |
| `test-terminal-backend.sh` | 开发调试用 |
| `focus-session.sh` | 从未实际调用 |

### 已修改的脚本

| 脚本 | 状态 | 变更内容 |
|------|------|----------|
| `task.toon.template` | ✅ | meta 行改为 pane_id |
| `terminal-backend.sh` | ✅ | 返回 pane_id，删除缓存逻辑 |
| `spawn-session.sh` | ✅ | 适配 pane_id |
| `poll.sh` | ✅ | 适配 pane_id，性能优化 |
| `capture-screen.sh` | ✅ | 支持 --pane-id 参数，调试信息到 stderr |
| `close-session.sh` | ✅ | 支持 --pane-id 参数，调试信息到 stderr |
| `send-to-session.sh` | ✅ | 直接使用 pane_id |
| `wo-send-command.sh` | ✅ | 适配 pane_id |
| `restore-session.sh` | ✅ | 适配 pane_id |
| `run-background.sh` | ✅ | 适配 pane_id |
| `spawn-agent.sh` | ✅ | 适配 pane_id |

### 待完成

| 任务 | 状态 |
|------|------|
| 更新 Skill 文档 | ⏳ 进行中 |
| 更新 CLAUDE.md | ⏳ 待开始 |

---

## 重大架构变更：pane_id 替代 session_id

### 问题现状

```
session_id (wo:myproject:feature.0)
    ↓ 每次操作都要解析
workspace + tab_title
    ↓ 每次操作都要查找
pane_id (如 5)
    ↓
发送命令/获取文本
```

**痛点**：
- 每次操作都要解析 session_id
- 每次都要调用 `wezterm cli list` + Python 解析
- 重复查询，缓存设计复杂且不可靠

### 新设计

```
创建会话时立即获取 pane_id → 存入 task.toon
    ↓
后续操作直接用 pane_id
    ↓
一次获取，多次使用
```

### task.toon meta 行变更

```diff
- meta{worktree,branch,session_id,created}:
-   .worktrees/feature,feature,wo:myproject:feature.0,2025-01-09T10:30:00Z
+ meta{worktree,branch,pane_id,created}:
+   .worktrees/feature,feature,5,2025-01-09T10:30:00Z
```

### terminal-backend.sh 变更

**1. tb_create_worktree_session 返回 pane_id**

```bash
# 新实现
tb_create_worktree_session() {
  local workspace="$1"
  local title="$2"
  local cwd="$3"
  local plan_file="$4"

  # 创建 tab，获取 pane_id
  pane_id=$(wezterm cli spawn \
    --workspace "$workspace" \
    --tab-title "$title" \
    --cwd "$cwd" \
    2>/dev/null | jq -r '.pane_id')

  echo "$pane_id"
}
```

**2. 删除 `_wezterm_get_pane_id` 相关代码**

- 删除 `_wezterm_get_pane_id()`
- 删除 `_wezterm_get_pane_id_cached()`
- 删除 `_wezterm_refresh_pane_cache()`
- 删除 pane_id 文件缓存逻辑

**3. 所有函数改用 pane_id 参数**

```bash
# 旧
tb_send_command() {
  pane_id=$(_wezterm_get_pane_id "$session_id")
  wezterm cli send-text --pane-id "$pane_id" --text "$cmd"
}

# 新
tb_send_command() {
  local pane_id="$1"
  local cmd="$2"
  local execute="${3:-true}"
  wezterm cli send-text --pane-id "$pane_id" --text "$cmd" --no-paste "$execute"
}
```

### tmux 后端兼容

tmux 用 `session:window.pane` 格式，可以直接当 pane_id 使用，无需修改。

---

## 新增需求：人类调试信息保留

### 设计原则

- **stdout**：TOON 格式输出（供 agent 解析）
- **stderr**：人类调试信息（供人类监控）

### 调试信息格式

```
[D] pane_id=5,worktree=.worktrees/feature,branch=feature,workspace=myproject
```

### 支持调试信息的脚本

| 脚本 | 调试信息 |
|------|----------|
| `capture-screen.sh` | pane_id, worktree, branch, workspace |
| `close-session.sh` | pane_id, worktree, branch, workspace |
| `send-to-session.sh` | pane_id, command |
| 其他脚本 | 根据上下文添加相关调试信息 |

---

## TOON 输出格式

### 事件日志
```
[I] event=session_starting,workspace=...,branch=...,worktree=...,pane_id=5
[I] event=terminal_session_created,pane_id=5,backend=...
[I] event=session_ready,pane_id=5,worktree=...
```

### 状态行
```
worktree=.worktrees/feature,branch=feature,overall_status=in_progress,agent_status=active,pane_id=5
pane_id=5,status=alive,cwd=/path
```

### 命令发送
```
[I] event=command_sent,pane_id=5,command=...,executed=true
```

---

## 验证步骤

```bash
# 1. 测试创建会话（验证 pane_id 正确返回）
./spawn-session.sh test feature-test .worktrees/feature-test PLAN.md --verbose

# 2. 验证 task.toon 格式
cat .worktrees/feature-test/task.toon
# 应显示: meta{worktree,branch,pane_id,created}:

# 3. 测试 poll.sh
./poll.sh .worktrees 10 --verbose

# 4. 测试 capture-screen.sh
./capture-screen.sh .worktrees/feature-test --lines 20

# 5. 测试 close-session.sh
./close-session.sh .worktrees/feature-test
```

---

## 兼容性

- **旧 worktree**：需手动删除后重建，或修改旧 task.toon
- **tmux 后端**：兼容，无需修改
- **Skill 文档**：需同步更新所有示例

---

## TOON 输出速查

| 类型 | 格式 | 示例 |
|------|------|------|
| **事件日志** | `[I] event=xxx,key1=val1,pane_id=N` | `[I] event=session_ready,pane_id=5,branch=feature` |
| **表格行** | `pane_id=N,key1=val1` | `pane_id=5,status=alive,cwd=/path` |
| **错误** | `[E] error=xxx,pane_id=N` | `[E] error=Session not found,pane_id=5` |
| **调试** | `[D] pane_id=N,key1=val1` | `[D] pane_id=5,worktree=.worktrees/feature` |

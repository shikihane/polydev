---
name: terminal-task-runner
description: "Use when running commands that take >30 seconds (builds, tests, servers) - hosts in terminal session for monitoring and recovery"
---

# Terminal Task Runner

在终端（tmux/wezterm）中托管后台命令并监控状态。

---

## 脚本路径

**所有脚本必须通过 `$POLYDEV_SCRIPTS` 变量调用，不要使用相对路径 `./scripts/`**

```bash
# 在调用任何脚本前，先设置路径变量
POLYDEV_SCRIPTS="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")")/scripts"
# 或者如果在 skill 上下文中，使用 skill base directory:
# POLYDEV_SCRIPTS="<skill-base-dir>/../scripts"

# 然后使用变量调用脚本
"$POLYDEV_SCRIPTS/run-background.sh" <name> "<command>"
```

**Claude Code 调用时**: 使用插件的安装路径
```bash
# 插件路径示例（根据实际安装位置）
POLYDEV_SCRIPTS="/path/to/polydev/scripts"
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

---

## 使用时机

- 构建命令 (`npm run build`, `cargo build`, `go build`)
- 测试命令 (`npm test`, `pytest`, `cargo test`)
- 开发服务器 (`npm run dev`, `cargo watch`)
- 安装依赖 (`npm install`, `pip install`)
- **SSH 远程连接** (交互式会话)
- 任何可能超过 30 秒的命令

---

## 脚本使用约束（必须遵守）

### 🔴 场景 A: 启动后台任务
**脚本**: `run-background.sh`
**参数**: `<name> "<command>" [--cwd <dir>]`
**返回**: session_id (格式: `bg:<workspace>:<name>.0`)

```bash
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")
# 返回: bg:bg-myproject:build.0
```

### 🔴 场景 B: 向已存在的 session 发送命令（SSH、REPL 等交互场景）
**脚本**: `send-to-session.sh`
**参数**: `<session_id> "<command>" [--no-enter]`
**session_id 格式**: `bg:xxx`, `wo:xxx`, `ag:xxx`

```bash
# 向 SSH 会话发送命令
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh-remote.0 "docker ps"

# 发送密码（不按回车）
"$POLYDEV_SCRIPTS/send-to-session.sh" bg:bg-polydev:ssh-remote.0 "mypassword" --no-enter
```

### 🔴 场景 C: 分析输出状态
**脚本**: `analyze-output.sh`
**参数**: `<session_id> --lines <N> [--json]`
**返回**: status (running|idle|success|failed|done)

```bash
result=$("$POLYDEV_SCRIPTS/analyze-output.sh" bg:bg-myproj:build.0 --lines 20 --json)
```

### 🔴 场景 D: 等待模式匹配
**脚本**: `wait-for-pattern.sh`
**参数**: `<session_id> --success "<pattern>" [--fail "<pattern>"] [--timeout <seconds>]`
**返回**: exit code (0=success, 1=fail, 2=timeout)

```bash
"$POLYDEV_SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300
```

### 🔴 场景 E: 查看原始输出
**脚本**: `capture-screen.sh`
**参数**: `--session <wo:session_id> --lines <N>`
**注意**: session 参数需要 `wo:` 前缀！

```bash
# bg: 转 wo: 前缀
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 50
```

### 🔴 场景 F: 关闭任务
**脚本**: `close-session.sh`
**参数**: `<session_id>`

```bash
"$POLYDEV_SCRIPTS/close-session.sh" bg:bg-myproj:build.0
```

### 🔴 场景 G: 列出所有会话
**脚本**: `list-sessions.sh`
**参数**: `[workspace]` (可选过滤)

```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
"$POLYDEV_SCRIPTS/list-sessions.sh" myproject
```

---

## 禁止事项

```
❌ 不要使用相对路径 ./scripts/（离开插件目录会失效）
❌ 不要使用 Bash 工具的 run_in_background 参数
❌ 不要使用 & 放入后台
❌ 不要使用 nohup
❌ 不要自己调用 tmux/wezterm 命令
❌ 不要用错脚本（如用 send-command.sh 发送给 bg: session）

✅ 必须通过 $POLYDEV_SCRIPTS 变量调用脚本
✅ 必须监控任务状态
✅ 完成后必须清理 session
```

---

## 典型工作流

### 工作流 A: 构建任务（轮询监控）

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# 启动
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" build "npm run build")

# 轮询检查
while true; do
  result=$("$POLYDEV_SCRIPTS/analyze-output.sh" "$session_id" --lines 20 --json)
  status=$(echo "$result" | jq -r '.status')

  case "$status" in
    success|done)
      echo "Task completed"
      break
      ;;
    failed)
      echo "Task failed"
      "$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 50
      break
      ;;
  esac

  sleep 10
done

# 清理
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

### 工作流 B: SSH 交互会话

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# 1. 启动 SSH 连接
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" ssh-server "ssh user@host")

# 2. 等待连接（可能需要密码）
sleep 3
"$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 20

# 3. 如果需要密码
"$POLYDEV_SCRIPTS/send-to-session.sh" "$session_id" "mypassword"

# 4. 发送命令
"$POLYDEV_SCRIPTS/send-to-session.sh" "$session_id" "docker ps"

# 5. 查看结果
sleep 2
"$POLYDEV_SCRIPTS/capture-screen.sh" --session "${session_id/bg:/wo:}" --lines 30

# 6. 完成后关闭
"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

### 工作流 C: 等待模式

```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"

# 启动并等待
session_id=$("$POLYDEV_SCRIPTS/run-background.sh" test "npm test")

# 等待成功或失败
"$POLYDEV_SCRIPTS/wait-for-pattern.sh" "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300

exit_code=$?
case $exit_code in
  0) echo "Tests passed" ;;
  1) echo "Tests failed" ;;
  2) echo "Timeout" ;;
esac

"$POLYDEV_SCRIPTS/close-session.sh" "$session_id"
```

---

## Session ID 格式

```
bg:<workspace>:<name>.0
│  │          │      │
│  │          │      └─ pane index (always 0)
│  │          └─ task name
│  └─ workspace (默认: bg-<当前目录名>)
└─ prefix (background task)
```

**前缀转换规则**:
- `capture-screen.sh` 的 `--session` 参数需要 `wo:` 前缀
- 其他脚本接受原始 `bg:` 前缀
- 转换方法: `${session_id/bg:/wo:}`

---

## 故障排除

### 命令没有执行
```bash
"$POLYDEV_SCRIPTS/list-sessions.sh"
```

### 看不到输出
```bash
"$POLYDEV_SCRIPTS/capture-screen.sh" --session wo:bg-myproj:build.0 --lines 100
```

### Session 卡住
```bash
"$POLYDEV_SCRIPTS/close-session.sh" bg:myproj:build.0
"$POLYDEV_SCRIPTS/run-background.sh" build "npm run build"
```

---
name: terminal-task-runner
description: Use when executing long-running background commands that need monitoring. Prefer tmux/wezterm over Claude Code's built-in background mechanism.
---

# Terminal Task Runner

在终端（tmux/wezterm）中托管后台命令并监控状态。

---

## 使用时机

- 构建命令 (`npm run build`, `cargo build`, `go build`)
- 测试命令 (`npm test`, `pytest`, `cargo test`)
- 开发服务器 (`npm run dev`, `cargo watch`)
- 安装依赖 (`npm install`, `pip install`)
- 任何可能超过 30 秒的命令

## 为什么不用 Claude Code 内置后台？

| 特性 | 内置后台 | 终端托管 |
|------|---------|---------|
| 稳定性 | 可能被中断 | 持久运行 |
| 输出查看 | 只能等结束 | 随时查看 scrollback |
| 恢复能力 | 进程丢失 | session 可恢复 |
| 多任务 | 有限制 | 无限制 |

---

## 核心脚本

```bash
# 1. 启动后台任务
./scripts/run-background.sh <name> "<command>" [--cwd <dir>]
# 返回: bg:<workspace>:<name>.0

# 2. 分析输出状态
./scripts/analyze-output.sh <session_id> --lines 20 [--json]
# 返回: status (running|idle|success|failed|done)

# 3. 等待模式匹配
./scripts/wait-for-pattern.sh <session_id> --success "<pattern>" [--fail "<pattern>"] [--timeout 300]
# 阻塞直到匹配，返回: success|fail|timeout

# 4. 查看原始输出
./scripts/capture-screen.sh --session <wo:session_id> --lines 50

# 5. 关闭任务
./scripts/close-session.sh <session_id>
```

---

## 典型工作流

### 方式 A: 轮询监控

```bash
# 启动
session_id=$(./scripts/run-background.sh build "npm run build")

# 轮询检查（每 10 秒）
while true; do
  result=$(./scripts/analyze-output.sh "$session_id" --lines 20 --json)
  status=$(echo "$result" | jq -r '.status')

  case "$status" in
    success|done)
      echo "✅ 任务完成"
      break
      ;;
    failed)
      echo "❌ 任务失败"
      # 查看详细错误
      ./scripts/capture-screen.sh --session "${session_id/bg:/wo:}" --lines 50
      break
      ;;
    idle)
      # 可能完成了，进一步检查
      ;;
    running)
      # 继续等待
      ;;
  esac

  sleep 10
done

# 清理
./scripts/close-session.sh "$session_id"
```

### 方式 B: 等待模式

```bash
# 启动并等待
session_id=$(./scripts/run-background.sh test "npm test")

# 等待成功或失败
result=$(./scripts/wait-for-pattern.sh "$session_id" \
  --success "passed|All tests passed" \
  --fail "failed|Error" \
  --timeout 300)

exit_code=$?
case $exit_code in
  0) echo "✅ 测试通过" ;;
  1) echo "❌ 测试失败" ;;
  2) echo "⏰ 超时" ;;
esac

./scripts/close-session.sh "$session_id"
```

---

## 状态判断策略

根据命令类型选择读取行数和匹配模式：

| 命令类型 | 推荐行数 | 成功模式 | 失败模式 |
|---------|---------|---------|---------|
| npm install | 10 | `added .* packages` | `ERR!` |
| npm run build | 20 | `Build completed\|Compiled` | `error\|Error` |
| npm test | 30 | `passed\|✓` | `failed\|✗` |
| cargo build | 15 | `Finished` | `error\[E` |
| cargo test | 20 | `passed` | `failed` |
| pytest | 30 | `passed` | `failed\|error` |
| go build | 10 | (idle) | `cannot\|error` |
| generic | 20 | (idle 60s+) | `error\|fail\|panic` |

---

## Session ID 格式

```
bg:<workspace>:<name>.0
│  │          │      │
│  │          │      └─ pane index (always 0)
│  │          └─ task name
│  └─ workspace (默认: 当前目录名)
└─ prefix (background task)
```

**注意**: 内部调用 terminal-backend.sh 时需要转换为 `wo:` 前缀：
```bash
internal_id="${session_id/bg:/wo:}"
tb_is_session_alive "$internal_id"
```

---

## 禁止事项

```
❌ 不要使用 Bash 工具的 run_in_background 参数
❌ 不要使用 & 放入后台
❌ 不要使用 nohup
❌ 不要自己调用 tmux/wezterm 命令

✅ 必须通过 scripts 脚本操作终端
✅ 必须监控任务状态
✅ 完成后必须清理 session
```

---

## 故障排除

### 命令没有执行

检查 session 是否创建成功：
```bash
./scripts/list-sessions.sh
```

### 看不到输出

使用 capture-screen.sh 查看：
```bash
./scripts/capture-screen.sh --session wo:bg-myproj:build.0 --lines 100
```

### Session 卡住

强制关闭并重新启动：
```bash
./scripts/close-session.sh bg:myproj:build.0
./scripts/run-background.sh build "npm run build"
```

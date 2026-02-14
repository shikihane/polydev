# Feature 1: `--peek N` 自动截屏

## 概览

4 个脚本执行完后，可选等 N 秒自动 capture 屏幕输出，省去手动 `sleep + capture-screen.sh`。

## 语义

- `--peek 0`：立即截屏
- `--peek 5`：等 5 秒后截屏
- 不传 `--peek`：不截屏（行为不变）

## 验证级别: L1 (compile)

脚本修改，无构建依赖，手动验证参数解析即可。

---

## Step 1: 在 terminal-backend.sh 末尾新增 tb_peek 函数

在 `tb_get_socket` 函数之后，文件末尾添加：

```bash
# tb_peek - 等待后截屏
# 用法: tb_peek <pane_id> <delay_seconds> [lines]
tb_peek() {
  local pane_id="$1"
  local delay="$2"
  local lines="${3:-50}"
  if [ "$delay" -gt 0 ] 2>/dev/null; then
    sleep "$delay"
  fi
  echo "---PEEK---"
  "$SCRIPT_DIR/capture-screen.sh" --pane-id "$pane_id" --lines "$lines"
}
```

---

## Step 2: 修改 send-to-session.sh

### 2a: 新增变量声明

在 `EXECUTE="true"` 之后添加：
```bash
PEEK_DELAY=""
```

### 2b: 参数解析 case 中新增

```bash
--peek)
  PEEK_DELAY="$2"
  shift 2
  ;;
```

### 2c: 脚本末尾成功路径后追加

在 `echo "[I] event=command_sent,..."` 之后（fi 之后）添加：
```bash
if [ -n "$PEEK_DELAY" ]; then
  tb_peek "$PANE_ID" "$PEEK_DELAY"
fi
```

---

## Step 3: 修改 wo-send-command.sh

同 Step 2 模式：
- 新增 `PEEK_DELAY=""` 变量
- case 中新增 `--peek)` 分支
- 末尾 fi 后追加 peek 调用（PANE_ID 已从 task.toon 提取）

---

## Step 4: 修改 run-background.sh

同 Step 2 模式：
- 新增 `PEEK_DELAY=""` 变量
- case 中新增 `--peek)` 分支（与 `--cwd`/`--workspace`/`--verbose` 同级）
- 在 `echo "$pane_id"` 之后追加 peek 调用

---

## Step 5: 修改 spawn-agent.sh

同 Step 2 模式但顺序特殊：
- 新增 `PEEK_DELAY=""` 变量
- case 中新增 `--peek)` 分支
- **注意**: `echo "$pane_id"` 必须在 peek 之前，保持返回值位置不变

```bash
echo "$pane_id"

if [ -n "$PEEK_DELAY" ]; then
  tb_peek "$pane_id" "$PEEK_DELAY"
fi
```

---

## Step 6: 更新文档

更新以下文件中的脚本参数表：

1. **`CLAUDE.md`** — Script Usage by Scenario 表格，每个涉及脚本的 Parameters 列追加 `[--peek N]`
2. **`skills/using-polydev/SKILL.md`** — Script Quick Reference 表格同步
3. **`skills/terminal-task-runner/SKILL.md`** — Scenario A/B/C 示例中补充 `--peek` 用法
4. **`skills/polydev/SKILL.md`** — 脚本参数表同步

每处更新：
- 参数列追加 `[--peek N]`
- 新增说明段落：

```
### --peek: 执行后自动截屏

所有返回 pane_id 的脚本均支持 `--peek N` 选项:
- `--peek 0`: 立即截屏
- `--peek 5`: 等 5 秒后截屏
- 不传: 不截屏

示例:
  "$POLYDEV_SCRIPTS/send-to-session.sh" 5 "docker ps" --peek 3
  "$POLYDEV_SCRIPTS/run-background.sh" build "npm test" --peek 10
```

---

## 完成标志

- [ ] `terminal-backend.sh` 新增 `tb_peek` 函数
- [ ] `send-to-session.sh` 支持 `--peek N`
- [ ] `wo-send-command.sh` 支持 `--peek N`
- [ ] `run-background.sh` 支持 `--peek N`
- [ ] `spawn-agent.sh` 支持 `--peek N`
- [ ] 4 个文档文件已更新

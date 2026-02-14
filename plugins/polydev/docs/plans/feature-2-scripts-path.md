# Feature 2: `POLYDEV_SCRIPTS` 路径简化

## 概览

用户不再需要手写完整路径。每次 session 启动自动写入一个短路径文件，后续一行搞定。

## 验证级别: L1 (compile)

Hook 修改 + 文档更新，手动验证文件写入即可。

---

## Step 1: 修改 hooks/on-session-start.sh

在现有逻辑之前（`PROJECT_DIR` 赋值之前，`to_unix_path` 函数定义之后），新增：

```bash
# 写入 scripts 路径到固定位置，供后续快速引用
PLUGIN_ROOT="$(to_unix_path "$CLAUDE_PLUGIN_ROOT")"
POLYDEV_HOME="$HOME/.polydev"
mkdir -p "$POLYDEV_HOME"
echo "${PLUGIN_ROOT}/scripts" > "$POLYDEV_HOME/scripts-path"
```

这段逻辑无条件执行（不依赖 task.toon 是否存在）。放在 `to_unix_path` 函数定义之后、`PROJECT_DIR` 赋值之前。

---

## Step 2: 更新 CLAUDE.md

### 2a: Script Path 段落

旧写法（找到并替换）：
```
POLYDEV_SCRIPTS="/path/to/polydev/plugins/polydev/scripts"
```

新写法：
```bash
# 自动由 SessionStart hook 写入，无需手动设置路径
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
```

### 2b: 保留 fallback 说明

在 Script Path 段落末尾新增：
```
> 如果 `~/.polydev/scripts-path` 不存在，说明 hook 未执行。手动设置:
> `POLYDEV_SCRIPTS="$CLAUDE_PLUGIN_ROOT/scripts"`
```

---

## Step 3: 更新 skills/using-polydev/SKILL.md

同 Step 2 模式，替换 Script Path 段落中的路径设置方式。

---

## Step 4: 更新 skills/terminal-task-runner/SKILL.md

同 Step 2 模式，替换 Script Path 段落和所有 Workflow 示例中的路径设置。

---

## Step 5: 更新 skills/polydev/SKILL.md

同 Step 2 模式，替换 Script Path 段落中的路径设置方式。

---

## 完成标志

- [ ] `hooks/on-session-start.sh` 写入 `~/.polydev/scripts-path`
- [ ] `CLAUDE.md` 路径指引已更新 + fallback
- [ ] `skills/using-polydev/SKILL.md` 路径指引已更新
- [ ] `skills/terminal-task-runner/SKILL.md` 路径指引已更新
- [ ] `skills/polydev/SKILL.md` 路径指引已更新

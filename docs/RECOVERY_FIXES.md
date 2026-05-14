# 任务恢复缺陷修复报告

**修复日期**: 2025-12-24
**问题严重程度**: 🔴 严重
**状态**: ✅ 已修复

---

## 问题回顾

### 时间线

1. **初始创建** - spawn-session.sh 创建了 task.toon，但 sed 替换 session_id 可能失败
2. **手动修复** - 用户手动修复了 session_id
3. **系统崩溃** - 会话丢失
4. **致命错误** - 在错误目录执行 `rm -rf`，删除了 memory worktree 的 task.toon
5. **无法恢复** - 缺少恢复机制

### 根本原因

1. ❌ **sed 替换不安全** - 使用 `/` 作为分隔符处理包含 `:` 的 session_id
2. ❌ **缺少目录确认** - 危险命令前没有检查当前目录
3. ❌ **task.toon 太脆弱** - 没有备份、没有版本控制
4. ❌ **缺少会话恢复机制** - 系统崩溃后无法恢复
5. ❌ **错误提示不清晰** - 用户不知道如何正确操作

---

## 修复内容

### 1. 修复 session_id 替换问题 ✅

**文件**: `scripts/spawn-session.sh:79`

**问题**:
```bash
# 旧代码 - 使用 / 分隔符，可能失败
sed_inplace "s/PENDING_PANE_ID/$session_id/" "$WORKTREE_PATH/task.toon"
```

**修复**:
```bash
# 新代码 - 使用 | 分隔符，安全处理 : 和 .
sed_inplace "s|PENDING_PANE_ID|$session_id|" "$WORKTREE_PATH/task.toon"
```

**原理**: session_id 格式为 `wo:workspace:branch.0`，包含 `:` 和 `.`，使用 `|` 作为 sed 分隔符避免冲突。

---

### 2. 实现 task.toon 自动备份机制 ✅

**文件**: `scripts/spawn-session.sh:25-37`

**新增功能**:
```bash
backup_task_toon() {
  local task_file="$1"
  local backup_dir="$(dirname "$task_file")/.task_backups"

  [ ! -f "$task_file" ] && return 0

  mkdir -p "$backup_dir"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$task_file" "$backup_dir/task.toon.${timestamp}.bak"

  # Keep only last 10 backups
  (cd "$backup_dir" && ls -t task.toon.*.bak 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null) || true
}
```

**特性**:
- 每次修改 task.toon 前自动备份
- 保留最近 10 个备份
- 备份存储在 `.task_backups/` 目录
- 文件名包含时间戳：`task.toon.20251224_143022.bak`

---

### 3. 创建会话恢复脚本 ✅

**新文件**: `scripts/restore-session.sh`

**功能**:
1. ✅ 检测 task.toon 是否存在
2. ✅ 从备份恢复 task.toon（如果缺失或损坏）
3. ✅ 检查会话是否存活
4. ✅ 重新创建终端会话
5. ✅ 更新 session_id
6. ✅ 可选：自动启动 Claude

**使用方法**:
```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/restore-session.sh" .worktrees/feature-auth
```

**交互流程**:
```
🔧 Worktree Session Recovery
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Worktree: /path/to/.worktrees/feature-auth

❌ task.toon not found!

📦 Found backup: task.toon.20251224_143022.bak
Restore from backup? [y/N] y
✅ Restored task.toon from backup

📋 Reading task.toon metadata...
  Branch: feature-auth
  Old Session ID: wo:myproject:feature-auth.0
  Status: 💀 DEAD

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Recovery options:
  [1] Create new session and restart Claude
  [2] Just create session (no Claude start)
  [3] Cancel
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Choose [1-3]: 1

🔨 Creating new terminal session...
✅ Created: wo:myproject:feature-auth.1

📝 Updating task.toon...
✅ Updated session_id

🤖 Starting Claude...
✅ Claude started

🎉 Recovery complete!
```

---

### 4. 创建安全删除工具 ✅

**新文件**: `scripts/cleanup-worktree.sh`

**安全机制**:
1. ✅ 显示当前目录和目标目录
2. ✅ 警告用户如果当前在目标目录中
3. ✅ 检查是否为 git worktree
4. ✅ 列出将要删除的文件和大小
5. ✅ 自动备份 task.toon
6. ✅ 要求输入目录名确认（防止误删）
7. ✅ 保留备份目录

**使用方法**:
```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/cleanup-worktree.sh" .worktrees/feature-auth
```

**交互流程**:
```
🧹 Safe Worktree Cleanup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  SAFETY CHECK

Current directory: /home/user/myproject
Target directory:  /home/user/myproject/.worktrees/feature-auth

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Files/directories that will be deleted:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  📄 task.toon (2.3K)
  📄 PLAN.md (4.5K)
  📁 .claude/ (12K)
  📁 src/ (156K)
  📁 tests/ (45K)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 Backing up task.toon...
   ✅ Saved to: .worktrees/feature-auth/.task_backups/task.toon.20251224_143500.bak

⚠️  FINAL CONFIRMATION

This will permanently delete all files in:
  /home/user/myproject/.worktrees/feature-auth

Type the worktree name to confirm deletion: feature-auth
> feature-auth

🗑️  Deleting files...
✅ Cleanup complete!

Backups preserved at: .worktrees/feature-auth/.task_backups

To remove the worktree from git:
  git worktree remove ".worktrees/feature-auth"
```

---

### 5. 添加 .gitignore 模板 ✅

**新文件**: `templates/worktree.gitignore`

**内容**:
```gitignore
# Worktree Orchestrator - Git Ignore Template

# Worktree directories
.worktrees/

# Task state and backups (IMPORTANT: Keep task.toon tracked!)
.task_backups/
*.tmp.*

# Temporary files
*.swp
*.swo
*~
.DS_Store

# Terminal backend state
/tmp/polydev-map.json
```

**注意**:
- ✅ task.toon 应该被 git 跟踪（不在 .gitignore 中）
- ✅ 备份目录被忽略（避免污染仓库）
- ✅ 临时文件被忽略

---

### 6. 改进错误处理和用户提示 ✅

**文件**: `scripts/spawn-session.sh`

**改进点**:

1. **更清晰的错误消息**:
```bash
# 旧版本
echo "Usage: spawn-session.sh ..."
exit 1

# 新版本
echo "❌ Error: Missing required arguments"
echo ""
echo "Usage: spawn-session.sh <workspace> <branch_name> <worktree_path> <plan_file> [verify_level]"
echo ""
echo "Arguments:"
echo "  workspace       - Name of the workspace (e.g., 'myproject-parallel')"
echo "  branch_name     - Git branch name for the worktree"
# ... 详细说明
echo ""
echo "Example:"
echo "  ./spawn-session.sh myproject-parallel feature-auth .worktrees/auth ./PLAN.md L3 L2"
exit 1
```

2. **验证输入**:
```bash
# 检查 plan 文件是否存在
if [ ! -f "$PLAN_FILE" ]; then
  echo "❌ Error: Plan file not found: $PLAN_FILE"
  exit 1
fi

# 检查 worktree 是否已存在
if [ -d "$WORKTREE_PATH" ]; then
  echo "⚠️  Warning: Directory already exists: $WORKTREE_PATH"
  echo "   Use restore-session.sh to recover, or cleanup-worktree.sh to remove it."
  exit 1
fi
```

3. **友好的进度输出**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Creating Worktree Session
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workspace:     myproject-parallel
Branch:        feature-auth
Worktree:      .worktrees/auth
Verification:  L3 (fallback: L2)
Backend:       wezterm

📁 Creating git worktree...
   ✅ Worktree created

⚙️  Setting up Claude configuration...
   ✅ Claude config ready

📋 Copying plan file...
   ✅ PLAN.md copied

📝 Creating task.toon...
   ✅ task.toon initialized

🖥️  Creating terminal session...
   ✅ Session created: wo:myproject-parallel:feature-auth.0

🤖 Starting Claude agent...
   ✅ Claude launched

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 Session spawned successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Session ID:  wo:myproject-parallel:feature-auth.0
Worktree:    .worktrees/auth
Branch:      feature-auth
Backend:     wezterm

💡 Next steps:
   - Monitor with: "/c/Users/<user>/.claude/skills/polydev/scripts/poll.sh" .worktrees 10
   - Focus with:   "/c/Users/<user>/.claude/skills/polydev/scripts/focus-session.sh" .worktrees/auth
   - Check status: cat .worktrees/auth/task.toon
```

4. **详细的 git 错误提示**:
```bash
if ! git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null; then
  echo "❌ Failed to create worktree"
  echo "   This might mean the branch already exists or the path is invalid."
  echo "   Run 'git worktree list' to see existing worktrees."
  exit 1
fi
```

---

## 新增文件列表

1. ✅ `scripts/restore-session.sh` - 会话恢复脚本
2. ✅ `scripts/cleanup-worktree.sh` - 安全删除工具
3. ✅ `templates/worktree.gitignore` - Git 忽略模板
4. ✅ `docs/RECOVERY_FIXES.md` - 本文档

---

## 修改文件列表

1. ✅ `scripts/spawn-session.sh`
   - 修复 sed 分隔符问题
   - 添加自动备份功能
   - 改进错误处理和用户提示
   - 添加输入验证
   - 改进进度显示

---

## 使用指南

### 正常流程

1. **创建新会话**:
   ```bash
   "/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" myproject-parallel feature-auth .worktrees/auth ./PLAN.md
   ```

2. **监控会话**:
   ```bash
   "/c/Users/<user>/.claude/skills/polydev/scripts/poll.sh" .worktrees 10
   ```

3. **聚焦会话**:
   ```bash
   "/c/Users/<user>/.claude/skills/polydev/scripts/focus-session.sh" .worktrees/auth
   ```

### 故障恢复流程

1. **会话崩溃后恢复**:
   ```bash
   "/c/Users/<user>/.claude/skills/polydev/scripts/restore-session.sh" .worktrees/auth
   ```

2. **task.toon 被误删**:
   ```bash
   # 恢复脚本会自动从 .task_backups/ 恢复
   "/c/Users/<user>/.claude/skills/polydev/scripts/restore-session.sh" .worktrees/auth
   ```

3. **手动恢复备份**:
   ```bash
   # 查看备份
   ls -lt .worktrees/auth/.task_backups/

   # 恢复特定备份
   cp .worktrees/auth/.task_backups/task.toon.20251224_143022.bak \
      .worktrees/auth/task.toon
   ```

### 清理流程

1. **安全清理 worktree**:
   ```bash
   "/c/Users/<user>/.claude/skills/polydev/scripts/cleanup-worktree.sh" .worktrees/auth
   ```

2. **从 git 移除 worktree**:
   ```bash
   git worktree remove .worktrees/auth
   ```

---

## 测试建议

### 测试用例 1: sed 替换测试

```bash
# 创建测试 worktree
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" test-workspace test-branch .worktrees/test ./PLAN.md

# 检查 task.toon 中的 session_id 是否正确
grep "wo:test-workspace:test-branch" .worktrees/test/task.toon
# 应该看到正确的 session_id，不是 PENDING_PANE_ID
```

### 测试用例 2: 备份测试

```bash
# 创建会话
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" test-workspace test-branch .worktrees/test ./PLAN.md

# 检查备份是否创建
ls .worktrees/test/.task_backups/
# 应该看到 task.toon.*.bak 文件

# 修改 task.toon 多次
echo "test" >> .worktrees/test/task.toon
# ... 重复几次

# 检查备份数量（应该不超过 10 个）
ls .worktrees/test/.task_backups/ | wc -l
```

### 测试用例 3: 恢复测试

```bash
# 创建会话
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" test-workspace test-branch .worktrees/test ./PLAN.md

# 模拟删除 task.toon
rm .worktrees/test/task.toon

# 尝试恢复
"/c/Users/<user>/.claude/skills/polydev/scripts/restore-session.sh" .worktrees/test
# 应该提示从备份恢复

# 验证恢复成功
cat .worktrees/test/task.toon
```

### 测试用例 4: 安全删除测试

```bash
# 创建测试 worktree
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" test-workspace test-branch .worktrees/test ./PLAN.md

# 尝试删除
"/c/Users/<user>/.claude/skills/polydev/scripts/cleanup-worktree.sh" .worktrees/test
# 应该显示安全确认界面

# 验证备份被保留
ls .worktrees/test/.task_backups/
```

---

## 防止未来问题的建议

### 对用户

1. ✅ **始终使用提供的脚本**，不要手动删除文件
2. ✅ **执行危险命令前检查 `pwd`**
3. ✅ **定期检查 task.toon 状态**：`cat .worktrees/*/task.toon`
4. ✅ **使用 poll.sh 监控会话**，及时发现问题
5. ✅ **保留 .task_backups/** 目录，不要删除

### 对开发者

1. ✅ **所有涉及文件路径的操作都要使用绝对路径**
2. ✅ **关键文件修改前自动备份**
3. ✅ **危险操作前多次确认**
4. ✅ **提供详细的错误信息和恢复指导**
5. ✅ **编写全面的测试用例**

---

## 总结

本次修复解决了 5 个关键问题：

1. ✅ **sed 替换失败** → 使用安全的分隔符
2. ✅ **缺少备份** → 自动备份 task.toon
3. ✅ **无法恢复** → restore-session.sh 脚本
4. ✅ **误删风险** → cleanup-worktree.sh 安全删除
5. ✅ **错误提示不清** → 改进所有脚本的输出

现在系统具有：
- 🛡️ **自动保护**: 修改前自动备份
- 🔄 **故障恢复**: 完整的会话恢复机制
- 🚨 **安全确认**: 多重确认防止误删
- 📋 **清晰指导**: 友好的错误消息和帮助信息

**建议**: 将 `.task_backups/` 添加到 .gitignore，但考虑定期将关键备份提交到 git（手动选择）。

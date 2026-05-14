# Brainstorm: 工作记忆 / 规则反思设计

**日期**: 2025-01-05
**状态**: 方案确定

---

## 最终方案总结

经过研究和讨论，放弃复杂的"情景记忆"系统，采用**轻量级规则反思**：

### 核心设计

1. **不使用 error-log**：避免增加子 Agent 的选择熵
2. **轻量触发**：在 SKILL 中明确触发条件，遇到特定问题时才反思
3. **项目级规则**：生成的规则存在项目 `.claude/rules/`，不扩散全局
4. **审核机制**：规则先进 proposed-rules/，审核后采纳

### 触发条件（全部满足）

1. 遇到 **环境/兼容性/参数用法** 问题
2. 问题 **会在新 Agent 执行时重复出现**
3. **已解决** 并有明确方案

### 文件结构

```
项目/
├── .claude/rules/
│   └── auto-*.md              # 采纳的规则
└── .agent-memory/
    └── proposed-rules/        # 待审核草稿
```

### 工作流

```
子 Agent 遇到兼容性问题 → 解决 → 判断是否重复性问题
    ↓ 是
propose-rule.sh → proposed-rules/*.md
    ↓
主 Agent/用户 审核 → adopt-rule.sh → .claude/rules/auto-*.md
```

---

## 以下为原始探索过程（保留参考）

---

## 1. 问题陈述

### 当前痛点

主 Agent 依赖静态文件（task.toon、报告文件）获取子 Agent 的状态，但这种方式有根本性缺陷：

```
子 Agent 工作过程中:
├── 10:00 遇到一个小问题，绕过了
├── 10:15 又遇到类似问题，感觉有点奇怪
├── 10:30 第三次遇到，开始怀疑是系统性问题
├── 10:45 确认这是一个严重 bug
└── 11:00 完成修复，写入 task.toon: "completed"

主 Agent 读取 task.toon:
└── 只看到 "completed"，完全不知道过程中的挣扎和发现
```

**问题**:
1. **时间序列丢失**: 静态文件只记录最终状态，不记录过程
2. **情景上下文丢失**: 问题发生的条件、环境、前后关联都丢失了
3. **知识无法迁移**: 一个子 Agent 踩过的坑，其他子 Agent 和主 Agent 无法学习
4. **调试困难**: 出问题时无法重建现场

### 典型场景

**场景 A: 渐进式发现 Bug**
```
子 Agent A 在 feature/auth 分支:
  - 发现登录偶尔失败
  - 重试后成功，以为是网络问题
  - 后来发现是竞态条件
  - 修复后完成任务

子 Agent B 在 feature/profile 分支:
  - 遇到同样的登录失败
  - 完全不知道 Agent A 已经发现并修复了
  - 浪费时间重复调查
```

**场景 B: 环境依赖问题**
```
子 Agent:
  - 在 Windows 上某操作失败
  - 尝试多种方法
  - 最终发现是路径分隔符问题
  - 修复后继续

主 Agent:
  - 不知道这个发现
  - 下次遇到类似问题，无法快速定位
```

**场景 C: 复杂决策过程**
```
子 Agent:
  - 面临 A/B 两种实现方案
  - 先尝试 A，遇到问题
  - 切换到 B，也遇到问题
  - 最终用 A+改进 方案
  - task.toon 只记录 "使用了方案 A"

未来问题:
  - 为什么选 A 不选 B？
  - 当时遇到什么问题？
  - 这个决策的约束条件是什么？
```

---

## 2. 什么是情景记忆？

### 认知科学定义

**情景记忆 (Episodic Memory)** 是人类长期记忆的一种，用于存储个人经历的事件，包括：
- **时间**: 什么时候发生的
- **地点**: 在什么环境/上下文中
- **内容**: 发生了什么
- **情感**: 感受如何（对 Agent 来说是"重要性/困难度"）

与之对比：
- **语义记忆**: 事实和概念（如"Python 用缩进表示块"）
- **程序记忆**: 如何做事（如"如何写 for 循环"）

### Agent 的情景记忆需要什么？

```
情景记忆条目:
├── 时间戳: 2025-01-05T10:30:00Z
├── Agent: feature/auth 分支的子 Agent
├── 阶段: 实现 JWT 验证
├── 事件: 发现 token 刷新竞态条件
├── 上下文:
│   ├── 触发条件: 并发请求 > 10
│   ├── 错误现象: 偶发 401
│   └── 相关文件: src/auth/refresh.ts
├── 过程:
│   ├── 最初判断: 网络问题
│   ├── 排查步骤: [...]
│   └── 最终定位: 锁机制缺失
├── 解决方案: 添加 mutex
├── 学到的教训: 刷新 token 必须加锁
└── 重要性: 高（影响所有认证流程）
```

---

## 3. 设计目标

1. **捕获时间序列**: 记录事件发生的顺序，而不只是最终状态
2. **保留情景上下文**: 记录问题发生的条件、环境、前后关联
3. **支持知识迁移**: 让其他 Agent 和主 Agent 能够查询和学习
4. **轻量级实现**: 不能给 Agent 增加太多负担
5. **可查询**: 能够根据关键词、时间、类型等维度查询

---

## 4. 设计方案

### 4.1 存储格式

**方案 A: 追加式日志文件**

```
.agent-memory/
├── episodes/
│   ├── 2025-01-05_feature-auth.jsonl    # 每个分支一个文件
│   └── 2025-01-05_feature-profile.jsonl
├── index.json                            # 索引（按关键词、类型）
└── lessons.md                            # 提炼的经验教训
```

每行是一个 JSON 事件：
```json
{"ts":"2025-01-05T10:30:00Z","type":"discovery","severity":"high","title":"Token刷新竞态条件","context":{"trigger":"并发>10","symptom":"偶发401"},"resolution":"添加mutex","lesson":"刷新token必须加锁","tags":["auth","concurrency","bug"]}
```

**优点**: 简单、追加写入、易于 grep
**缺点**: 索引需要额外维护

**方案 B: 结构化目录**

```
.agent-memory/
├── episodes/
│   └── 2025-01-05T10-30-00_token-race-condition/
│       ├── meta.json          # 元信息
│       ├── context.md         # 详细上下文
│       ├── timeline.md        # 时间线
│       └── artifacts/         # 相关文件快照
└── index/
    ├── by-tag.json
    ├── by-date.json
    └── by-severity.json
```

**优点**: 结构清晰、支持丰富内容
**缺点**: 复杂、文件多

**方案 C: 单文件 + TOON 格式**

```
.agent-memory/episodes.toon

episodes[]{ts,agent,type,severity,title,context,resolution,lesson,tags}:
  2025-01-05T10:30:00Z,feature/auth,discovery,high,Token刷新竞态条件,{并发>10|偶发401},添加mutex,刷新token必须加锁,[auth|concurrency|bug]
  2025-01-05T10:45:00Z,feature/auth,decision,medium,选择方案A,{尝试过B失败},A+改进,先验证再优化,[architecture|decision]
```

**优点**: 紧凑、一个文件、格式统一
**缺点**: 复杂上下文难以表达

### 4.2 推荐方案：混合式

```
.agent-memory/
├── stream.jsonl              # 主事件流（追加写入）
├── lessons-learned.md        # 提炼的经验教训（人类可读）
└── artifacts/                # 重要的上下文快照
    └── 2025-01-05_token-race/
        └── error-log.txt
```

**stream.jsonl** 格式：
```jsonl
{"ts":"...","agent":"feature/auth","type":"observe","content":"登录偶尔失败，重试后成功"}
{"ts":"...","agent":"feature/auth","type":"hypothesis","content":"可能是网络问题"}
{"ts":"...","agent":"feature/auth","type":"investigate","content":"添加日志，发现并发时失败率高"}
{"ts":"...","agent":"feature/auth","type":"discovery","content":"竞态条件！token刷新没加锁","severity":"high","tags":["auth","concurrency"]}
{"ts":"...","agent":"feature/auth","type":"resolve","content":"添加 mutex","files":["src/auth/refresh.ts"]}
{"ts":"...","agent":"feature/auth","type":"lesson","content":"刷新 token 必须加锁，任何共享状态的修改都要考虑并发"}
```

### 4.3 事件类型

| 类型 | 说明 | 示例 |
|------|------|------|
| `observe` | 观察到现象 | "登录偶尔失败" |
| `hypothesis` | 提出假设 | "可能是网络问题" |
| `investigate` | 调查过程 | "添加日志分析" |
| `discovery` | 发现问题/原因 | "竞态条件" |
| `decision` | 做出决策 | "选择方案 A" |
| `attempt` | 尝试解决 | "尝试添加重试" |
| `fail` | 尝试失败 | "重试无效" |
| `resolve` | 解决问题 | "添加 mutex" |
| `lesson` | 总结教训 | "共享状态要加锁" |
| `question` | 遗留问题 | "为什么只在高并发时出现？" |

### 4.4 严重程度

| 级别 | 说明 |
|------|------|
| `critical` | 阻塞性问题，必须立即处理 |
| `high` | 重要发现，影响多个功能 |
| `medium` | 普通问题，局部影响 |
| `low` | 小发现，备忘性质 |
| `info` | 纯信息记录 |

---

## 5. Agent 如何记录？

### 5.1 被动记录 vs 主动记录

**被动记录**: 通过 hook 自动捕获
- 优点: 不需要 Agent 主动操作
- 缺点: 只能捕获外部行为，无法捕获思考过程

**主动记录**: Agent 主动调用记录
- 优点: 能记录思考、假设、判断
- 缺点: 增加 Agent 负担

**推荐**: 结合使用
- 关键发现、决策、教训：主动记录
- 文件操作、命令执行：被动记录（可选）

### 5.2 记录时机

子 Agent 应该在以下时机记录：

1. **发现异常时**: "这个行为很奇怪..."
2. **形成假设时**: "我认为原因是..."
3. **验证假设时**: "经过测试，确认是..."
4. **做出决策时**: "选择方案 A 因为..."
5. **解决问题时**: "通过 X 解决了 Y"
6. **获得教训时**: "以后遇到类似情况应该..."

### 5.3 记录脚本

```bash
# 新增脚本: log-episode.sh
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" <type> "<content>" [--severity <level>] [--tags <tags>]

# 示例
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" observe "登录偶尔失败，重试后成功"
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" discovery "Token刷新存在竞态条件" --severity high --tags "auth,concurrency"
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" lesson "共享状态修改必须加锁"
```

### 5.4 子 Agent 的 Skill 更新

在 worktree-executor 和 agent-investigator 中添加记录指导：

```markdown
## 情景记忆

工作过程中，记录重要的发现和决策：

```bash
# 发现问题时
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" discovery "描述问题" --severity high --tags "相关标签"

# 做出决策时
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" decision "选择了什么，为什么"

# 解决问题后
"/c/Users/<user>/.claude/skills/polydev/scripts/log-episode.sh" lesson "学到了什么教训"
```

**什么时候记录？**
- 遇到意外行为时
- 做出重要决策时
- 发现值得分享的知识时
- 解决了困难问题时

**不需要记录什么？**
- 常规操作
- 琐碎细节
- 已经在 task.toon 中的状态
```

---

## 6. 主 Agent 如何使用？

### 6.1 查询记忆

```bash
# 新增脚本: query-episodes.sh

# 查看最近的发现
"/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --type discovery --limit 10

# 查看高严重度事件
"/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --severity high

# 按标签查询
"/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --tags auth,concurrency

# 查看某个分支的事件
"/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --agent feature/auth

# 查看经验教训
"/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --type lesson
```

### 6.2 在 Poll 循环中检查

```bash
while branches_remaining; do
  result=$("/c/Users/<user>/.claude/skills/polydev/scripts/poll.sh" .worktrees 10)

  # 检查是否有新的高严重度发现
  new_discoveries=$("/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --severity high --since "$last_check")
  if [ -n "$new_discoveries" ]; then
    echo "⚠️ 发现重要问题:"
    echo "$new_discoveries"
    # 可能需要通知其他分支或人类
  fi

  last_check=$(date -u +%Y-%m-%dT%H:%M:%SZ)
done
```

### 6.3 跨分支知识共享

当新的子 Agent 启动时，可以查询相关的历史经验：

```bash
# 在 spawn-session.sh 中添加
relevant_lessons=$("/c/Users/<user>/.claude/skills/polydev/scripts/query-episodes.sh" --type lesson --tags "$BRANCH_TAGS")
if [ -n "$relevant_lessons" ]; then
  # 将相关经验注入到子 Agent 的提示词中
  echo "## 相关历史经验" >> "$WORKTREE_PATH/PLAN.md"
  echo "$relevant_lessons" >> "$WORKTREE_PATH/PLAN.md"
fi
```

---

## 7. 经验提炼

### 7.1 自动生成 lessons-learned.md

定期（或在所有任务完成后）运行：

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/summarize-episodes.sh" > .agent-memory/lessons-learned.md
```

生成的文件：

```markdown
# 经验教训汇总

生成时间: 2025-01-05T12:00:00Z
来源: 5 个分支的工作记录

## 高优先级发现

### 1. Token 刷新竞态条件
- **发现者**: feature/auth 分支
- **时间**: 2025-01-05T10:30:00Z
- **问题**: 并发请求时 token 刷新可能失败
- **解决**: 添加 mutex
- **教训**: 任何共享状态的修改都要考虑并发

### 2. Windows 路径分隔符问题
- **发现者**: feature/cli 分支
- **时间**: 2025-01-05T11:00:00Z
- **问题**: path.join 在 Windows 上行为不一致
- **解决**: 统一使用 path.posix
- **教训**: 跨平台代码要用平台无关的 API

## 决策记录

### 选择 JWT 而非 Session
- **决策者**: feature/auth 分支
- **原因**: 无状态、易于水平扩展
- **权衡**: 牺牲了即时撤销能力

## 待解决问题

- [ ] 为什么高并发时才出现竞态？低并发也可能有问题吗？
- [ ] path.posix 在所有场景下都适用吗？
```

### 7.2 长期知识沉淀

将高价值的经验教训迁移到项目的正式文档：

```
.agent-memory/lessons-learned.md (临时，自动生成)
    ↓
docs/architecture-decisions.md (永久，人工审核后迁移)
CLAUDE.md (项目级 AI 指导)
```

---

## 8. 与现有系统的集成

### 8.1 目录结构

```
polydev/
├── scripts/
│   ├── log-episode.sh          # 新增: 记录事件
│   ├── query-episodes.sh       # 新增: 查询事件
│   ├── summarize-episodes.sh   # 新增: 生成摘要
│   └── ...
├── skills/
│   ├── polydev/
│   │   └── SKILL.md            # 更新: 添加记忆查询指导
│   ├── worktree-executor/
│   │   └── SKILL.md            # 更新: 添加记录指导
│   └── agent-investigator/
│       └── SKILL.md            # 更新: 添加记录指导
└── templates/
    └── episode-template.json   # 事件模板
```

### 8.2 与 task.toon 的关系

| 文件 | 用途 | 更新频率 | 内容 |
|------|------|---------|------|
| `task.toon` | 任务状态同步 | 状态变化时 | 当前状态、进度 |
| `.agent-memory/stream.jsonl` | 情景记忆 | 重要事件时 | 过程、发现、教训 |

**不是替代关系，是补充关系**：
- task.toon: "我现在在做什么"（状态）
- stream.jsonl: "我经历了什么"（历程）

---

## 9. 实施阶段

### Phase 1: 基础设施

- [ ] 实现 `log-episode.sh`
- [ ] 实现 `query-episodes.sh`
- [ ] 定义事件格式和类型

### Phase 2: Agent 集成

- [ ] 更新 worktree-executor SKILL.md
- [ ] 更新 agent-investigator SKILL.md
- [ ] 在子 Agent 提示词中添加记录指导

### Phase 3: 主 Agent 使用

- [ ] 更新 polydev SKILL.md
- [ ] 在 poll 循环中添加记忆检查
- [ ] 实现知识注入（spawn 时）

### Phase 4: 经验提炼

- [ ] 实现 `summarize-episodes.sh`
- [ ] 自动生成 lessons-learned.md
- [ ] 建立长期知识迁移流程

---

## 10. 待讨论问题

1. **存储位置**: `.agent-memory/` 放在项目根目录还是 `.worktrees/` 中？
   - 项目根目录：所有分支共享
   - .worktrees：每个分支独立，需要合并

2. **记录粒度**: 记录多少才合适？
   - 太少：错过重要信息
   - 太多：噪音太大

3. **隐私/敏感信息**: 如何处理可能包含敏感信息的记录？
   - 自动过滤？
   - 标记为敏感？

4. **跨项目共享**: 这些经验能否跨项目共享？
   - 项目级 vs 全局级
   - 脱敏后共享？

---

## 11. 总结

情景记忆解决的核心问题是：**将子 Agent 的工作过程（而不只是结果）传递给主 Agent 和其他 Agent**。

关键设计原则：
1. **轻量记录**: 只记录重要事件，不是流水账
2. **结构化存储**: 便于查询和分析
3. **主动 + 被动**: 关键洞察靠主动记录
4. **知识迁移**: 经验能够被复用

这套机制让整个 Agent 系统具备了"组织记忆"的能力。

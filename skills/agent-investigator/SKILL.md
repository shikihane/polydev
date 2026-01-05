---
name: agent-investigator
description: Use when you are spawned as an investigation agent. Generates a structured report file and outputs completion marker.
---

# Agent Investigator

执行调查任务并生成结构化报告的技能。

**注意**: 此 Skill 由子 Agent 使用，当你被 `spawn-agent.sh` 启动时自动激活。

---

## 核心职责

1. **理解调查任务** - 从启动提示词中获取
2. **执行调查** - 搜索、阅读、分析相关代码/文档
3. **生成报告** - 写入指定文件
4. **输出完成标记** - 让主 Agent 知道你完成了

---

## 完成标记格式（必须遵守）

任务完成时，在终端输出这个 **精确格式**：

```
[AGENT_DONE]
report: <报告文件的完整路径>
timestamp: <ISO时间戳，如 2025-01-05T10:30:00Z>
summary: <20字以内的中文摘要>
```

**示例：**
```
[AGENT_DONE]
report: ./.agent-reports/auth-analysis.md
timestamp: 2025-01-05T10:30:00Z
summary: JWT认证, 3个中间件, 2个安全隐患
```

主 Agent 会通过 `grep "\[AGENT_DONE\]"` 检测你的完成状态。

---

## 报告模板

```markdown
# 调查报告: <主题>

生成时间: <ISO timestamp>

## 摘要

<3-5句话概括核心发现，这是主 Agent 最先看到的内容>

## 发现

### 1. <发现点标题>

<详细说明>

**关键代码：**
```<language>
// path/to/file.ts:123
<相关代码片段>
```

### 2. <发现点标题>

<详细说明>

## 关键文件

| 文件 | 行号 | 说明 |
|------|------|------|
| `src/auth/jwt.ts` | 45-67 | JWT 验证逻辑 |
| `src/middleware/auth.ts` | 12-34 | 认证中间件 |

## 建议

1. **<建议标题>** - <具体行动>
2. **<建议标题>** - <具体行动>

## 附录（可选）

<额外的技术细节、代码片段、参考资料>
```

---

## 执行流程

```
1. 读取任务描述
     ↓
2. 规划调查步骤
     ↓
3. 执行调查（搜索、阅读、分析）
   - 使用 Glob 找文件
   - 使用 Grep 搜索模式
   - 使用 Read 阅读代码
     ↓
4. 整理发现，撰写报告
     ↓
5. 将报告写入指定文件
     ↓
6. 输出 [AGENT_DONE] 标记
     ↓
7. 完成（主 Agent 会读取报告）
```

---

## 禁止事项

```
❌ 不要等待用户输入（你是后台运行的）
❌ 不要在终端输出大量过程信息（浪费主 Agent 的 token）
❌ 不要忘记输出 [AGENT_DONE] 标记
❌ 不要修改代码（除非任务明确要求）

✅ 过程信息记在心里或写日志
✅ 最终结果写入报告文件
✅ 终端只输出关键进度和完成标记
✅ 报告要结构化、可快速浏览
```

---

## 终端输出示例

理想的终端输出应该非常简洁：

```
🔍 开始调查: 认证机制分析

📂 搜索认证相关文件...
   找到 12 个相关文件

📖 分析关键代码...
   - src/auth/jwt.ts
   - src/middleware/auth.ts
   - src/routes/login.ts

📝 撰写报告...

✅ 报告已生成: ./.agent-reports/auth-analysis.md

[AGENT_DONE]
report: ./.agent-reports/auth-analysis.md
timestamp: 2025-01-05T10:30:00Z
summary: JWT认证, 3个中间件, 2个安全隐患
```

---

## 与主 Agent 的通信

你和主 Agent 之间没有直接通信通道。唯一的通信方式是：

1. **报告文件** - 主 Agent 读取你生成的报告
2. **[AGENT_DONE] 标记** - 主 Agent 通过终端输出检测你的完成状态
3. **summary 字段** - 主 Agent 快速判断是否需要详读报告

保持报告精简、结构化，让主 Agent 能快速获取关键信息。

---

## 规则反思（完成前检查）

**触发条件**（全部满足才触发）：
1. 遇到了 **环境/兼容性/参数用法** 问题
2. 问题 **会在新 Agent 执行时重复出现**
3. 你 **已解决** 并有明确方案

**触发动作**：写文件到 `.agent-memory/proposed-rules/<问题简述>.md`

**格式**：
```markdown
# <问题简述>

## 问题
<描述问题现象和触发条件>

## 解决方案
<具体的解决方法>

## 示例
```bash
# 错误做法
...

# 正确做法
...
```
```

**不触发的情况**：
- 业务逻辑问题
- 一次性问题
- 不确定是否通用

# Agent 情景记忆研究报告

**研究时间**: 2026-01-05
**研究范围**: AI Agent 情景记忆设计、多 Agent 知识共享、主流框架实现

## 摘要

情景记忆（Episodic Memory）在 AI Agent 系统中用于捕获"经验"而非"事实"——即记录 Agent 如何解决问题的过程，而不仅仅是结果。最新研究和实践表明：**简单的 JSONL 事件流 + 分层摘要**是最实用的方案，远优于复杂的状态机。主流框架（LangChain、LlamaIndex、CrewAI）均采用"分层记忆"架构：短期工作记忆 + 长期记忆（分为 Episodic/Semantic/Procedural 三种）。关键洞察是：**不要过度设计事件类型**，应该用 OpenTelemetry 标准的 Trace/Span/Event 模型，并通过周期性摘要来压缩长期记忆。你当前的 observe→hypothesis→investigate 方案过于细碎，应简化为标准的追踪事件 + 自动摘要提取。

---

## 1. 主流框架的做法

### 1.1 LangChain + LangMem

**核心架构**: [三层记忆模型](https://blog.langchain.com/memory-for-agents/)

- **Episodic Memory**: 存储成功交互的完整上下文（情境、思考过程、成功原因），以 few-shot 示例形式指导未来行为
- **Semantic Memory**: 存储知识和事实（通过向量数据库或知识图谱）
- **Procedural Memory**: LLM 权重 + Agent 代码（决定 Agent 如何工作）

**实现方式**:
- [LangMem SDK](https://blog.langchain.com/langmem-sdk-launch/) 专门用于长期记忆管理
- Episodic Memory 被实现为**从长交互中提炼的 few-shot 示例**（[提取方法](https://langchain-ai.github.io/langmem/guides/extract_episodic_memories/)）
- [MongoDB 集成](https://www.mongodb.com/company/blog/product-release-announcements/powering-long-term-memory-for-agents-langgraph)允许跨会话的长期记忆存储

**关键特性**:
- 短期记忆（Thread-scoped）：通过 LangGraph 管理对话历史
- 长期记忆（User/App-level）：跨会话共享的用户偏好和经验
- **DeepLearning.AI 课程**教授如何在 triage 步骤中使用 few-shot 示例来更新用户偏好

### 1.2 LlamaIndex

**核心架构**: [可组合的记忆块](https://docs.llamaindex.ai/en/stable/module_guides/deploying/agents/memory/)

**短期记忆（Working Memory）**:
- 默认实现为 FIFO 队列，存储最近 X 条消息（受 token 限制）
- `token_limit`（默认 30000）+ `chat_history_token_ratio`（默认 0.7）
- 当超出限制时，旧消息被刷入长期记忆

**长期记忆块**:
1. **StaticMemoryBlock**: 静态信息（如系统指令）
2. **FactExtractionMemoryBlock**: 从对话中提取事实（使用 LLM）
3. **VectorMemoryBlock**: 向量数据库存储消息，通过相似度检索

**可组合架构**: [SimpleComposableMemory](https://docs.llamaindex.ai/en/stable/examples/agent/memory/composable_memory/)
- `primary_memory`: 主聊天缓冲区
- `secondary_memory_sources`: 额外记忆源（仅注入到系统提示）

**存储后端**: 支持 SQLite（默认）、远程数据库，可自定义表名

### 1.3 CrewAI

**核心架构**: [角色化 + RAG 短期记忆](https://docs.crewai.com/en/concepts/agents)

- **Short-Term Memory with RAG**: 为 Agent 提供上下文相关信息
- **跨任务上下文**: 启用记忆后，Agent 可维护多任务间的上下文
- **局限性**: 原生记忆架构相对静态，不跨会话演化
- **集成 Mem0**: [CrewAI + Mem0](https://mem0.ai/blog/crewai-guide-multi-agent-ai-teams) 可实现持久化上下文，减少 90% token 成本

**设计模式**:
1. Coordinator-Worker: 主规划器分解任务给专门 Agent
2. Collaborative Peer Group: Agent 迭代共享和改进输出
3. Hybrid Planner-Executor: 规划、执行、反馈循环

### 1.4 AutoGPT

**核心架构**: [自主循环 + 向量数据库记忆](https://dev.to/dataformathub/ai-agents-2025-why-autogpt-and-crewai-still-struggle-with-autonomy-48l0)

- LLM 推理 + 记忆模块（通常是向量数据库）+ 工具访问
- 自我反思（self-reflection）循环：Agent 批评自己的输出并调整计划
- **问题**: 易陷入反馈循环，脆弱的长期记忆，高 token 消耗，错误级联

**建议**: 使用 AutoGPT 概念但在 LangGraph 或 CrewAI 中实现，加入防护机制

---

## 2. 学术研究和关键论文

### 2.1 CoALA: 认知架构标准

**论文**: [Cognitive Architectures for Language Agents](https://arxiv.org/abs/2309.02427) (TMLR 2024)
**作者**: Theodore Sumers, Shunyu Yao, Karthik Narasimhan, Thomas L. Griffiths

**核心贡献**: 定义了 Agent 的标准认知架构

**记忆模块**:

1. **Working Memory（工作记忆）**
   - 当前决策周期的活跃信息
   - 包括：感知输入、活跃知识（推理生成或检索）、上一周期的目标

2. **Episodic Memory（情景记忆）**
   - 过去经验的记录，包括完整交互轨迹和事件序列
   - 使 Agent 能从历史遭遇中学习并适应行为

3. **Semantic Memory（语义记忆）**
   - 关于世界的通用知识
   - 通过外部数据库、知识图谱或检索系统实现

4. **Procedural Memory（过程记忆）**
   - Agent 的操作知识：LLM 参数 + 显式代码
   - 代表 Agent 执行任务的"know-how"

**动作空间**:
- 内部认知动作：记忆检索、推理、学习
- 外部环境交互：物理、对话、数字

**决策循环**: 规划阶段（提出候选动作、评估效用）→ 执行阶段

**高级能力**: 反思情景记忆生成语义推断，修改程序代码生成过程知识

### 2.2 多 Agent 系统中的记忆

**论文**: [Memory in LLM-based Multi-agent Systems](https://www.techrxiv.org/users/1007269/articles/1367390) (2024)

**记忆拓扑类型**:

1. **本地记忆（Local Memory）**
   - 早期框架（CAMEL、AutoGen、Chain-of-agents）采用
   - 避免干扰但可能冗余和不一致

2. **共享记忆（Shared Memory）**
   - Memory Sharing 框架提供共享记忆池
   - 实现"团队思维"，知识立即全局可用
   - 问题：无结构共享导致噪音，缺乏访问控制

3. **双层架构（Two-Tier）**
   - 每个 Agent 维护私有记忆 + 共享记忆
   - 私有记忆隔离敏感信息，共享记忆启用知识传递

**记忆托管方式**:
- **Orchestrator-level**: 中央协调器作为记忆中心（黑板模式）
- **External hosting**: 所有 Agent 查询共享数据库/知识图谱

**关键系统**:
- **MemStore**: 发布-订阅机制，多 Agent 开放记忆共享
- **Intrinsic Memory Agents**: 结构化、面向目标的 Agent 特定记忆
- **Memory as a Service (MaaS)**: 多个 Agent 的 prompt-answer 对存入共享记忆池

**论文**: [Collaborative Memory](https://arxiv.org/html/2505.18279v1) (2025)
- 研究多用户、多 Agent 环境中的协作记忆共享
- 动态访问控制，平衡共享与隐私

### 2.3 记忆压缩和摘要

**关键发现**: [Memory in the Age of AI Agents](https://arxiv.org/abs/2512.13564) (2024)

**压缩技术**:
- **Summarization**: 使用独立 summarizer LLM 压缩旧交互
- **Observation Masking**: 研究发现比 LLM 摘要更高效可靠
- **Infant Agent**: 记忆检索机制减少约 80% API token 成本

**分层记忆**:
- 多分辨率摘要：全局摘要 + Agent 特定细粒度日志
- 根据团队重要性分数或任务相关性提升/降级条目
- 支持数百万轮对话的块状 episode 级摘要 + 高效近似最近邻检索

**未来方向**:
- 跨 Agent 剪枝、压缩、遗忘机制
- 去重共享经验，合并重叠交互轨迹

---

## 3. 开源项目实践

### 3.1 MemMachine

**GitHub**: [MemMachine/MemMachine](https://github.com/MemMachine/MemMachine)

**定位**: 通用记忆层，简化 AI Agent 状态管理

**架构**:
- **Episodic Memory**: 对话上下文，存储在**图数据库**
- **Profile Memory**: 长期用户事实，存储在 **SQL 数据库**
- 可扩展、可互操作的记忆存储和检索

**适用场景**: 下一代自主系统

### 3.2 nemori

**GitHub**: [nemori-ai/nemori](https://github.com/nemori-ai/nemori)

**核心洞察**: 将 AI 记忆与人类情景记忆粒度对齐

**实现**:
- 摄取多轮对话
- **分段为主题一致的 episodes**
- 提炼持久语义知识
- 提供统一搜索界面

**技术**:
- 结合事件分割理论（Event Segmentation Theory）和预测处理
- 生产级并发、缓存、可插拔存储
- 2025 年 9 月开源，覆盖 episodic 和 semantic 记忆的端到端实现

### 3.3 Mem0

**GitHub**: [mem0ai/mem0](https://github.com/mem0ai/mem0)

**定位**: 通用记忆层，实现个性化 AI 交互

**性能**:
- LOCOMO 基准上比 OpenAI Memory 准确率提升 **26%**
- 响应速度比全上下文快 **91%**

**适用场景**: 客服聊天机器人、AI 助手、自主系统

### 3.4 Letta

**GitHub**: [letta-ai/letta](https://github.com/letta-ai/letta)

**定位**: 构建有状态 Agent 的平台

**核心特性**:
- **Memory-first coding harness**: 不是独立会话，而是持久化 Agent
- Agent 随时间学习并可跨模型迁移
- 高级记忆，能自我改进

### 3.5 Beads

**博客**: [Beads: Git-Backed Issue Tracking](https://aibit.im/blog/post/beads-elevate-your-ai-agent-s-memory-with-git-backed-issue-tracking)

**核心创新**: **Git 作为数据库**

**架构**:
- 真相源：`.beads/issues.jsonl`（JSONL 文件提交到 Git）
- 每台机器维护本地 SQLite 缓存
- 智能自动同步机制保持缓存与 Git 仓库同步
- **无需 PostgreSQL/MySQL**，只需 Git

**特性**:
- JSONL 记录提交到 Git 实现共享状态
- 跨机器 Agent 共享一个逻辑数据库
- 每次变更都有日志，提供完整审计跟踪

---

## 4. 可观测性和追踪标准

### 4.1 OpenTelemetry + 追踪标准

**主流做法**: 使用 [OpenTelemetry](https://langfuse.com/integrations/native/opentelemetry) 标准进行 Agent 追踪

**核心概念**:

1. **Trace（追踪）**
   - 代表一个端到端操作（一个"工作流"）
   - 属性：`workflow_name`（如"代码生成"、"客户服务"）
   - 唯一 `trace_id`（格式：`trace_<32_alphanumeric>`）

2. **Span（跨度）**
   - Trace 中的一个操作单元（如函数调用、RAG 检索步骤）
   - 可嵌套表示父子关系
   - 包含属性、事件、时间信息

3. **Event（事件）**
   - 单个时间点的事件（如用户点击）

**平台对比**:

| 特性 | Langfuse | LangSmith |
|------|----------|-----------|
| 开源 | 是 | 否 |
| 框架中立 | 是（基于 OTEL） | LangChain/LangGraph 原生 |
| 自托管 | 是 | 企业版 |
| 成本 | 免费 | 商业 |

**Langfuse 特性**: [Langfuse Docs](https://langfuse.com/docs/observability/overview)
- 组织为：Observations（观察）、Traces（追踪）、Sessions（会话）
- 支持特定于 LLM 应用的 Observation 类型：Generations（生成）、Tool Calls（工具调用）、RAG Retrieval（RAG 检索）

**LangSmith 特性**: [LangSmith Observability](https://www.langchain.com/langsmith/observability)
- LangChain/LangGraph 深度集成（只需设置环境变量）
- 实时监控、告警、成本/延迟/质量追踪
- 企业版支持自托管

### 4.2 AWS Bedrock Agent Tracing

**文档**: [Bedrock Trace Events](https://docs.aws.amazon.com/bedrock/latest/userguide/trace-events.html)

**Trace 组件**:
- **PreProcessingTrace**: 预处理步骤（上下文化和分类用户输入）
- **OrchestrationTrace**: 编排步骤（解释输入、调用动作组、查询知识库）
- **PostProcessingTrace**: 后处理步骤（处理最终输出，决定如何返回响应）

**用途**: 追踪 Agent 的推理过程，从用户输入到响应的路径

### 4.3 OpenAI Agents SDK

**文档**: [OpenAI Agents SDK Tracing](https://openai.github.io/openai-agents-python/tracing/)

**核心特性**:
- Trace = 端到端操作，由 Spans 组成
- `workflow_name` 属性标识逻辑工作流
- 自动生成 `trace_id`（或手动传递）
- 可全局禁用：`OPENAI_AGENTS_DISABLE_TRACING=1`

**Trace Grading**: [评分机制](https://platform.openai.com/docs/guides/trace-grading)
- 为 Agent 的 trace 分配结构化分数或标签
- 评估正确性、质量、符合预期
- 识别 Agent 成功/失败之处，针对性改进

**Memory Management**: [Session Memory](https://cookbook.openai.com/examples/agents_sdk/session_memory)
- Session 存储特定会话的对话历史
- 自动上下文管理（trimming 和 compression）

### 4.4 Microsoft Foundry

**文档**: [Trace and Observe AI Agents](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/trace-agents-sdk)

**贡献**: 引入 OpenTelemetry 的新语义约定
- 为多 Agent 系统建立标准化追踪和遥测
- 一致记录质量、性能、安全、成本的关键指标
- 集成到 Microsoft Foundry、Semantic Kernel、Azure AI 包

---

## 5. 推荐方案

基于研究，以下是针对你的场景的推荐方案：

### 5.1 核心架构：简化为标准追踪 + 自动摘要

**不要**创建自定义事件类型（observe/hypothesis/investigate/discovery/resolve/lesson），这太细碎且难维护。

**应该**采用**标准 OpenTelemetry 模型**：

```
Trace（一个子 Agent 任务）
  ├── Span: 初始化任务
  ├── Span: 分析代码库
  │     ├── Event: 发现关键文件 X
  │     └── Event: 识别依赖关系 Y
  ├── Span: 实现特性 A
  │     ├── Event: 尝试方法 1（失败）
  │     ├── Event: 修改为方法 2（成功）
  │     └── Event: 运行测试通过
  └── Span: 完成任务
        └── Event: 生成最终报告
```

### 5.2 文件结构

```
.agent-memory/
├── traces/
│   └── <trace_id>.jsonl          # 每个 Trace 一个文件（Spans + Events）
├── summaries/
│   └── <trace_id>-summary.md     # 自动生成的摘要
└── knowledge/
    ├── patterns.jsonl             # 提取的可复用模式（Semantic Memory）
    └── index.json                 # 元数据索引
```

**为什么 JSONL**:
- 追加友好（append-only），一行一个事件
- 低内存占用（流式解析）
- 适合 TB 级数据集
- [JSONL 优势](https://www.speakeasy.com/blog/why-api-producers-should-care-about-jsonl)

### 5.3 事件记录格式

**Span 格式**:
```json
{
  "type": "span",
  "trace_id": "trace_abc123",
  "span_id": "span_xyz789",
  "parent_span_id": "span_parent456",
  "name": "实现特性 A",
  "start_time": "2026-01-05T10:00:00Z",
  "end_time": "2026-01-05T10:15:00Z",
  "status": "ok",
  "attributes": {
    "worktree": "/path/to/worktree",
    "model": "claude-sonnet-4-5",
    "cost_tokens": 5000
  }
}
```

**Event 格式**:
```json
{
  "type": "event",
  "trace_id": "trace_abc123",
  "span_id": "span_xyz789",
  "timestamp": "2026-01-05T10:05:00Z",
  "name": "尝试方法 1 失败",
  "attributes": {
    "error": "ImportError: module not found",
    "file": "src/main.py",
    "action": "修改 import 路径"
  }
}
```

### 5.4 自动摘要提取

**触发时机**:
- 子 Agent 任务完成后
- 主 Agent 在下一次调度前

**摘要内容**（通过 LLM 生成）:
```markdown
# Task Summary: [任务名称]

**Duration**: 15 minutes
**Outcome**: Success
**Cost**: 5000 tokens

## What Was Done
- 分析了 X 代码库
- 实现了特性 A
- 运行测试并通过

## Key Insights
- 发现 module X 需要特殊 import 路径
- 方法 1 失败因为依赖版本冲突
- 方法 2 成功，使用虚拟环境隔离

## Reusable Patterns
- Pattern: "依赖冲突 → 虚拟环境"
  - Context: Python 项目多版本依赖
  - Solution: 使用 venv 隔离
  - Applicable to: 类似 Python 项目
```

### 5.5 知识提取（Semantic Memory）

**从摘要中提取可复用模式**:

```jsonl
{"pattern_id": "py-dep-conflict", "context": "Python 多版本依赖冲突", "solution": "使用 venv 隔离", "success_count": 5, "last_used": "2026-01-05"}
{"pattern_id": "git-worktree-cleanup", "context": "worktree 残留导致冲突", "solution": "先 prune 再 add", "success_count": 3, "last_used": "2026-01-04"}
```

**在下次任务前**，主 Agent 可查询相关 patterns：
```
Query: "Python 项目依赖问题"
Result: pattern "py-dep-conflict" (相似度 0.92)
```

### 5.6 主 Agent 如何使用

**场景 1: 实时监控**
- 主 Agent 通过 `tail -f traces/<trace_id>.jsonl` 实时查看子 Agent 进度
- 发现关键事件（如 error）可及时介入

**场景 2: 任务完成后学习**
- 读取 `summaries/<trace_id>-summary.md`
- 提取 "Key Insights" 和 "Reusable Patterns"
- 更新 `knowledge/patterns.jsonl`

**场景 3: 未来任务规划**
- 新任务前查询 `knowledge/patterns.jsonl`
- 匹配相似上下文的成功模式
- 将相关 pattern 注入子 Agent 的 system prompt

### 5.7 与 Observability 工具集成

**可选**: 将 traces 导出到 Langfuse/LangSmith
- Langfuse 支持 OpenTelemetry 格式直接导入
- 获得可视化 UI、统计分析、成本追踪
- 适合生产环境

---

## 6. 与当前方案的对比

### 6.1 当前方案的问题

| 问题 | 描述 |
|------|------|
| **事件类型过多** | observe/hypothesis/investigate/discovery/resolve/lesson 六种类型，心智负担高 |
| **状态机复杂** | 需要定义状态转移规则，维护困难 |
| **非标准化** | 自定义格式难以与现有工具集成（如 Langfuse） |
| **缺乏分层** | 所有事件平铺在一个流中，难以提取高层洞察 |
| **手动维护** | lessons-learned.md 需要手动更新，容易遗漏 |

### 6.2 推荐方案的优势

| 优势 | 描述 |
|------|------|
| **标准化** | 使用 OpenTelemetry Trace/Span/Event，可直接集成到 Langfuse/LangSmith |
| **简洁** | 只有三种核心类型（Trace/Span/Event），符合直觉 |
| **自动化** | 摘要和知识提取通过 LLM 自动生成，无需手动维护 |
| **分层清晰** | Trace → Span → Event 天然分层，易于导航和理解 |
| **可观测性** | 兼容工业标准，可使用成熟的可观测性工具栈 |
| **实用性** | Beads 和 nemori 等项目证明 JSONL + 摘要的有效性 |

### 6.3 迁移路径

从你的当前方案迁移到推荐方案：

| 当前概念 | 映射到推荐方案 |
|----------|---------------|
| `stream.jsonl` | `traces/<trace_id>.jsonl`（每个 Trace 独立文件） |
| `observe` | Event（type: observation） |
| `hypothesis` | Event（type: reasoning，在 Span: 分析问题 内） |
| `investigate` | Span（name: 调查 X） |
| `discovery` | Event（type: insight，在相应 Span 内） |
| `resolve` | Span（name: 实现解决方案） |
| `lesson` | 不再是事件，而是摘要的 "Key Insights" 部分 |
| `lessons-learned.md` | `knowledge/patterns.jsonl`（自动提取） |
| `artifacts/` | 不变，或移到 `traces/<trace_id>/artifacts/` |

### 6.4 实施建议

**阶段 1: 基础追踪**（立即可做）
- 实现 Trace/Span/Event 基础记录
- 每个子 Agent 任务生成一个 `<trace_id>.jsonl`
- 主 Agent 可实时读取（`tail -f`）

**阶段 2: 自动摘要**（1-2 周）
- 子 Agent 完成后调用 LLM 生成摘要
- 摘要存为 `<trace_id>-summary.md`
- 主 Agent 读取摘要而非原始 JSONL（减少 token）

**阶段 3: 知识提取**（2-4 周）
- 从多个摘要中提取共同模式
- 构建 `knowledge/patterns.jsonl`
- 向量化 patterns，支持语义搜索

**阶段 4: 工具集成**（可选）
- 导出到 Langfuse 进行可视化分析
- 集成到 CI/CD 流程

---

## 7. 参考链接

### 主流框架
- [LangChain: Memory for agents](https://blog.langchain.com/memory-for-agents/)
- [LangChain: Memory overview](https://docs.langchain.com/oss/python/concepts/memory)
- [LangChain: LangMem SDK launch](https://blog.langchain.com/langmem-sdk-launch/)
- [LangChain: How to Extract Episodic Memories](https://langchain-ai.github.io/langmem/guides/extract_episodic_memories/)
- [MongoDB: Powering Long-Term Memory for Agents](https://www.mongodb.com/company/blog/product-release-announcements/powering-long-term-memory-for-agents-langgraph)
- [LangChain: Long-term Memory in LLM Applications](https://langchain-ai.github.io/langmem/concepts/conceptual_guide/)
- [DeepLearning.AI: Long-Term Agentic Memory with LangGraph](https://www.deeplearning.ai/short-courses/long-term-agentic-memory-with-langgraph/)
- [LlamaIndex: Improved Long & Short-Term Memory](https://www.llamaindex.ai/blog/improved-long-and-short-term-memory-for-llamaindex-agents)
- [LlamaIndex: Memory Documentation](https://docs.llamaindex.ai/en/stable/module_guides/deploying/agents/memory/)
- [LlamaIndex: Simple Composable Memory](https://docs.llamaindex.ai/en/stable/examples/agent/memory/composable_memory/)
- [LlamaIndex: Vector Memory](https://docs.llamaindex.ai/en/stable/examples/agent/memory/vector_memory/)
- [CrewAI: Agents Documentation](https://docs.crewai.com/en/concepts/agents)
- [CrewAI Guide: Build Multi-Agent AI Teams](https://mem0.ai/blog/crewai-guide-multi-agent-ai-teams)
- [AI Agent Memory: LangGraph, CrewAI, and AutoGen Comparison](https://dev.to/foxgem/ai-agent-memory-a-comparative-analysis-of-langgraph-crewai-and-autogen-31dp)
- [LangGraph vs CrewAI vs AutoGPT](https://agixtech.com/langgraph-vs-crewai-vs-autogpt/)

### 学术研究
- [CoALA: Cognitive Architectures for Language Agents](https://arxiv.org/abs/2309.02427)
- [CoALA Explained](https://www.cognee.ai/blog/fundamentals/cognitive-architectures-for-language-agents-explained)
- [Memory in LLM-based Multi-agent Systems](https://www.techrxiv.org/users/1007269/articles/1367390)
- [Collaborative Memory: Multi-User Memory Sharing](https://arxiv.org/html/2505.18279v1)
- [Memory in the Age of AI Agents](https://arxiv.org/abs/2512.13564)
- [Agent-Memory-Paper-List](https://github.com/Shichun-Liu/Agent-Memory-Paper-List)
- [Awesome-Memory-for-Agents](https://github.com/TsinghuaC3I/Awesome-Memory-for-Agents)

### 开源项目
- [MemMachine/MemMachine](https://github.com/MemMachine/MemMachine)
- [nemori-ai/nemori](https://github.com/nemori-ai/nemori)
- [mem0ai/mem0](https://github.com/mem0ai/mem0)
- [letta-ai/letta](https://github.com/letta-ai/letta)
- [ALucek/agentic-memory](https://github.com/ALucek/agentic-memory)
- [Beads: Git-Backed Issue Tracking](https://aibit.im/blog/post/beads-elevate-your-ai-agent-s-memory-with-git-backed-issue-tracking)

### 追踪和可观测性
- [AWS Bedrock: Track agent's reasoning with trace](https://docs.aws.amazon.com/bedrock/latest/userguide/trace-events.html)
- [Agentuity: Agent Tracing](https://agentuity.dev/Guides/agent-tracing)
- [OpenAI Agents SDK: Tracing](https://openai.github.io/openai-agents-python/tracing/)
- [OpenAI: Trace grading](https://platform.openai.com/docs/guides/trace-grading)
- [OpenAI Agents SDK: Session Memory](https://cookbook.openai.com/examples/agents_sdk/session_memory)
- [Microsoft: Trace and Observe AI Agents in Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/trace-agents-sdk)
- [Langfuse: LLM Observability & Application Tracing](https://langfuse.com/docs/observability/overview)
- [Langfuse: Tracing Data Model](https://langfuse.com/docs/observability/data-model)
- [Langfuse: OpenTelemetry Integration](https://langfuse.com/integrations/native/opentelemetry)
- [LangSmith: Observability](https://www.langchain.com/langsmith/observability)
- [Langfuse vs LangSmith](https://www.zenml.io/blog/langfuse-vs-langsmith)

### 实践和模式
- [Agent Logs: Definition, Monitoring, and Optimization](https://www.adopt.ai/glossary/agent-logs)
- [Structured Data for Agentic Workflows](https://oleg-dubetcky.medium.com/structured-data-for-agentic-workflows-a-skill-extraction-blueprint-62e9e54a777d)
- [Why API Producers Should Care About JSONL](https://www.speakeasy.com/blog/why-api-producers-should-care-about-jsonl)
- [Practical Memory Patterns for Longer-Horizon Agent Workflows](https://www.ais.com/practical-memory-patterns-for-reliable-longer-horizon-agent-workflows/)
- [Taming AI Agents: Practical Lessons](https://medium.com/@erataj/taming-ai-agents-practical-lessons-from-my-first-multi-agent-workflow-41b732a45c41)
- [Top AI Agentic Workflow Patterns](https://blog.bytebytego.com/p/top-ai-agentic-workflow-patterns)
- [Understanding Agentic Workflows: Patterns and Use Cases](https://codewave.com/insights/agentic-workflows-patterns-use-cases/)
- [One year of agentic AI: Six lessons](https://www.mckinsey.com/capabilities/quantumblack/our-insights/one-year-of-agentic-ai-six-lessons-from-the-people-doing-the-work)
- [What Are Agentic Workflows?](https://weaviate.io/blog/what-are-agentic-workflows)

---

## 8. 总结和行动建议

### 核心建议

1. **简化事件类型**：放弃 6 种自定义类型，采用标准 Trace/Span/Event
2. **使用 JSONL**：每个任务一个 `.jsonl` 文件，追加式记录
3. **自动摘要**：任务完成后用 LLM 生成结构化摘要
4. **知识提取**：从摘要中提取可复用 patterns，构建 Semantic Memory
5. **标准兼容**：遵循 OpenTelemetry 规范，便于未来集成 Langfuse 等工具

### 立即可做

```bash
# 1. 重构目录结构
mkdir -p .agent-memory/{traces,summaries,knowledge}

# 2. 实现基础 Trace 记录
# 子 Agent 启动时创建 traces/<trace_id>.jsonl
# 每个操作追加 Span/Event（JSON 一行）

# 3. 主 Agent 实时监控
# tail -f .agent-memory/traces/<trace_id>.jsonl
```

### 下一步演进

- **Week 1-2**: 基础追踪 + 实时监控
- **Week 3-4**: 自动摘要生成
- **Month 2**: 知识提取和模式复用
- **Month 3**: 考虑集成 Langfuse 进行可视化

### 最后的话

你的原始直觉是对的——需要捕获工作过程而非仅结果。但实现上不需要发明新概念（observe/hypothesis/...），而应**站在巨人肩膀上**，使用已被验证的 OpenTelemetry 模型 + JSONL 格式 + LLM 自动摘要。这种方案在 Beads、nemori、LangChain 等项目中已被证明有效，简单、标准、可扩展。

**Keep it simple, keep it standard.**

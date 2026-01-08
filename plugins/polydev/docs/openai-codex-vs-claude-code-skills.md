# OpenAI Codex CLI vs Claude Code: Skill 开发对比研究报告

## 摘要

本报告对 OpenAI Codex CLI 和 Claude Code 的 skill 开发机制进行了深入对比研究。两个平台都采用了基于 Markdown 的 skill 系统，并且都遵循了 Anthropic 首创的 Agent Skills 开放标准（agentskills.io）。核心发现：

- **统一标准**：两者都使用 `SKILL.md` + YAML frontmatter 格式，这是 Agent Skills 开放标准的一部分
- **渐进式披露**：都采用轻量级元数据索引 + 按需加载完整内容的设计，优化 context 管理
- **自动触发**：都支持基于 description 字段的语义匹配自动调用机制
- **生态系统**：Anthropic 主导标准制定，OpenAI 和多家厂商（Microsoft, GitHub, Cursor 等）快速跟进
- **关键差异**：Claude Code 更注重开发者控制和本地工作流，Codex CLI 则提供云端 + 本地混合模式和更高的自动化程度

## 1. OpenAI Codex CLI 概述

### 1.1 产品定位

OpenAI Codex CLI 是 OpenAI 推出的命令行 AI 编码代理（coding agent），可以在本地终端中读取、修改和运行代码。它是一个开源项目，使用 Rust 语言构建以保证速度和效率。

**核心特性：**
- 轻量级终端 UI，支持交互式对话
- 可配置的自动化级别（Suggest / Auto Edit / Full Auto）
- 支持本地和云端混合工作模式
- 内置 Model Context Protocol (MCP) 集成
- 开源且免费（仅 API 调用收费）

**平台支持：**
- macOS、Windows、Linux 全平台支持
- 默认使用 gpt-5-codex（macOS/Linux）或 gpt-5（Windows）
- 可通过 `/model` 命令切换模型

### 1.2 架构设计

Codex CLI 采用模块化架构，核心组件包括：

1. **终端 UI 层**：全屏交互式界面，实时显示代码变更
2. **代理核心**：基于 Rust 的高性能执行引擎
3. **工具层**：文件操作、Shell 执行、Web 搜索等
4. **MCP 协议层**：连接第三方工具和资源
5. **Skills 系统**：动态加载的能力扩展机制

**配置管理：**
- 共享配置文件：`~/.codex/config.toml`
- CLI 和 IDE 扩展共享同一配置
- 支持沙箱模式和审批策略配置

### 1.3 Skill/插件系统

Codex 的 skill 系统是其核心扩展机制，允许团队和个人将领域知识封装为可重用的工作流。

**设计理念：**
- "Onboarding guides for specific domains" —— 将通用代理转化为领域专家
- Progressive disclosure —— 三级加载系统最小化 context 消耗
- 模块化 —— 每个 skill 是独立的能力包

---

## 2. Claude Code Skill 系统

### 2.1 架构设计

Claude Code 是 Anthropic 推出的 AI 编码助手，强调"developer-in-the-loop"的协作式开发体验。

**核心特性：**
- 深度理解和推理能力（基于 Claude 3/4 系列模型）
- 强大的 context 管理能力，适合大型代码库
- 丰富的扩展机制：Skills、Commands、Subagents、Hooks
- 原生 MCP 支持（包括 HTTP 和 STDIO）
- 插件市场生态

**架构组件：**
1. **Skills**：自动触发的能力扩展（模型决策）
2. **Commands**：用户手动触发的工作流（斜杠命令）
3. **Subagents**：后台执行的专用代理
4. **Hooks**：事件驱动的自动化
5. **MCP Servers**：外部工具和数据源集成

### 2.2 开发方式

Claude Code skill 开发流程简单直接：

1. 在 `.claude/skills/` 或 `~/.config/claude/skills/` 创建 skill 目录
2. 编写 `SKILL.md` 文件（YAML frontmatter + Markdown 指令）
3. 添加可选的脚本、模板、参考文档
4. 重启 Claude Code 或使用 `/skills` 命令刷新

**开发工具：**
- 无需特殊工具，纯文本编辑器即可
- 可通过 plugin 形式打包分发
- 支持 `marketplace.json` 实现一键安装

### 2.3 分发机制

Claude Code 支持多种 skill 分发方式：

1. **项目级**：`.claude/skills/` —— 随代码库共享
2. **用户级**：`~/.config/claude/skills/` —— 个人全局 skills
3. **插件市场**：通过 `/plugin install` 安装
4. **企业部署**：管理员统一推送

**社区生态：**
- 官方仓库：[anthropics/skills](https://github.com/anthropics/skills)
- 第三方市场：SkillsMP、claude-plugins.dev
- 众多开源集合：awesome-claude-skills 等

---

## 3. 详细对比分析

### 3.1 架构设计对比

| 维度 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **实现语言** | Rust（CLI 核心） | 未公开（闭源） |
| **开源性** | CLI 开源，模型闭源 | 完全闭源 |
| **运行模式** | 本地 + 云端混合 | 本地优先，支持云端（Codex Cloud） |
| **配置文件** | `~/.codex/config.toml` | `~/.config/claude/config.json` + `.claude/` 项目配置 |
| **扩展机制** | Skills + MCP + Slash Commands | Skills + Commands + Hooks + Subagents + MCP |
| **工具协议** | MCP (STDIO) | MCP (STDIO + HTTP) |
| **审批模式** | 三级（Suggest / Auto Edit / Full Auto） | 细粒度工具权限控制 |

**关键差异：**
- **Codex** 更注重性能和轻量化，使用 Rust 实现
- **Claude Code** 提供更丰富的扩展点（Hooks、Subagents）
- **Codex** 的自动化级别可全局配置，更适合批量操作
- **Claude Code** 强调每一步都保持人类知情权

### 3.2 开发体验对比

#### OpenAI Codex CLI

**创建 Skill：**
```bash
# 使用内置的 skill-creator
$ codex
> $skill-creator
# 描述 skill 功能，Codex 自动生成骨架

# 或手动创建
mkdir -p ~/.codex/skills/my-skill
cat > ~/.codex/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: What this skill does and when to use it
---
# My Skill Instructions

[Detailed instructions here]
EOF
```

**安装社区 Skill：**
```bash
$ codex
> $skill-installer install create-plan from .experimental
# 重启 Codex 以加载新 skill
```

#### Claude Code

**创建 Skill：**
```bash
# 项目级 skill
mkdir -p .claude/skills/my-skill
cat > .claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: What this skill does and when to use it
---
# My Skill Instructions

[Detailed instructions here]
EOF

# 或通过插件创建
claude-code
/plugin install skill-creator
/skill create my-skill
```

**开发工具对比：**

| 特性 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **脚手架工具** | `$skill-creator`（内置） | 社区插件（如 skill-creator） |
| **热重载** | 需要重启 Codex | 部分支持，推荐 `/clear` |
| **调试支持** | `codex --enable skills`（feature flag） | `--mcp-debug`（MCP 调试） |
| **文档生成** | 无 | 社区工具支持 |
| **测试框架** | 手动测试 | 手动测试 |

**开发体验总结：**
- **Codex** 的 `$skill-creator` 更加智能，可自动生成完整骨架
- **Claude Code** 生态工具更丰富，但依赖社区贡献
- 两者都缺乏官方测试框架，skill 质量依赖开发者经验

### 3.3 配置格式对比

两者都使用 **SKILL.md + YAML frontmatter** 格式，这是 Agent Skills 开放标准的核心规范。

#### 基础格式（完全一致）

```yaml
---
name: skill-name
description: Description that helps the agent select the skill
metadata:
  short-description: Optional user-facing description
---

# Skill Instructions

[Markdown content with instructions, examples, and guidelines]
```

#### OpenAI Codex CLI 扩展字段

```yaml
---
name: skill-creator
description: |
  Guide for creating effective skills. Use when users want to create
  a new skill that extends Codex's capabilities.
metadata:
  short-description: Create and update skills
  version: 1.0.0
---
```

**字段约束：**
- `name`：非空，最多 100 字符，单行
- `description`：非空，最多 500 字符，单行（关键触发依据）
- `metadata`：可选，用于用户界面展示

#### Claude Code 扩展字段

```yaml
---
name: my-skill
description: Clear description of what this skill does and when to use it
metadata:
  short-description: Optional user-facing description
  dependencies:
    - python3
    - requests
  disable-model-invocation: false  # Claude 独有：禁用自动触发
---
```

**独有字段：**
- `dependencies`：声明 skill 依赖的软件包
- `disable-model-invocation`：设为 `true` 时禁用自动触发，只能通过 `/skill-name` 手动调用

#### 目录结构对比

**OpenAI Codex CLI：**
```
skill-name/
├── SKILL.md             # 必需：元数据 + 指令
├── scripts/             # 可选：可执行脚本（Python/Bash 等）
├── references/          # 可选：按需加载的参考文档
└── assets/              # 可选：输出模板、图标、字体等
```

**Claude Code：**
```
skill-name/
├── SKILL.md             # 必需：元数据 + 指令
├── scripts/             # 可选：辅助脚本
├── templates/           # 可选：文件模板
├── utils/               # 可选：工具函数
└── references/          # 可选：参考文档
```

**差异说明：**
- Codex 明确区分 `assets/`（输出资源）和 `references/`（文档）
- Claude Code 更灵活，允许任意子目录结构
- 两者都推荐"一级引用"原则：SKILL.md 直接链接文件，避免嵌套

### 3.4 能力范围对比

#### OpenAI Codex CLI Skill 能力

**核心能力：**
1. **指令注入**：将 SKILL.md 内容注入到 context 中
2. **脚本执行**：运行 `scripts/` 中的可执行文件（Python、Bash、Node.js 等）
3. **资源引用**：按需加载 `references/` 中的文档
4. **模板应用**：复制或修改 `assets/` 中的模板文件

**示例用例：**
- **文档生成**：使用 `assets/template.md` 生成符合规范的文档
- **代码生成**：基于 `references/schema.json` 生成 API 客户端
- **数据分析**：执行 `scripts/analyze.py` 处理 BigQuery 数据
- **工作流自动化**：按步骤指南完成复杂任务（如 PR review）

**限制：**
- 不能直接调用 OpenAI API（需通过脚本）
- 不能持久化状态（每次会话独立）
- 不能与其他 skill 通信

#### Claude Code Skill 能力

**核心能力：**
1. **指令注入**：将 SKILL.md 内容注入到 context 中
2. **脚本执行**：运行 skill 目录中的脚本
3. **资源引用**：按需加载参考文档
4. **调用其他 skills**：可以引用其他 skill（如 `$another-skill`）
5. **触发 subagents**：启动后台代理执行长任务
6. **调用 MCP 工具**：使用 MCP server 提供的工具

**示例用例：**
- **PR 审查**：结合 GitHub MCP server 自动化 code review
- **测试驱动开发**：先写测试，再实现功能
- **数据库查询**：使用企业数据库 schema 生成 SQL
- **设计转代码**：从 Figma MCP server 读取设计生成代码

**限制：**
- 不能绕过工具权限审批
- 不能访问未授权的文件或目录
- 不能执行危险命令（除非用户批准）

**能力对比总结：**

| 能力 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **基础指令注入** | ✅ | ✅ |
| **脚本执行** | ✅ | ✅ |
| **资源引用** | ✅ | ✅ |
| **调用其他 skills** | ❌ | ✅ |
| **触发 subagents** | ❌ | ✅ |
| **MCP 工具调用** | ✅ (间接) | ✅ (直接) |
| **持久化状态** | ❌ | ❌ |
| **跨 skill 通信** | ❌ | 有限（通过文件） |

### 3.5 分发机制对比

#### OpenAI Codex CLI

**官方渠道：**
- **官方仓库**：[openai/skills](https://github.com/openai/skills)
  - `.system/`：内置 skills（自动安装）
  - `.curated/`：官方精选 skills
  - `.experimental/`：实验性 skills

**安装方式：**
```bash
# 使用 skill-installer
$skill-installer install create-plan from .experimental

# 手动克隆
git clone https://github.com/openai/skills.git
cp -r skills/.curated/my-skill ~/.codex/skills/

# 通过 GitHub URL
$skill-installer --url https://github.com/user/repo/tree/main/path/to/skill
```

**Scope 层级：**
1. **System**（最低优先级）：`~/.codex/skills/.system/` —— 内置 skills
2. **Admin**：`/etc/codex/skills/` —— 系统级（所有用户）
3. **User**：`~/.codex/skills/` —— 用户级（所有项目）
4. **Repo**（最高优先级）：`.codex/skills/` —— 项目级（随代码库）

**优先级规则：**
- 同名 skill 按 Repo > User > Admin > System 覆盖
- 可用于团队统一 skill 版本或本地测试

#### Claude Code

**官方渠道：**
- **官方仓库**：[anthropics/skills](https://github.com/anthropics/skills)
- **插件市场**：
  - [claude-plugins.dev](https://claude-plugins.dev/)
  - [SkillsMP](https://skillsmp.com/) —— 跨平台 skill 市场（25,000+ skills）

**安装方式：**
```bash
# 通过插件市场
/plugin marketplace add <plugin-name>

# 手动复制
git clone https://github.com/anthropics/skills.git
cp -r skills/my-skill ~/.config/claude/skills/

# 项目级安装
cp -r skills/my-skill .claude/skills/
```

**Scope 层级：**
1. **Built-in**（最低优先级）：内置 skills
2. **Plugin**：插件提供的 skills
3. **User**：`~/.config/claude/skills/` —— 用户级
4. **Project**（最高优先级）：`.claude/skills/` —— 项目级

**企业部署：**
- `managed-mcp.json`：管理员强制部署（用户无法修改）
- Allowlist/Denylist：基于策略的访问控制

#### marketplace.json（Claude Code 独有）

```json
{
  "name": "my-skill",
  "version": "1.0.0",
  "description": "Brief description",
  "author": "Your Name",
  "repository": "https://github.com/user/repo",
  "install_command": "/plugin install my-skill"
}
```

**优势：**
- 一键安装，无需手动复制文件
- 版本管理和更新提示
- 市场展示徽章

**对比总结：**

| 维度 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **官方仓库** | ✅ openai/skills | ✅ anthropics/skills |
| **内置安装工具** | ✅ $skill-installer | ✅ /plugin install |
| **Scope 层级** | 4 级（System/Admin/User/Repo） | 4 级（Built-in/Plugin/User/Project） |
| **企业部署** | ✅ Admin scope | ✅ managed-mcp.json |
| **第三方市场** | ✅ SkillsMP | ✅ SkillsMP + claude-plugins.dev |
| **一键安装** | ❌ | ✅ marketplace.json |
| **版本管理** | 手动 | 插件系统自动 |

### 3.6 触发机制对比

#### OpenAI Codex CLI

**自动触发（Implicit Invocation）：**
- Codex 在启动时加载所有 skill 的 `name` 和 `description`
- 当用户请求与 `description` 语义匹配时，Codex 自动读取完整 SKILL.md
- 触发算法：基于 description 的语义相似度（具体算法未公开）

**手动触发（Explicit Invocation）：**
```bash
# 方式 1：使用 /skills 命令选择
/skills
# 选择一个 skill

# 方式 2：直接提及 skill
$skill-name do something

# 方式 3：在 prompt 中引用
"Use $skill-name to analyze this data"
```

**触发优化建议：**
- 在 `description` 中明确"when to use"条件
- 包含关键词以提高匹配率
- 测试不同表述方式确保触发准确

#### Claude Code

**自动触发（Model-Invoked）：**
- Claude 加载所有 skill 的 metadata（name + description）
- 基于 description 进行子串和语义匹配
- 匹配成功后调用 `Skill` tool 注入 SKILL.md 内容

**手动触发：**
```bash
# 方式 1：斜杠命令（如果配置了）
/skill-name

# 方式 2：在 prompt 中提及
"Use the skill-name skill to..."
```

**禁用自动触发：**
```yaml
---
name: dangerous-skill
description: Performs critical operations
metadata:
  disable-model-invocation: true  # 只能手动调用
---
```

**触发可靠性优化：**

根据社区研究（Scott Spence, 200+ 测试），以下方法可将触发成功率从 50% 提升到 80-84%：

1. **WHEN + WHEN NOT 模式：**
```yaml
description: |
  Creates professional documents (.docx) with formatting.
  WHEN: User asks to create/edit .docx files, add comments, track changes.
  WHEN NOT: For simple text files, PDFs, or spreadsheets.
```

2. **关键词列表：**
```yaml
description: |
  GitHub PR review automation. Triggers on: "review PR", "code review",
  "check pull request", "analyze PR", "PR feedback".
```

3. **Forced Eval Hook（高级技巧）：**
```markdown
# 在 SKILL.md 开头
Before proceeding, you MUST evaluate all available skills and confirm
which ones are relevant to this request. List them explicitly.
```

#### 触发机制对比总结

| 维度 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **自动触发** | ✅ 基于 description 语义匹配 | ✅ 子串 + 语义匹配 |
| **手动触发** | ✅ `/skills` + `$skill-name` | ✅ `/skill-name` |
| **禁用自动触发** | ❌ | ✅ `disable-model-invocation: true` |
| **触发准确率** | 未公开基准数据 | ~50%（社区测试）→ 80%+ (优化后) |
| **触发调试** | `codex --enable skills` | 观察 `/context` 中的 skill 加载 |

**关键洞察：**
- 两者都依赖 `description` 质量，这是最大的挑战
- Claude Code 的触发机制相对简单（子串匹配），Codex 可能更智能（但未公开）
- 开发者需要大量测试来优化 description 触发准确率

### 3.7 工具集成对比

#### OpenAI Codex CLI + MCP

**MCP 支持：**
- **STDIO 传输**：✅ 完全支持
- **HTTP 传输**：❌ 不支持（仅 STDIO）
- **配置文件**：`~/.codex/config.toml`

**配置示例：**
```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upnext/context7"]
env = { CONTEXT7_API_KEY = "your-key" }

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@anthropic-ai/mcp-server-playwright"]
```

**内置工具：**
- 文件操作（read、write、edit）
- Shell 执行（bash、command）
- Web 搜索（browsing）
- Git 操作（status、diff、commit、push）

**Codex as MCP Server：**
- `codex-mcp-server`：将 Codex CLI 包装为 MCP 服务器
- 可被其他 AI 系统（如 OpenAI Agents SDK）调用
- 提供 `codex` 和 `codex-reply` 两个 MCP 工具

#### Claude Code + MCP

**MCP 支持：**
- **STDIO 传输**：✅ 完全支持
- **HTTP 传输**：✅ 完全支持（推荐云端服务）
- **配置方式**：
  1. 项目级：`.mcp.json`（随代码库共享）
  2. 用户级：`~/.config/claude/mcp.json`
  3. 企业级：`managed-mcp.json`（强制部署）

**配置示例：**
```json
{
  "mcp_servers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "your-token"
      }
    },
    "sentry": {
      "url": "https://sentry-mcp.example.com/mcp",
      "headers": {
        "Authorization": "Bearer your-token"
      }
    }
  }
}
```

**内置工具：**
- 文件操作（Read、Write、Edit）
- 终端执行（Bash）
- Web 搜索（WebSearch）
- Web 抓取（WebFetch）
- 代码搜索（Grep、Glob）
- 任务管理（TodoWrite）
- Notebook 编辑（NotebookEdit）

**热门 MCP Servers：**
- **GitHub**：仓库、Issues、PR、CI/CD 工作流
- **Figma Dev Mode**：从设计生成代码
- **Sentry**：错误日志和问题跟踪
- **Linear**：项目管理和任务跟踪
- **Notion**：知识库集成
- **Puppeteer/Playwright**：浏览器自动化

#### MCP 生态对比

| 维度 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **STDIO 支持** | ✅ | ✅ |
| **HTTP 支持** | ❌ | ✅ |
| **配置灵活性** | 中等（仅 config.toml） | 高（项目/用户/企业三级） |
| **调试工具** | 基础 | `--mcp-debug` 标志 |
| **热门集成数** | 较少（因 HTTP 缺失） | 较多（200+ via Docker MCP Toolkit） |
| **自建 MCP Server** | ✅ 标准协议 | ✅ 标准协议 |
| **作为 MCP Server** | ✅ codex-mcp-server | ✅ claude-code-mcp |

**关键差异：**
- Codex 缺少 HTTP 支持限制了云端 MCP 服务集成
- Claude Code 的三级配置更适合企业和团队场景
- 两者都可以被包装为 MCP Server 供其他系统调用

### 3.8 生态系统对比

#### OpenAI Codex CLI

**发布时间：**
- CLI 公开发布：2024 年底
- Skills 系统上线：2024 年 12 月（feature flag 保护）
- 正式 GA：2025 年 1 月

**社区活跃度：**
- GitHub Stars（openai/codex）：~15,000（截至 2026-01）
- 官方 skills 数量：~30+（.curated + .experimental）
- 第三方 skills：增长中，尚未形成大规模生态

**合作伙伴：**
- **采用 Agent Skills 标准的平台**：OpenCode、Cursor、Amp、Letta、goose、GitHub、VS Code
- **MCP 生态**：共享 Anthropic 主导的 MCP 生态系统

**企业支持：**
- 包含在 ChatGPT Plus、Pro、Business、Edu、Enterprise 计划中
- 企业管理功能：admin-scoped skills、集中配置管理

**文档和资源：**
- 官方文档：[developers.openai.com/codex](https://developers.openai.com/codex)
- Skills 仓库：[github.com/openai/skills](https://github.com/openai/skills)
- 社区教程：较少，仍在积累中

#### Claude Code

**发布时间：**
- Claude Code 1.0：2024 年初
- Claude Code 2.0：2024 年底（大幅性能提升）
- Skills 系统：自 1.0 起支持

**社区活跃度：**
- GitHub Stars（anthropics/skills）：~8,000
- 官方 skills 数量：~50+
- 第三方 skills：数千个（通过插件市场）

**合作伙伴：**
- **Agent Skills 标准发起者**：Anthropic 创建并开源
- **企业合作伙伴**：Canva、Stripe、Notion、Zapier、Figma、Atlassian
- **平台集成**：VS Code、Cursor、Windsurf、Web 版 Claude

**企业支持：**
- Claude for Work（团队版）
- Claude Enterprise（企业版，支持 SSO、审计日志）
- Skills 企业级部署（managed-mcp.json）

**文档和资源：**
- 官方文档：[code.claude.com/docs](https://code.claude.com/docs)
- Skills 指南：[docs.claude.com/skills](https://docs.claude.com/en/docs/agents-and-tools/agent-skills)
- 丰富的社区教程和博客文章
- 专门的 skill 市场：claude-plugins.dev

#### Agent Skills 开放标准

**标准主页：** [agentskills.io](https://agentskills.io)

**发起者：** Anthropic（2024 年 12 月 18 日发布）

**采用者：**
- OpenAI（Codex CLI + ChatGPT）
- Microsoft（未明确公开产品）
- GitHub Copilot
- Cursor
- Atlassian Intelligence
- Figma AI
- OpenCode、Amp、Letta、goose 等独立工具

**标准内容：**
- SKILL.md 文件格式规范
- YAML frontmatter 必需字段
- 目录结构约定（scripts/references/assets）
- Progressive disclosure 加载机制
- 互操作性保证

**意义：**
- 打破平台锁定：skill 可跨 AI 平台使用
- 加速生态发展：开发者一次编写，到处运行
- 与 MCP 互补：MCP 解决工具调用，Agent Skills 解决知识封装

#### 生态对比总结

| 维度 | OpenAI Codex CLI | Claude Code |
|------|------------------|-------------|
| **发布成熟度** | 新（2024 底 - 2025 初） | 较成熟（2024 初至今） |
| **官方 skills 数量** | ~30+ | ~50+ |
| **社区 skills 数量** | 增长中 | 数千个 |
| **插件市场** | SkillsMP（跨平台） | SkillsMP + claude-plugins.dev |
| **企业客户** | ChatGPT 订阅用户 | Claude for Work/Enterprise 客户 |
| **开放标准地位** | 采用者 | 发起者 |
| **文档完整度** | 中等 | 高 |
| **社区教程** | 较少 | 丰富 |
| **合作伙伴数** | 少数（主要技术平台） | 多（技术平台 + SaaS 企业） |

**战略差异：**
- **OpenAI**：快速跟进标准，利用 ChatGPT 巨大用户基数推广
- **Anthropic**：主导标准制定，构建开放生态以对抗 OpenAI 平台锁定

---

## 4. 优劣势总结

### 4.1 OpenAI Codex CLI 优势

**1. 性能和轻量化**
- Rust 实现，启动快、资源占用低
- 适合低配置机器和云端环境

**2. 自动化程度高**
- 三级审批模式（Suggest / Auto Edit / Full Auto）
- Full Auto 模式适合批量操作和 CI/CD 集成

**3. 云端集成**
- 与 ChatGPT 生态无缝集成
- Codex Cloud 支持远程协作和持久化会话

**4. 模型能力**
- GPT-5.2-Codex 在复杂工程任务上表现优异
- SWE-bench Verified 得分 69.1%（接近 Claude）

**5. GitHub 集成**
- 官方 GitHub App 好评如潮
- 自动 code review 能发现真实 bug
- 可直接在 PR 中修复问题

**6. 价格优势**
- CLI 工具免费开源
- Pro 计划 \$20/月（基本不限量使用）
- 适合高频用户

**7. 易用性**
- 内置 `$skill-creator` 和 `$skill-installer`
- 一步到位的 skill 创建和安装体验

### 4.2 Claude Code 优势

**1. 推理能力**
- 基于 Claude Opus/Sonnet 4，深度理解能力更强
- SWE-bench Verified 得分 72.7%（行业领先）

**2. Context 管理**
- 擅长处理大型代码库（100,000+ 行）
- 更好的上下文保持和跨文件推理

**3. 协作体验**
- "Developer-in-the-loop" 设计理念
- 每步操作都透明可控，减少意外修改

**4. 扩展生态**
- 丰富的扩展点：Skills + Commands + Hooks + Subagents
- 插件市场成熟，社区贡献活跃

**5. MCP 支持**
- 原生支持 STDIO 和 HTTP 传输
- 三级配置（项目/用户/企业）适合团队协作

**6. 确定性**
- 多次运行相同任务产生一致结果
- 适合需要稳定输出的生产环境

**7. 开放标准主导者**
- Agent Skills 标准发起者，生态话语权强
- 跨平台兼容性是长期优势

**8. 企业功能**
- SSO、审计日志、策略管理
- managed-mcp.json 集中部署

### 4.3 各自适用场景

#### 选择 OpenAI Codex CLI 的场景

1. **快速原型开发**
   - 需要快速生成代码草稿
   - 对代码质量要求不苛刻
   - 愿意后续手动审查和调整

2. **批量自动化任务**
   - CI/CD 集成
   - 大规模代码迁移和重构
   - 需要无人值守运行

3. **云端协作**
   - 团队成员使用不同设备
   - 需要持久化会话和跨设备切换
   - 使用 Codex Cloud 或 GitHub 集成

4. **成本敏感用户**
   - Pro 计划 \$20/月不限量
   - 高频使用不担心撞限额

5. **GitHub 深度用户**
   - 主要工作流在 GitHub 上
   - 需要自动化 PR review 和 issue 处理

#### 选择 Claude Code 的场景

1. **生产级代码质量**
   - 需要可维护、有文档的代码
   - 重视架构设计和最佳实践
   - 代码需直接上线而非原型

2. **大型代码库**
   - 10 万行以上代码
   - 需要跨多个文件的深度理解
   - 复杂的依赖关系和架构

3. **本地开发优先**
   - 重视数据隐私和代码安全
   - 不希望代码上传云端
   - 需要完全离线工作能力

4. **需要可靠性**
   - 相同输入需产生相同输出
   - 不能接受随机性和不确定性
   - 需要审计和回溯能力

5. **企业环境**
   - 需要 SSO 和权限管理
   - 需要审计日志和合规性
   - 多团队协作和统一配置

6. **复杂推理任务**
   - 算法设计和优化
   - 架构决策和权衡分析
   - 需要 AI "理解"业务逻辑

---

## 5. 开发者建议

### 5.1 如何选择平台

**评估问题清单：**

1. **项目类型**
   - [ ] 是原型还是生产代码？
   - [ ] 代码库规模多大（<10k / 10k-100k / >100k 行）？
   - [ ] 需要多深的架构理解？

2. **工作流偏好**
   - [ ] 喜欢高度自动化还是步步可控？
   - [ ] 能接受不确定性还是需要确定性结果？
   - [ ] 主要在本地还是云端工作？

3. **团队需求**
   - [ ] 个人项目还是团队协作？
   - [ ] 是否需要企业级功能（SSO、审计）？
   - [ ] 预算是多少（\$20 vs \$100/月）？

4. **生态需求**
   - [ ] 需要哪些第三方集成（GitHub、Figma、Sentry 等）？
   - [ ] 是否计划开发自定义 skills？
   - [ ] 更看重插件数量还是质量？

**建议决策树：**

```
需要 GitHub 深度集成？
├─ 是 → OpenAI Codex CLI
└─ 否 →
    代码库 > 100k 行？
    ├─ 是 → Claude Code
    └─ 否 →
        需要高度自动化？
        ├─ 是 → OpenAI Codex CLI
        └─ 否 →
            重视代码质量和文档？
            ├─ 是 → Claude Code
            └─ 否 → 都可以，优先 Claude Code（标准制定者）
```

### 5.2 Skill 开发最佳实践

**通用原则（适用两个平台）：**

1. **精心设计 description**
   - 这是触发机制的核心，值得花 80% 精力优化
   - 使用"WHEN + WHEN NOT"模式明确触发条件
   - 包含用户可能使用的所有关键词
   - 保持在 500 字符以内但信息密集

2. **保持 SKILL.md 简洁**
   - 目标：<500 行 Markdown
   - 将详细文档放到 `references/` 按需加载
   - 使用精炼的示例而非冗长的解释

3. **使用 Progressive Disclosure**
   - SKILL.md：核心指令和工作流
   - `references/`：详细文档、schema、规范
   - `scripts/`：可执行脚本（仅运行输出进 context）
   - `assets/`：模板和资源（不进 context）

4. **提供具体示例**
   - 比抽象描述更有效
   - 包含输入和期望输出
   - 覆盖常见场景和边缘情况

5. **测试跨模型兼容性**
   - 在多个模型上测试（GPT-5, Claude Opus, Sonnet）
   - 弱模型可能需要更详细指令
   - 强模型可能需要减少啰嗦

6. **避免嵌套引用**
   - SKILL.md → reference.md ✅
   - SKILL.md → ref1.md → ref2.md ❌
   - 深度嵌套导致 AI 只部分读取

7. **脚本优于指令（当需要确定性时）**
   - 数据验证、API 调用 → 写脚本
   - 创意任务、代码生成 → 写指令
   - 混合使用：脚本处理数据，AI 生成代码

### 5.3 平台特定技巧

#### OpenAI Codex CLI

**1. 利用 Full Auto 模式（谨慎）：**
```bash
codex --approvals full-auto
# 适合可逆操作（如生成新文件）
# 不适合修改关键文件或执行破坏性命令
```

**2. 使用 skill-creator 生成骨架：**
```bash
$skill-creator
# 回答几个问题，自动生成完整 skill 结构
# 比手动创建快 10 倍
```

**3. 测试 skill 触发：**
```bash
codex --enable skills
# 然后用不同措辞测试
"Help me with X"
"I need to do X"
"Can you X for me?"
# 观察哪个表述能触发你的 skill
```

**4. 组织 skill 目录：**
```
~/.codex/skills/
├── .local/          # 个人实验性 skills
├── team/            # 团队共享 skills（通过 git submodule）
└── vendor/          # 第三方 skills
```

#### Claude Code

**1. 使用 disable-model-invocation 控制触发：**
```yaml
---
name: dangerous-deploy
description: Deploys to production
metadata:
  disable-model-invocation: true  # 必须手动 /dangerous-deploy
---
```

**2. 利用 Subagents 保持 context：**
```markdown
# 在 SKILL.md 中
To verify details, spawn a subagent to investigate the codebase
and report back. This keeps the main context clean.
```

**3. 配置 .claude/skills/ 在项目中：**
```bash
# 项目根目录
mkdir -p .claude/skills/my-project-skill
# 编写 SKILL.md
# 提交到 git —— 全团队自动获得
```

**4. 使用 /context 调试：**
```bash
/context
# 查看哪些 skills 被加载
# 检查 MCP servers 消耗的 context
# 识别 context 瓶颈
```

**5. 优化 description 触发率：**
```yaml
description: |
  Git commit message generator following Conventional Commits.
  WHEN: User says "commit", "create commit", "commit message", "commit changes"
  WHEN NOT: For viewing history, checking status, or pushing code
  TRIGGERS: commit, commit message, generate commit, create commit
```

### 5.4 调试和故障排除

**常见问题 1：Skill 不触发**

原因和解决方案：
- **description 太模糊** → 添加明确的关键词和场景
- **文件名错误** → 必须是 `SKILL.md`（全大写）
- **YAML 格式错误** → 检查 `---` 分隔符和字段拼写
- **不在正确目录** → 确认 scope 路径正确

**常见问题 2：Context 消耗过快**

原因和解决方案：
- **SKILL.md 太长** → 拆分到 `references/`
- **太多 MCP servers** → 禁用不必要的（Claude Code：`/context`）
- **嵌套引用** → 扁平化为一级引用
- **大文件直接加载** → 改用脚本输出摘要

**常见问题 3：Skill 行为不一致**

原因和解决方案：
- **指令模糊** → 添加具体示例和边界条件
- **模型随机性** → 关键步骤改用脚本实现
- **版本冲突** → 检查是否有同名 skill 在多个 scope

**常见问题 4：脚本执行失败**

原因和解决方案：
- **没有执行权限** → `chmod +x scripts/*.sh`
- **依赖缺失** → 在 metadata 声明 `dependencies`
- **路径问题** → 使用绝对路径或 `$SKILL_DIR` 变量
- **Python 版本** → 明确 shebang（`#!/usr/bin/env python3`）

### 5.5 未来趋势和准备

**1. Agent Skills 标准将继续演进**
- 关注 [agentskills.io](https://agentskills.io) 的更新
- 新字段可能包括：版本约束、依赖声明、权限请求
- 考虑兼容性：避免使用平台特定功能

**2. Skill 市场将更加成熟**
- 预计出现付费 skills（如企业级模板）
- 质量认证和评分系统
- 自动更新和版本管理

**3. AI 能力提升将改变 Skill 设计**
- 更强模型需要更少指令
- 重点转向高层约束而非详细步骤
- 示例驱动（few-shot）可能比指令更有效

**4. 跨平台互操作性增强**
- Skill 一次编写，多平台运行
- MCP + Agent Skills 双标准驱动生态
- 投资于标准兼容的 skill 开发

**5. 企业级功能强化**
- 更细粒度的权限控制
- 审计日志和合规性报告
- Skill 使用分析和优化建议

**开发者行动建议：**
- ✅ 优先学习 Agent Skills 标准（而非平台特定功能）
- ✅ 参与社区贡献（openai/skills 或 anthropics/skills）
- ✅ 关注 MCP 生态发展
- ✅ 为自己的常见工作流创建 skills
- ✅ 分享优秀 skills 到社区市场

---

## 6. 参考资源

### 官方文档

**OpenAI Codex CLI:**
- [Codex CLI 主页](https://developers.openai.com/codex/cli/)
- [Agent Skills 文档](https://developers.openai.com/codex/skills/)
- [创建 Skills](https://developers.openai.com/codex/skills/create-skill/)
- [Model Context Protocol](https://developers.openai.com/codex/mcp/)
- [命令行参考](https://developers.openai.com/codex/cli/reference/)

**Claude Code:**
- [Claude Code 文档](https://code.claude.com/docs/en/)
- [Agent Skills 指南](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/)
- [Skill 最佳实践](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices/)
- [MCP 集成](https://code.claude.com/docs/en/mcp/)
- [Claude Code 博客](https://www.anthropic.com/engineering/claude-code-best-practices)

**Agent Skills 标准:**
- [Agent Skills 规范](https://agentskills.io/)
- [Agent Skills 标准概述](https://agentskills.io/home)

### GitHub 仓库

- [openai/codex](https://github.com/openai/codex) - Codex CLI 源码
- [openai/skills](https://github.com/openai/skills) - 官方 Skills 目录
- [anthropics/skills](https://github.com/anthropics/skills) - Claude Skills 官方仓库
- [anthropics/claude-code](https://github.com/anthropics/claude-code) - Claude Code 插件示例

### 社区资源

**比较和评测:**
- [Claude Code vs. OpenAI Codex - Composio](https://composio.dev/blog/claude-code-vs-openai-codex)
- [Testing OpenAI Codex and Comparing It to Claude Code - The New Stack](https://thenewstack.io/testing-openai-codex-and-comparing-it-to-claude-code/)
- [Codex vs Claude Code - Builder.io](https://www.builder.io/blog/codex-vs-claude-code)
- [Claude Code vs OpenAI Codex - Northflank](https://northflank.com/blog/claude-code-vs-openai-codex)

**Skill 开发教程:**
- [Skills in OpenAI Codex - fsck.com](https://blog.fsck.com/2025/12/19/codex-skills/)
- [Porting Skills to OpenAI Codex - fsck.com](https://blog.fsck.com/2025/10/27/skills-for-openai-codex/)
- [How to Make Claude Code Skills Activate Reliably - Scott Spence](https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably)
- [Claude Agent Skills: A First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
- [Inside Claude Code Skills - Mikhail Shilkov](https://mikhail.io/2025/10/claude-code-skills/)

**开放标准和生态:**
- [OpenAI Launches Skills In Codex - Dataconomy](https://dataconomy.com/2025/12/24/openai-launches-skills-in-codex-to-supercharge-agentic-coding/)
- [OpenAI are quietly adopting skills - Simon Willison](https://simonwillison.net/2025/Dec/12/openai-skills/)
- [Agent Skills: Anthropic's Next Bid to Define AI Standards - The New Stack](https://thenewstack.io/agent-skills-anthropics-next-bid-to-define-ai-standards/)
- [Anthropic publishes Agent Skills as an open standard](https://the-decoder.com/anthropic-publishes-agent-skills-as-an-open-standard-for-ai-platforms/)

**MCP 相关:**
- [Model Context Protocol 官网](https://modelcontextprotocol.io/)
- [Connect Codex to MCP Servers - Docker](https://www.docker.com/blog/connect-codex-to-mcp-servers-mcp-toolkit/)
- [Best MCP Servers for Claude Code - MCPcat](https://mcpcat.io/guides/best-mcp-servers-for-claude-code/)
- [Configuring MCP Tools in Claude Code - Scott Spence](https://scottspence.com/posts/configuring-mcp-tools-in-claude-code/)

### Skill 市场

- [SkillsMP](https://skillsmp.com/) - 跨平台 skill 市场（25,000+ skills）
- [Claude Plugins](https://claude-plugins.dev/) - Claude Code 插件和 skills
- [Agent Skills Marketplace](https://skillsmp.com/) - ChatGPT、Codex、Claude 通用市场

### 社区集合

- [awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills) - Claude Skills 精选列表
- [claude-code-marketplace](https://github.com/netresearch/claude-code-marketplace) - Netresearch 策展的 skills
- [codex-settings](https://github.com/feiskyer/codex-settings) - Codex 配置和 skills 示例

### 博客和分析

- [Claude Code 最佳实践 - Terry Cho](https://medium.com/@terrycho/best-practices-for-maximizing-claude-code-performance-f2d049579563)
- [CLAUDE.md 最佳实践 - Arize](https://arize.com/blog/claude-md-best-practices-learned-from-optimizing-claude-code-with-prompt-learning/)
- [Understanding Claude Code Full Stack - alexop.dev](https://alexop.dev/posts/understanding-claude-code-full-stack/)
- [Claude Code customization guide - alexop.dev](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/)

---

## 研究日期

**研究执行日期：** 2026-01-06

**信息来源：**
- 官方文档（OpenAI、Anthropic）
- GitHub 开源仓库
- 社区博客和教程
- 第三方评测和对比
- Hacker News、Reddit 社区讨论

**研究方法：**
- Web Search（10+ 轮搜索，40+ 来源）
- 官方文档分析
- 社区资源整合
- 交叉验证关键信息

**局限性说明：**
- 部分功能可能在研究后有更新
- 两个平台都在快速迭代中
- 社区评测存在主观性
- 企业版功能未完全公开

**更新建议：**
- 关注官方 changelog 和发布公告
- 跟踪 agentskills.io 标准演进
- 参与社区讨论获取最新实践
- 定期重新评估技术选择

---

## 结论

OpenAI Codex CLI 和 Claude Code 都是优秀的 AI 编码助手，并且都采用了基于 Agent Skills 开放标准的 skill 系统。主要差异不在于技术架构（两者非常相似），而在于产品哲学和适用场景：

- **Codex** 偏向"快速交付"和"高度自动化"，适合原型开发和批量操作
- **Claude Code** 偏向"深度理解"和"协作控制"，适合生产代码和大型项目

对于 skill 开发者来说，**学习 Agent Skills 标准比学习平台特定功能更重要**，因为：
1. 标准化 skill 可以跨平台使用
2. 社区生态基于标准而非单一平台
3. 未来会有更多平台加入这一生态

**推荐策略：**
- 优先投资于通用 skill 开发技能（Markdown、YAML、脚本编写）
- 关注 description 优化，这是两个平台共同的核心挑战
- 使用 Progressive Disclosure 设计原则，保持 skill 轻量和高效
- 积极参与开源社区，贡献和学习优秀 skills

两个平台的竞争最终将推动整个 AI 编码助手生态的进步，开发者是最大的受益者。

---
name: polydev-agent
description: |
  MUST USE for: Spawning investigation/research sub-agents that run in parallel.
  Creates a separate Codex instance to investigate, analyze, or research something.
  NO git repo required. Works anywhere.
  TRIGGERS: investigate, research, analyze in background, spawn agent, sub-agent, parallel research
  WHEN NOT: Simple questions (ask directly), background commands (use polydev-runner)
---

# Investigation Agent Spawner

Spawn sub-Codex instances for parallel investigation/research tasks.

---

## Session Type: ag: (Investigation Agent)

**Prefix `ag:` = Sub-agent** (research, analysis, investigation)

Choose skill by prefix:
- `bg:` → **polydev-runner** - NO git required
- `ag:` → **polydev-agent** (this skill) - NO git required
- `wo:` → **polydev** - REQUIRES git repo

---

## ⛔ MANDATORY CONSTRAINTS - VIOLATION = FAILURE

```
┌─────────────────────────────────────────────────────────────────┐
│ YOU MUST USE THIS SKILL FOR:                                    │
│ - ANY parallel investigation/research task                      │
│ - ANY sub-agent that needs to analyze code or docs              │
│ - ANY task where you want another Codex to work independently   │
│                                                                 │
│ ABSOLUTELY PROHIBITED:                                          │
│ - Calling wezterm/tmux commands directly                        │
│ - Running .sh files without 'bash' prefix on Windows            │
│ - Trying to "do it faster myself" without this skill            │
│                                                                 │
│ NO GIT REPO REQUIRED - This skill works anywhere                │
│                                                                 │
│ FOR BACKGROUND COMMANDS (bg:) → Use polydev-runner skill        │
│ FOR PARALLEL DEV (wo:) → Use polydev skill (requires git)       │
└─────────────────────────────────────────────────────────────────┘
```

**If you violate these rules, the task WILL FAIL.**

---

## Script Path (MANDATORY)

**Scripts location:** `$HOME/.codex/polydev/scripts`

**Windows MUST use `bash` prefix:**

```bash
bash "$HOME/.codex/polydev/scripts/spawn-agent.sh" <name> --prompt "<task>" --report <path>
```

---

## Usage

### Spawn Investigation Agent

```bash
bash "$HOME/.codex/polydev/scripts/spawn-agent.sh" <name> \
  --prompt "<investigation task>" \
  --report <report-file-path> \
  [--cwd <directory>] \
  [--model <sonnet|opus|haiku>]

# Returns: ag:ag-<workspace>:<name>.0
```

### Example

```bash
# Research authentication mechanisms
bash "$HOME/.codex/polydev/scripts/spawn-agent.sh" auth-research \
  --prompt "分析项目的认证机制，找出安全隐患" \
  --report ./.agent-reports/auth-analysis.md

# Get codebase overview
bash "$HOME/.codex/polydev/scripts/spawn-agent.sh" codebase-overview \
  --prompt "给我一个项目结构概述" \
  --report ./.agent-reports/overview.md \
  --model sonnet
```

---

## Monitoring Agent

### Check Status

```bash
bash "$HOME/.codex/polydev/scripts/capture-screen.sh" --session ag:ag-myproject:research.0 --lines 30
```

### Wait for Completion

```bash
bash "$HOME/.codex/polydev/scripts/wait-for-pattern.sh" ag:ag-myproject:research.0 \
  --success "\[AGENT_DONE\]" \
  --timeout 600
```

### Read Report

After agent completes, read the report file specified in `--report`.

### Close Agent

```bash
bash "$HOME/.codex/polydev/scripts/close-session.sh" ag:ag-myproject:research.0
```

---

## Session ID Format

```
ag:<workspace>:<name>.0
|  |          |      |
|  |          |      +-- pane index (always 0)
|  |          +-- agent name
|  +-- workspace (default: ag-<current-dir-name>)
+-- prefix (agent)
```

---

## Agent Behavior

The spawned agent will:
1. Read the prompt
2. Investigate/research the task
3. Write results to the report file
4. Output `[AGENT_DONE]` marker when complete

**Model selection:**
- `sonnet` (default) - Good balance of speed and quality
- `opus` - Highest quality, slower
- `haiku` - Fastest, for simple tasks

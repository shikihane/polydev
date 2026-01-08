---
name: retrace
description: "Search and analyze Claude Code session history. Use when user asks to find past conversations, recall what was done, search for patterns in history, or analyze previous sessions."
---

<CRITICAL>
If the user mentions ANY of these, you MUST use retrace:

- "之前" / "上次" / "以前" / "earlier" / "before" / "previously"
- "记得" / "recall" / "remember" / "what did we"
- "找" / "搜" / "search" / "find" (relating to past work)
- "历史" / "history" / "session" / "conversation"
- "怎么做的" / "how did we" / "what approach"
- "复用" / "reuse" / "similar to what we did"
- References to past debugging, implementations, or solutions

This is NOT optional. If there's even a 10% chance the user is asking about past work, USE RETRACE.
</CRITICAL>

# Retrace - Claude Code Session History Search

Search and analyze your Claude Code conversation history using FTS5 full-text search.

## Mandatory Triggers

**You MUST use retrace when:**

| User Says | Action |
|-----------|--------|
| "我们之前怎么处理 X 的？" | Search for X, analyze results |
| "找一下关于 Y 的讨论" | Search for Y with filters |
| "上次那个 bug 是怎么修的？" | Search "bug fix" + analyze |
| "有没有类似的实现？" | Search pattern + analyze |
| "回顾一下之前的方案" | Search + context retrieval |

## Prerequisites

Before searching, ensure the index is built:

```bash
RETRACE_SCRIPTS="<plugin-path>/scripts"
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto
```

**If index doesn't exist:** Run `retrace-index.py --auto` first. Never tell user "no history available" without checking.

## Quick Reference

### 1. Locate Current Session

```bash
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-locate.py" --json
```

### 2. Search Sessions

```bash
# Basic search
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "error handling"

# Search with filters
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "bug" \
    --type tool_result \
    --limit 10 \
    --level detail

# Get statistics only (minimal tokens)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "token" --level stats

# Get context around a message
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --context <id> --before 5 --after 5
```

### 3. AI-Powered Analysis (Auto-Chunking)

```bash
# 自动分析（小数据<100KB直接处理，大数据自动分片并行）
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "error" --prompt "classify error types"

# JSON 输出（用于进一步处理）
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "query" --prompt "summarize" --json
```

**Auto-chunking behavior (stdin pipe, 1 API turn):**
- Data < 100KB → Single Haiku call (~5-7s)
- Data >= 100KB → Auto-split into ~100KB chunks, parallel (~15-22s/chunk, max 20)

## Search Levels (Token Budget Control)

| Level | Output | Token Cost | Use Case |
|-------|--------|------------|----------|
| `stats` | Counts, distributions | ~50 | Quick overview |
| `list` | ID, timestamp, preview | ~500 | Browse results |
| `detail` | Full preview, file location | ~2000 | Examine matches |
| `full` | Complete message content | Variable | Deep inspection |

**Default workflow: stats → list → detail → full (wide to narrow)**

## Filter Options

| Filter | Example | Description |
|--------|---------|-------------|
| `--type` | `tool_result`, `user`, `assistant` | Message type |
| `--role` | `user`, `assistant` | Speaker role |
| `--tool` | `Bash`, `Edit`, `Read` | Tool used |
| `--project` | `polydev` | Project name (partial match) |
| `--since` | `2025-01-01` | Start date |
| `--until` | `2025-01-07` | End date |

## Red Flags - STOP and Use Retrace

If you catch yourself thinking:

| Thought | Reality |
|---------|---------|
| "I don't know what we did before" | Search retrace first |
| "Let me guess the approach" | Search similar implementations first |
| "User probably doesn't remember" | YOU can search for them |
| "I'll implement from scratch" | Check if similar work exists first |
| "This seems familiar" | IT IS - search for it |

**All of these mean: Use retrace first.**

## Mandatory Analysis Steps

When user asks about past work:

1. **Always search first** - Never say "I don't know" without searching
2. **Use stats level first** - Check if results exist (low token cost)
3. **Narrow down** - Use filters to reduce results
4. **Analyze if needed** - Use Haiku for pattern extraction
5. **Show evidence** - Include relevant snippets in response

## Example Workflows

### Find Past Bug Fixes

```bash
# 1. Quick check - how many results?
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "fix bug" --level stats

# 2. One-step search + analyze (auto-chunks if large)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "fix bug" \
    --prompt "categorize bug types and solutions"
```

### Recall Implementation Patterns

```bash
# Search for specific pattern
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "authentication" \
    --type assistant --level detail

# Get context for interesting results
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --context <id> --before 10
```

### Index Management

```bash
# Build/update index (incremental)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto

# Rebuild from scratch
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --no-incremental

# View statistics
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --stats
```

## Output Formats

All scripts support `--json` flag for machine-readable output.

```bash
# JSON output for further processing
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" --json | jq '.[] | .id'
```

## Notes

- Index is stored at `~/.claude/retrace-index.db`
- Session files are in `~/.claude/projects/<encoded-path>/`
- Sessions auto-delete after 30 days by default
- FTS5 requires SQLite 3.9+ (most systems have this)

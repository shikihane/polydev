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

## Architecture (v2.0)

- **Per-project databases**: Each project has its own index at `~/.claude/projects/<project>/retrace-index.db`
- **Session isolation**: Sessions table with metadata and summaries
- **Shared module**: `retrace_common.py` for common utilities

## Mandatory Triggers

**You MUST use retrace when:**

| User Says | Action |
|-----------|--------|
| "我们之前怎么处理 X 的？" | Search for X, analyze results |
| "找一下关于 Y 的讨论" | Search for Y with filters |
| "上次那个 bug 是怎么修的？" | Search "bug fix" + analyze |
| "有没有类似的实现？" | Search pattern + analyze |
| "回顾一下之前的方案" | Search + context retrieval |
| "回溯这个会话" / "这次聊了什么" | Use retrace-chronicle.py on session |

## Prerequisites

Before searching, ensure the index is built:

```bash
RETRACE_SCRIPTS="<plugin-path>/scripts"
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto
```

**If index doesn't exist:** Run `retrace-index.py --auto` first. Never tell user "no history available" without checking.

## Quick Reference

### 1. List Sessions

```bash
# List all sessions in a project
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --list-sessions --project polydev

# JSON output
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --list-sessions --project polydev --json
```

### 2. Search Sessions

```bash
# Basic search
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "error handling" --project polydev

# Search within a specific session
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "bug" \
    --session <session-id> \
    --level detail

# Get statistics only (minimal tokens)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "token" --level stats --project polydev

# Get context around a message
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --context <id> --before 5 --after 5
```

### 3. AI-Powered Analysis (Auto-Chunking)

```bash
# Search + analyze (auto-chunks if data > 100KB)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "error" --prompt "classify error types" --project polydev

# JSON output
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "query" --prompt "summarize" --json
```

### 4. Session Chronicle (Single Session History Extraction)

Extract key events from a single session with timestamps in TOON format.

```bash
# By session UUID (requires --project to locate file)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --session <uuid> --project polydev

# By direct file path
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --file ~/.claude/projects/<project-dir>/<uuid>.jsonl

# JSON output
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --file <path> --json
```

**Workflow:** First use `--list-sessions` to find session UUID, then use chronicle on specific session.

**Chronicle extracts (TOON format: `time,type,content`):**
- `code`: Code snippets, functions, fixes
- `cmd`: Bash/git/npm commands executed
- `file`: File operations (created/modified/deleted)
- `error`: Error messages and root causes
- `decision`: Technical choices made
- `mistake`: Wrong assumptions, bugs found

**Output example:**
```
@events[time,type,content]
2026-01-06T12:27:48,error,Windows PowerShell runs .sh scripts as file association
2026-01-06T12:30:10,fix,Modified config to use absolute path
2026-01-06T14:10:21,cmd,`git checkout -b feature/auth`
```

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
| `--session` | `<uuid>` | Filter by session ID |
| `--since` | `2025-01-01` | Start date |
| `--until` | `2025-01-07` | End date |

## Script Reference

| Script | Purpose |
|--------|---------|
| `retrace-index.py` | Build/update FTS5 index per project |
| `retrace-search.py` | Search with layered output + session listing |
| `retrace-analyze.py` | Query-based AI analysis |
| `retrace-chronicle.py` | Single session history extraction (TOON format) |
| `retrace_common.py` | Shared utilities |

## Index Management

```bash
# Build/update index for all projects
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto

# Index specific project
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --project polydev

# Rebuild from scratch (no incremental)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --no-incremental

# View statistics
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --stats
```

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

## Output Formats

All scripts support `--json` flag for machine-readable output.

```bash
# JSON output for further processing
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" --json | jq '.[] | .id'
```

## Notes

- Index is stored per-project at `~/.claude/projects/<project>/retrace-index.db`
- Session files are in `~/.claude/projects/<encoded-path>/`
- Sessions auto-delete after 30 days by default
- FTS5 requires SQLite 3.9+ (most systems have this)

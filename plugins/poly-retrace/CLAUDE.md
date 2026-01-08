# CLAUDE.md - Poly-Retrace Plugin

Claude Code session history search and analysis plugin.

## Overview

Poly-retrace enables searching and analyzing Claude Code conversation history using SQLite FTS5 full-text search with BM25 ranking.

## Architecture

```
poly-retrace/
├── .claude-plugin/
│   └── plugin.json         # Plugin manifest
├── scripts/
│   ├── retrace-locate.py   # Locate session files
│   ├── retrace-index.py    # Build FTS5 index
│   ├── retrace-search.py   # Search with layered output
│   └── retrace-analyze.py  # Auto-chunking Haiku analysis
├── skills/
│   └── retrace/            # Main search skill
└── CLAUDE.md               # This file
```

## Critical Rules

### Script Path - MANDATORY

**All scripts must be called via `$RETRACE_SCRIPTS` variable:**

```bash
RETRACE_SCRIPTS="/path/to/poly-retrace/scripts"
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query"
```

### Python Command - Windows Compatibility

```bash
# Always detect Python command first
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
fi
```

### Index Before Search

**Always ensure index exists before searching:**

```bash
# Check and build if needed
if [[ ! -f ~/.claude/retrace-index.db ]]; then
    $PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto
fi
```

## Data Storage

| Item | Location |
|------|----------|
| Session files | `~/.claude/projects/<encoded-path>/*.jsonl` |
| Index database | `~/.claude/retrace-index.db` |

### Path Encoding

Directory paths are encoded: `E:\Heyang3\polydev` → `E-Heyang3-polydev`

## Search Workflow

### Wide-to-Narrow Pattern

Always start with stats, narrow down progressively:

```bash
# 1. Stats - see what exists
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "error" --level stats

# 2. List - browse matches
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "error" --level list --limit 20

# 3. Detail - examine interesting ones
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --ids "1,5,12" --level detail

# 4. Full - get complete content if needed
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --full 5
```

### Token Budget Control

| Level | Approx Tokens | Use Case |
|-------|---------------|----------|
| stats | ~50 | Quick check |
| list | ~500 | Browse results |
| detail | ~2000 | Examine matches |
| full | Variable | Deep inspection |

## Haiku Analysis

Auto-chunking analysis with Haiku (handles any data size):

```bash
# Direct search + analyze (auto-chunks if data > 100KB)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "bug" --prompt "classify bug types"

# JSON output for further processing
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "error" --prompt "summarize" --json
```

**Auto-chunking behavior (stdin pipe, 1 API turn):**
- Data < 100KB → Single Haiku call (~5-7s)
- Data >= 100KB → Split into ~100KB chunks, parallel processing (~15-22s/chunk, max 20 concurrent)

## Script Reference

### retrace-locate.py

```bash
# Find current session
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-locate.py" --json

# Find by session ID
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-locate.py" --session-id <uuid>

# List all projects
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-locate.py" --list

# List project sessions
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-locate.py" --list --project <name>
```

### retrace-index.py

```bash
# Index all projects (incremental)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto

# Index specific project
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --project polydev

# Rebuild from scratch
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --no-incremental

# View stats
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --stats
```

### retrace-search.py

```bash
# Basic search
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query"

# With filters
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" \
    --type tool_result \
    --tool Bash \
    --project polydev \
    --since 2025-01-01 \
    --limit 10

# Get context
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --context <id> --before 5 --after 5

# Full content
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --full <id>
```

### retrace-analyze.py

```bash
# Search and analyze (auto-chunks large data)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "error" --prompt "summarize errors"

# JSON output
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "bug" --prompt "classify" --json
```

**Parameters:**
- `query` (required): Search keyword
- `--prompt`, `-p`: Analysis task (default: "analyze and summarize")
- `--json`: Output JSON format

## Filter Options

| Filter | Values | Description |
|--------|--------|-------------|
| `--type` | `user`, `assistant`, `tool_result` | Message type |
| `--role` | `user`, `assistant` | Speaker role |
| `--tool` | `Bash`, `Edit`, `Read`, etc. | Tool name |
| `--project` | String | Project name (partial match) |
| `--since` | ISO date | Start date |
| `--until` | ISO date | End date |

## Integration with Polydev

Retrace can analyze sub-agent work history:

```bash
# Find all sub-agent sessions in a project
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "worktree" \
    --project polydev --level stats

# Analyze patterns across parallel work
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "blocked" \
    --prompt "summarize sub-agent blocking issues"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "索引数据库不存在" | Run `retrace-index.py --auto` |
| No results | Check filters, try broader search |
| FTS5 not available | Falls back to FTS4 automatically |
| Empty analysis | Check file path, ensure results exist |

# CLAUDE.md - Poly-Retrace Plugin

Claude Code session history search and analysis plugin.

## Overview

Poly-retrace enables searching and analyzing Claude Code conversation history using SQLite FTS5 full-text search with BM25 ranking.

## Architecture (v2.0)

```
poly-retrace/
├── .claude-plugin/
│   └── plugin.json         # Plugin manifest
├── scripts/
│   ├── retrace_common.py   # Shared utilities (search, chunking, haiku)
│   ├── retrace-locate.py   # Locate session files
│   ├── retrace-index.py    # Build FTS5 index (per-project)
│   ├── retrace-search.py   # Search with layered output + sessions
│   ├── retrace-analyze.py  # Query-based analysis
│   └── retrace-chronicle.py # Full history extraction (TOON)
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
# Check project index
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --project <name>
```

## Data Storage (v2.0)

| Item | Location |
|------|----------|
| Session files | `~/.claude/projects/<encoded-path>/*.jsonl` |
| **Index database** | `~/.claude/projects/<encoded-path>/retrace-index.db` |

**Note:** Each project has its own index database (not a single global database).

### Path Encoding

Directory paths are encoded: `C:\Projects\myapp` → `C-Projects-myapp`

## Script Reference

### retrace_common.py (Shared Module)

Provides:
- `search(query, project)` - Search with query
- `search_all(project)` - Get all records
- `get_data_size(json_str)` - Calculate byte size
- `find_claude()` - Locate claude command
- `chunk_by_size(results, max_bytes)` - Split data for parallel processing
- `call_haiku(data, system_prompt, user_prompt, timeout)` - Call Haiku API

### retrace-index.py (v2.0)

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

### retrace-search.py (v2.0)

```bash
# List all sessions
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --list-sessions --project polydev

# Basic search
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" --project polydev

# Search within session
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" --session <uuid>

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
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "error" --prompt "summarize errors" --project polydev

# JSON output
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "bug" --prompt "classify" --json
```

**Parameters:**
- `query` (required): Search keyword
- `--prompt`, `-p`: Analysis task (default: "analyze and summarize")
- `--project`: Project name filter
- `--json`: Output JSON format

### retrace-chronicle.py (NEW)

Full history extraction with strong constraints. Outputs TOON format.

```bash
# Extract all history from project
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --project polydev

# JSON output
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --project polydev --json
```

**Extracts:**
- Code snippets, functions, fixes
- Bash/git/npm commands executed
- File paths (created/modified/deleted)
- Error messages, stack traces
- Technical decisions made
- Mistakes and rework reasons

**Output format (TOON):**
```
@events[time,type,content]
2026-01-07T14:30,code,`def process_data(): ...`
2026-01-07T14:35,cmd,`git checkout -b feature/auth`
2026-01-07T14:40,file,created:src/auth.py
2026-01-07T14:45,error,TypeError: cannot read property 'x' of undefined
```

## Token Budget Control

| Level | Approx Tokens | Use Case |
|-------|---------------|----------|
| stats | ~50 | Quick check |
| list | ~500 | Browse results |
| detail | ~2000 | Examine matches |
| full | Variable | Deep inspection |

## Filter Options

| Filter | Values | Description |
|--------|--------|-------------|
| `--type` | `user`, `assistant`, `tool_result` | Message type |
| `--role` | `user`, `assistant` | Speaker role |
| `--tool` | `Bash`, `Edit`, `Read`, etc. | Tool name |
| `--project` | String | Project name (partial match) |
| `--session` | UUID | Session ID filter |
| `--since` | ISO date | Start date |
| `--until` | ISO date | End date |

## Auto-Chunking Behavior

Both `retrace-analyze.py` and `retrace-chronicle.py` use stdin pipe (1 API turn):
- Data < 100KB → Single Haiku call (~5-7s)
- Data >= 100KB → Split into ~100KB chunks, parallel (~15-22s/chunk, max 20 concurrent)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "索引数据库不存在" | Run `retrace-index.py --auto --project <name>` |
| No results | Check project filter, try broader search |
| FTS5 not available | Falls back to FTS4 automatically |
| Empty analysis | Check file path, ensure results exist |

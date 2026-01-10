---
name: Retrace
description: This skill should be used when the user asks to "find past conversations", "recall what was done", "search history", "look up previous work", "how did we handle X", "what was that implementation", "find similar code", "search session", "analyze conversation history", "recover file", "restore previous version", or mentions terms like "earlier", "before", "previously", "last time", "history", "past work".
version: 0.2.0
---

# Retrace - Claude Code Session History Search

Search and analyze Claude Code conversation history using FTS5 full-text search with BM25 ranking.

## When to Use This Skill

Use retrace when the user asks about:
- Past conversations, previous work, or earlier implementations
- How a specific feature or bug was handled before
- Finding similar implementations or code patterns
- Recovering code that was damaged without git record
- Extracting session chronicles or history summaries

## Architecture

- **Per-project databases**: Each project has its own index at `~/.claude/projects/<project>/retrace-index.db`
- **Session isolation**: Sessions table with metadata and summaries
- **Shared module**: `retrace_common.py` for common utilities

## Core Workflow

1. **Ensure index exists** before searching
2. **List sessions** to find relevant session IDs
3. **Search with layered output** (stats → list → detail → full)
4. **Use chronicle** for single-session history extraction
5. **Use recover** for file version restoration

## Quick Reference

### Ensure Index Exists

```bash
RETRACE_SCRIPTS="<plugin-path>/scripts"
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --project <project>
```

### List Sessions

```bash
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --list-sessions --project <project>
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --list-sessions --project <project> --json
```

### Search Sessions

```bash
# Basic search
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" --project <project>

# With filters
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "bug" --type tool_result --tool Edit --project <project>

# Get context around a message
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --context <id> --before 5 --after 5

# Statistics only
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "query" --level stats --project <project>
```

### AI-Powered Analysis

```bash
# Search and analyze (auto-chunks if data > 100KB)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "error" --prompt "classify error types" --project <project>
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-analyze.py" "query" --prompt "summarize" --json
```

### Session Chronicle

```bash
# Extract all events from a session (TOON format)
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --session <uuid> --project <project>
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --file <path> --json
```

### File Recovery

```bash
# Recover file versions from session
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" --session <uuid> --project <project> --file <path> --output ./recovery
```

## Search Levels

| Level | Output | Token Cost |
|-------|--------|------------|
| `stats` | Counts, distributions | ~50 |
| `list` | ID, timestamp, preview | ~500 |
| `detail` | Full preview, file location | ~2000 |
| `full` | Complete message | Variable |

**Default workflow**: stats → list → detail → full

## Filter Options

| Filter | Example |
|--------|---------|
| `--type` | `tool_result`, `user`, `assistant` |
| `--role` | `user`, `assistant` |
| `--tool` | `Bash`, `Edit`, `Read` |
| `--project` | Project name (partial match) |
| `--session` | Session UUID |
| `--since` | Start date (ISO) |
| `--until` | End date (ISO) |

## Index Management

```bash
# Build/update all project indexes
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto

# Rebuild from scratch
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --auto --no-incremental

# View statistics
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-index.py" --stats
```

## Red Flags - Use Retrace

Stop and search retrace when thinking:
- "What did we do before?" → Search first
- "Similar implementation?" → Find existing code
- "Code was modified without git" → Use recover
- "Need to restore previous version" → Use recover
- "This seems familiar" → Search for it

## Script Reference

| Script | Purpose |
|--------|---------|
| `retrace-index.py` | Build/update FTS5 index |
| `retrace-search.py` | Search with layered output |
| `retrace-analyze.py` | AI-powered analysis |
| `retrace-chronicle.py` | Session history extraction |
| `retrace-recover.py` | File version recovery |

## Additional Resources

### Reference Files

- **`references/architecture.md`** - Detailed architecture and data storage
- **`references/chronicle-format.md`** - TOON format specification for chronicle output
- **`references/recover-guide.md`** - File recovery guide and data source trust levels

### Example Files

- **`examples/search-examples.sh`** - Common search patterns
- **`examples/chronicle-examples.sh`** - Chronicle usage examples
- **`examples/recover-examples.sh`** - Recovery workflow examples

### Scripts

- **`scripts/validate-skill.sh`** - Validate skill structure and configuration

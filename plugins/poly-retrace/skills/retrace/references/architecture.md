# Architecture Reference

## Overview

Retrace v2.0 provides full-text search and analysis capabilities for Claude Code conversation history using SQLite FTS5.

## Data Storage

### Session Files

Location: `~/.claude/projects/<encoded-path>/`

Session files are named by UUID: `<uuid>.jsonl`

Each session file contains Claude Code conversation history with tool usage, file modifications, and AI responses.

### Index Database

Location: `~/.claude/projects/<encoded-path>/retrace-index.db`

Each project has its own dedicated SQLite database containing:
- **Sessions table**: Metadata and summaries
- **FTS5 virtual table**: Full-text search index with BM25 ranking
- **Messages table**: Indexed message content

### Path Encoding

Directory paths are URL-encoded for filesystem safety:

| Original Path | Encoded |
|---------------|---------|
| `C:\Projects\myapp` | `C-Projects-myapp` |
| `/home/user/project` | `home-user-project` |

## Database Schema

### Sessions Table

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    project TEXT,
    created_at TEXT,
    summary TEXT
);
```

### FTS5 Index

```sql
CREATE VIRTUAL TABLE messages_fts USING fts5(
    session_id,
    role,
    type,
    content,
    tool_name,
    tokenize='porter'
);
```

## Session Lifecycle

- **Creation**: New sessions created when Claude Code starts
- **Indexing**: Sessions indexed automatically on first search
- **Retention**: Sessions auto-delete after 30 days (configurable)

## Supported Operations

| Operation | Tool | Description |
|-----------|------|-------------|
| Index | `retrace-index.py` | Build/update FTS5 index |
| Search | `retrace-search.py` | Query with filters |
| Analyze | `retrace-analyze.py` | AI-powered analysis |
| Chronicle | `retrace-chronicle.py` | Extract session events |
| Recover | `retrace-recover.py` | Restore file versions |

## Token Budget Control

When processing large result sets, use layered output:

1. **stats** (~50 tokens): Quick overview, counts
2. **list** (~500 tokens): Browse results, IDs and timestamps
3. **detail** (~2000 tokens): Examine matches, previews
4. **full** (variable): Deep inspection, complete content

## Filter Reference

| Filter | Description |
|--------|-------------|
| `--type` | Message type: `tool_result`, `user`, `assistant` |
| `--role` | Speaker: `user`, `assistant` |
| `--tool` | Tool name: `Bash`, `Edit`, `Read`, `Write` |
| `--project` | Project name (partial match) |
| `--session` | Filter by session UUID |
| `--since` | Start date (ISO 8601) |
| `--until` | End date (ISO 8601) |

## BM25 Ranking

FTS5 uses BM25 for relevance ranking:

- Higher BM25 scores indicate better matches
- Scores are calculated based on term frequency and inverse document frequency
- Use `--level detail` to see BM25 scores for results

## Auto-Chunking

For large data processing (>100KB):

1. Split data into ~100KB chunks
2. Process chunks in parallel (max 20 concurrent)
3. Aggregate results

Typical latency:
- Single chunk (<100KB): ~5-7 seconds
- Multiple chunks: ~15-22 seconds per chunk

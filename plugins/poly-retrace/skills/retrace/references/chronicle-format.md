# Chronicle Format Specification

## Overview

The chronicle command extracts key events from a Claude Code session and outputs them in TOON (Tabular Object Notation) format.

## TOON Format

```
@events[time,type,content]
<timestamp>,<type>,<content>
```

### Event Types

| Type | Description | Example Content |
|------|-------------|-----------------|
| `code` | Code snippets, functions, fixes | `def process(): pass` |
| `cmd` | Bash/git/npm commands | `git checkout -b feature/auth` |
| `file` | File operations | `created:src/auth.py` |
| `error` | Error messages, stack traces | `TypeError: cannot read property 'x'` |
| `decision` | Technical choices | `Choose SQLite over PostgreSQL` |
| `mistake` | Wrong assumptions, bugs | `Forgot to validate input` |

### Timestamp Format

ISO 8601: `YYYY-MM-DDTHH:MM:SS`

Example: `2026-01-06T14:30:00`

## Output Examples

### Basic Chronicle Output

```
@events[time,type,content]
2026-01-06T12:27:48,error,Windows PowerShell runs .sh scripts as file association
2026-01-06T12:30:10,fix,Modified config to use absolute path
2026-01-06T14:10:21,cmd,`git checkout -b feature/auth`
2026-01-06T14:15:33,file,created:src/auth.py
2026-01-06T14:20:45,code,`def authenticate(user): return validate(user)`
2026-01-06T14:25:00,decision,Use JWT for token-based auth
2026-01-06T14:30:22,mistake,Incorrectly assumed user ID was always numeric
```

### JSON Output

Use `--json` flag for structured output:

```json
{
  "session_id": "abc123...",
  "events": [
    {
      "time": "2026-01-06T12:27:48",
      "type": "error",
      "content": "Windows PowerShell runs .sh scripts as file association"
    }
  ]
}
```

## Extraction Logic

Chronicle extracts events based on:

1. **Tool calls**: `Bash` → `cmd` type, `Write` → `code`/`file` type
2. **Error messages**: Parse tool results for error patterns
3. **Decision markers**: Identify "choose", "decide", "select" statements
4. **Mistake indicators**: Detect "oops", "mistake", "wrong", "fix" patterns

## Workflow

1. List sessions to find session UUID
2. Run chronicle on specific session
3. Parse TOON output for analysis

## Use Cases

- Understand session flow
- Identify key decisions
- Find error patterns
- Review code evolution
- Document work done

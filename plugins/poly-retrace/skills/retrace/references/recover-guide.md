# File Recovery Guide

## Overview

The recover command extracts file versions from session history when code was damaged without git record.

## When to Use

Use recover when:
- Code was modified incorrectly and no git record exists
- User asks "recover", "restore", "previous version"
- Code broke after agent modifications without commit
- Need to restore file from session snapshots

## Data Source Trust Levels

### Trusted Sources (100% reliable)

1. **`Write` tool** - Complete file content
2. **`Read` tool** (no offset/limit) - Full file read
3. **`Bash cat file`** - Complete file output

### Skipped Sources (unreliable)

- `Edit` tool - Only diff fragments, cannot verify consistency
- `Bash` with pipes/processing - May modify content
- `Read` with offset/limit - Partial content only

## Recovery Command

```bash
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
    --session <uuid> \
    --project <project> \
    --file <path> \
    --output ./recovery
```

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `--session` | Session UUID to search |
| `--project` | Project name for path resolution |
| `--file` | Relative file path to recover |
| `--output` | Output directory for recovered versions |

## Output Structure

```
./recovery/
├── versions.txt           # Index (TOON format)
├── filename_v001.sh       # Version 1
├── filename_v002.sh       # Version 2
└── ...
```

### versions.txt Format

```
@versions[version,time,tool]
v001,2026-01-06T14:30:00,Write
v002,2026-01-06T15:45:00,Write
```

## Workflow

1. List sessions to find relevant session UUID
2. Identify the file path that needs recovery
3. Run recover command with correct parameters
4. Review recovered versions in output directory
5. Select the correct version to restore

## Error Handling

- **No versions found**: Script exits with error, no fallback to unreliable sources
- **Invalid session**: Error with session not found
- **Invalid path**: Error with file path not in session

## Examples

### Recover a script file

```bash
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev \
    --file "scripts/build.sh" \
    --output ./recovery
```

### Recover multiple versions

Output includes all versions found in session timeline, ordered chronologically.

## Limitations

- Only recovers from `Write`, `Read`, and `Bash cat` operations
- Does not use `Edit` operations (partial/unreliable)
- Session must contain the file operations
- Cannot recover files deleted from session history

#!/bin/bash
# Search Examples for Retrace Skill
# Copy and adapt these patterns for common search scenarios

# Detect Python command (Windows compatibility)
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "Error: Python not found"
    exit 1
fi

RETRACE_SCRIPTS="${RETRACE_SCRIPTS:-$(dirname "$0")/../../scripts}"

# Example 1: Basic Search
# Find all mentions of error handling
echo "=== Example 1: Basic Search ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "error handling" --project polydev

# Example 2: Search with Type Filter
# Find only tool results (tool calls and outputs)
echo "=== Example 2: Type Filter ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "database" --type tool_result --project polydev

# Example 3: Search with Tool Filter
# Find only Edit tool operations
echo "=== Example 3: Tool Filter ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "config" --tool Edit --project polydev

# Example 4: Search Within Specific Session
# Focus search on a single session
echo "=== Example 4: Session Filter ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "API" --session 550e8400-e29b-41d4-a716-446655440000 --level detail

# Example 5: Get Statistics Only
# Quick overview without full results
echo "=== Example 5: Statistics ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "authentication" --level stats --project polydev

# Example 6: Get Context Around a Message
# View messages before and after a specific result
echo "=== Example 6: Context ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --context abc123 --before 3 --after 3

# Example 7: Date Range Filter
# Find discussions within a date range
echo "=== Example 7: Date Range ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "refactor" --since 2025-01-01 --until 2025-01-31 --project polydev

# Example 8: JSON Output for Further Processing
# Machine-readable output for scripting
echo "=== Example 8: JSON Output ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "bug" --project polydev --json | jq '.[] | .id'

# Example 9: List All Sessions
# Get overview of available sessions
echo "=== Example 9: List Sessions ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" --list-sessions --project polydev

# Example 10: Combined Filters
# Multiple filters for precise search
echo "=== Example 10: Combined Filters ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" "migration" \
    --type tool_result \
    --tool Bash \
    --project polydev \
    --since 2025-01-01 \
    --limit 20

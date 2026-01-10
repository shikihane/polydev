#!/bin/bash
# Chronicle Examples for Retrace Skill
# Extract session history in TOON format

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

# Example 1: Basic Chronicle
# Extract all events from a session by UUID
echo "=== Example 1: Basic Chronicle ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev

# Example 2: Chronicle by Direct File Path
# Extract from a session file directly
echo "=== Example 2: By File Path ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --file ~/.claude/projects/polydev/550e8400-e29b-41d4-a716-446655440000.jsonl

# Example 3: JSON Output
# Get structured JSON output for processing
echo "=== Example 3: JSON Output ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --file ~/.claude/projects/polydev/550e8400-e29b-41d4-a716-446655440000.jsonl \
    --json

# Example 4: Filter by Event Type
# Extract only code-related events (post-process)
echo "=== Example 4: Filter Code Events ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev | grep ',code,'

# Example 5: Extract Only Commands
# Find all bash commands executed
echo "=== Example 5: Extract Commands ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev | grep ',cmd,'

# Example 6: Find Errors and Fixes
# Review error handling in session
echo "=== Example 6: Errors and Fixes ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev | grep -E ',(error|fix|mistake),'

# Example 7: Project Chronicle
# Extract all events from project (all sessions)
echo "=== Example 7: Project Chronicle ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" --project polydev

# Example 8: Output to File
# Save chronicle for later review
echo "=== Example 8: Save to File ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev > session_chronicle.txt

# Example 9: Count Event Types
# Get statistics on session activity
echo "=== Example 9: Event Statistics ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev | awk -F',' '{print $2}' | sort | uniq -c

# Example 10: Timeline View
# Create a simple timeline of events
echo "=== Example 10: Timeline ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-chronicle.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev | cut -d',' -f1,2 | head -20

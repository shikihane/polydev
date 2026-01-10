#!/bin/bash
# Recover Examples for Retrace Skill
# Restore file versions from session history

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

# Example 1: Basic Recovery
# Recover all versions of a file from a session
echo "=== Example 1: Basic Recovery ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev \
    --file "src/auth.py" \
    --output ./recovery

# Example 2: Recover Configuration File
# Restore a config file that was accidentally modified
echo "=== Example 2: Recover Config ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev \
    --file "config/settings.json" \
    --output ./config_recovery

# Example 3: Recover Script File
# Restore a shell script that was broken
echo "=== Example 3: Recover Script ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev \
    --file "scripts/deploy.sh" \
    --output ./script_recovery

# Example 4: Check Available Versions
# View the version index before deciding
echo "=== Example 4: Check Versions ==="
cat ./recovery/versions.txt

# Example 5: Recover Multiple Files
# Loop through multiple files (using bash)
echo "=== Example 5: Batch Recovery ==="
for file in "src/main.py" "src/utils.py" "tests/test_main.py"; do
    $PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
        --session 550e8400-e29b-41d4-a716-446655440000 \
        --project polydev \
        --file "$file" \
        --output ./batch_recovery/$(basename "$file")
done

# Example 6: Find Session with File
# First, list sessions to find one containing the file
echo "=== Example 6: Find Session ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" \
    --list-sessions \
    --project polydev

# Example 7: Search for File Operations
# Find which sessions modified a specific file
echo "=== Example 7: Search File History ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-search.py" \
    "src/auth.py" \
    --tool Write \
    --project polydev

# Example 8: Compare Recovered Versions
# Use diff to compare versions
echo "=== Example 8: Compare Versions ==="
diff ./recovery/src_auth_v001.py ./recovery/src_auth_v002.py

# Example 9: Selective Recovery
# Copy only the correct version to restore
echo "=== Example 9: Selective Recovery ==="
cp ./recovery/src_auth_v003.py ./src/auth.py

# Example 10: Recovery with Different Output
# Save to a different location for review
echo "=== Example 10: Review First ==="
$PYTHON_CMD "$RETRACE_SCRIPTS/retrace-recover.py" \
    --session 550e8400-e29b-41d4-a716-446655440000 \
    --project polydev \
    --file "src/auth.py" \
    --output ./review_recovery

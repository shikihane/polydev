#!/bin/bash
# Validate Retrace Skill Structure
# Check that all required files exist and are properly formatted

set -e

SKILL_DIR="$(dirname "$0")/.."
ERRORS=0

echo "=== Retrace Skill Validation ==="
echo ""

# Helper function to check if pattern exists in file
has_pattern() {
    local pattern="$1"
    local file="$2"
    grep -- "$pattern" "$file" > /dev/null 2>&1
}

# Check 1: SKILL.md exists
echo "Checking SKILL.md..."
if [ -f "$SKILL_DIR/SKILL.md" ]; then
    echo "  [OK] SKILL.md exists"

    # Check frontmatter
    if has_pattern "---" "$SKILL_DIR/SKILL.md"; then
        echo "  [OK] Frontmatter present"

        # Check name
        if has_pattern "name:" "$SKILL_DIR/SKILL.md"; then
            echo "  [OK] Name field present"
        else
            echo "  [ERROR] Missing name field"
            ERRORS=$((ERRORS + 1))
        fi

        # Check description
        if has_pattern "description:" "$SKILL_DIR/SKILL.md"; then
            echo "  [OK] Description field present"
        else
            echo "  [ERROR] Missing description field"
            ERRORS=$((ERRORS + 1))
        fi

        # Check version
        if has_pattern "version:" "$SKILL_DIR/SKILL.md"; then
            echo "  [OK] Version field present"
        else
            echo "  [WARN] Missing version field (recommended)"
        fi
    else
        echo "  [ERROR] Frontmatter not found"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  [ERROR] SKILL.md not found"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: References directory
echo ""
echo "Checking references/..."
if [ -d "$SKILL_DIR/references" ]; then
    echo "  [OK] references/ exists"

    # Check referenced files exist
    for ref in architecture.md chronicle-format.md recover-guide.md; do
        if [ -f "$SKILL_DIR/references/$ref" ]; then
            echo "    [OK] $ref"
        else
            echo "    [ERROR] $ref missing"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo "  [ERROR] references/ directory missing"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: Examples directory
echo ""
echo "Checking examples/..."
if [ -d "$SKILL_DIR/examples" ]; then
    echo "  [OK] examples/ exists"

    # Check referenced files exist
    for ex in search-examples.sh chronicle-examples.sh recover-examples.sh; do
        if [ -f "$SKILL_DIR/examples/$ex" ]; then
            echo "    [OK] $ex"
        else
            echo "    [ERROR] $ex missing"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo "  [ERROR] examples/ directory missing"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Scripts directory
echo ""
echo "Checking scripts/..."
if [ -d "$SKILL_DIR/scripts" ]; then
    echo "  [OK] scripts/ exists"

    if [ -f "$SKILL_DIR/scripts/validate-skill.sh" ]; then
        echo "    [OK] validate-skill.sh"
    else
        echo "    [ERROR] validate-skill.sh missing"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  [ERROR] scripts/ directory missing"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: SKILL.md references
echo ""
echo "Checking SKILL.md references..."
if has_pattern "references/architecture.md" "$SKILL_DIR/SKILL.md"; then
    echo "  [OK] References architecture.md"
else
    echo "  [WARN] Not referencing architecture.md"
fi

if has_pattern "references/chronicle-format.md" "$SKILL_DIR/SKILL.md"; then
    echo "  [OK] References chronicle-format.md"
else
    echo "  [WARN] Not referencing chronicle-format.md"
fi

if has_pattern "examples/" "$SKILL_DIR/SKILL.md"; then
    echo "  [OK] References examples/"
else
    echo "  [WARN] Not referencing examples/"
fi

# Summary
echo ""
echo "=== Validation Summary ==="
if [ $ERRORS -eq 0 ]; then
    echo "All critical checks passed!"
    exit 0
else
    echo "Found $ERRORS error(s)"
    exit 1
fi

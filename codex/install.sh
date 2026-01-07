#!/bin/bash
# install.sh - Install polydev for Codex CLI
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.codex/polydev"

echo "Installing polydev for Codex CLI..."

mkdir -p "$DEST"

# Skills -> ~/.codex/skills/ (Codex default location)
mkdir -p "$HOME/.codex/skills"
cp -r "$SCRIPT_DIR/skills/"* "$HOME/.codex/skills/"
echo "  ✅ skills -> ~/.codex/skills/"

# Scripts + Templates -> ~/.codex/polydev/
cp -r "$SCRIPT_DIR/scripts" "$DEST/"
cp -r "$SCRIPT_DIR/templates" "$DEST/"
echo "  ✅ scripts -> $DEST/scripts/"
echo "  ✅ templates -> $DEST/templates/"

echo ""
echo "Done! Scripts installed to: $DEST/scripts"
echo ""
echo "IMPORTANT for Windows: Use 'bash' prefix to run scripts:"
echo "  bash \"\$HOME/.codex/polydev/scripts/list-sessions.sh\""

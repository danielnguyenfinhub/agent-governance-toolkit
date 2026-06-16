#!/bin/bash
# Copyright (c) Microsoft Corporation. Licensed under the MIT License.
#
# install-claude-plugin.sh — install the agt-governance Claude Code plugin
# into your local Claude plugins directory and install its npm dependencies.
#
# This reproduces the manual flow:
#   npm install --prefix ~/.claude/plugins/agt-governance
# but also copies the plugin source from this repo into that directory first,
# so a single command gives you a ready-to-load plugin.
#
# Usage:
#   scripts/install-claude-plugin.sh [TARGET_DIR]
#
#   TARGET_DIR  Optional. Where to install the plugin.
#               Default: $CLAUDE_PLUGIN_DIR, else ~/.claude/plugins/agt-governance
#
# Environment:
#   CLAUDE_PLUGIN_DIR  Overrides the default target directory.
#
# Examples:
#   scripts/install-claude-plugin.sh
#   scripts/install-claude-plugin.sh ~/.claude/plugins/agt-governance
#   CLAUDE_PLUGIN_DIR=/opt/claude/plugins/agt scripts/install-claude-plugin.sh
set -euo pipefail

# Resolve repo root from this script's location (scripts/ lives at the root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_SRC="$REPO_ROOT/agent-governance-claude-code"

TARGET="${1:-${CLAUDE_PLUGIN_DIR:-$HOME/.claude/plugins/agt-governance}}"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: node and npm are required (Node.js 18+). Install them first." >&2
  exit 1
fi

if [ ! -f "$PLUGIN_SRC/package.json" ]; then
  echo "ERROR: plugin source not found at $PLUGIN_SRC" >&2
  echo "       Run this script from a checkout of the agent-governance-toolkit repo." >&2
  exit 1
fi

echo "Installing agt-governance plugin"
echo "  source: $PLUGIN_SRC"
echo "  target: $TARGET"

mkdir -p "$TARGET"

# Copy the plugin source, excluding build/VCS artifacts. Prefer rsync; fall
# back to tar so this works on minimal systems without rsync.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git' \
    --exclude 'node_modules' \
    "$PLUGIN_SRC"/ "$TARGET"/
else
  ( cd "$PLUGIN_SRC" && tar --exclude='.git' --exclude='node_modules' -cf - . ) \
    | ( cd "$TARGET" && tar -xf - )
fi

echo "Installing npm dependencies (production only)..."
npm install --prefix "$TARGET" --omit=dev --no-audit --no-fund

echo
echo "Done. Plugin installed at: $TARGET"
echo "Load it with:"
echo "  claude --plugin-dir \"$TARGET\""

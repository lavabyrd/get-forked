#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

echo "Removing get-forked from $CLAUDE_DIR"

rm -f "$CLAUDE_DIR/scripts/"fork-{this,that,off,queue,doctor}.sh
rm -f "$CLAUDE_DIR/commands/"fork-{this,that,off,queue}.md
rm -f "$CLAUDE_DIR/commands/forking-hell.md"
rm -rf "$CLAUDE_DIR/skills/get-forked"

echo "Removed scripts, commands, and skill."
echo "State file $CLAUDE_DIR/forks.json was NOT removed (delete manually if you want a clean slate)."

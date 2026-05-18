#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

echo "Installing get-forked into $CLAUDE_DIR"

for cmd in tmux jq uuidgen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd" >&2
    echo "Install with: brew install $cmd (or your package manager equivalent)" >&2
    exit 1
  fi
done

mkdir -p "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills/get-forked"

cp "$REPO_DIR/scripts/"*.sh "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"fork-*.sh

cp "$REPO_DIR/commands/"*.md "$CLAUDE_DIR/commands/"
cp "$REPO_DIR/skills/get-forked/SKILL.md" "$CLAUDE_DIR/skills/get-forked/"

[ -f "$CLAUDE_DIR/forks.json" ] || echo '{"sessions":{}}' > "$CLAUDE_DIR/forks.json"

echo ""
echo "How should forks open?"
echo "  session  — new tmux session per fork (most isolated, default)"
echo "  window   — new tmux window in the current session"
echo "  pane     — horizontal split in the current window"
printf "Mode [session]: "
read -r mode_choice
mode_choice="${mode_choice:-session}"
case "$mode_choice" in
  session|window|pane) ;;
  *)
    echo "Unknown mode '$mode_choice', defaulting to 'session'"
    mode_choice=session
    ;;
esac
echo "FORK_MODE=$mode_choice" > "$CLAUDE_DIR/get-forked.conf"

echo ""
echo "Installed:"
echo "  scripts  -> $CLAUDE_DIR/scripts/fork-{this,that,off,queue,doctor}.sh"
echo "  commands -> $CLAUDE_DIR/commands/fork-{this,that,off,queue}.md, forking-hell.md"
echo "  skill    -> $CLAUDE_DIR/skills/get-forked/SKILL.md"
echo "  config   -> $CLAUDE_DIR/get-forked.conf (FORK_MODE=$mode_choice)"
echo "  state    -> $CLAUDE_DIR/forks.json"
echo ""
echo "To change mode later, edit $CLAUDE_DIR/get-forked.conf"
echo "Run /forking-hell in a new Claude Code session to verify."

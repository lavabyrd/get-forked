#!/usr/bin/env bash
set -euo pipefail

name="${1:-}"
if [ -z "$name" ]; then
  echo "Usage: fork-this.sh <name>"
  exit 1
fi

FORK_MODE=session
[ -f ~/.claude/get-forked.conf ] && source ~/.claude/get-forked.conf

[ -f ~/.claude/forks.json ] || echo '{"sessions":{}}' > ~/.claude/forks.json

project_hash=$(pwd | sed 's|/|-|g')
parent_id=$(ls -t ~/.claude/projects/${project_hash}/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl 2>/dev/null)

if [ -z "$parent_id" ]; then
  echo "Could not determine current session ID. Are you in the right directory?"
  exit 1
fi

new_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
ts=$(date -u +%FT%TZ)
current_session=$(tmux display-message -p '#S')

case "$FORK_MODE" in
  session)
    jq --arg id "$new_id" --arg name "$name" --arg parent "$parent_id" \
       --arg cwd "$(pwd)" --arg ts "$ts" --arg win "$current_session" \
       'if .sessions[$parent] == null then
          .sessions[$parent] = {name: $win, parent: null, children: [], created_at: $ts, cwd: $cwd, mode: "session", pane_id: null}
        else . end |
        .sessions[$parent].children += [$id] |
        .sessions[$id] = {name: $name, parent: $parent, children: [], created_at: $ts, cwd: $cwd, mode: "session", pane_id: null}' \
       ~/.claude/forks.json > /tmp/forks.tmp && mv /tmp/forks.tmp ~/.claude/forks.json
    tmux new-session -d -s "$name" -c "$(pwd)" "claude --resume $parent_id --fork-session --session-id $new_id --name $name"
    tmux switch-client -t "$name"
    ;;
  window)
    current_window=$(tmux display-message -p '#W')
    jq --arg id "$new_id" --arg name "$name" --arg parent "$parent_id" \
       --arg cwd "$(pwd)" --arg ts "$ts" --arg win "$current_window" \
       'if .sessions[$parent] == null then
          .sessions[$parent] = {name: $win, parent: null, children: [], created_at: $ts, cwd: $cwd, mode: "session", pane_id: null}
        else . end |
        .sessions[$parent].children += [$id] |
        .sessions[$id] = {name: $name, parent: $parent, children: [], created_at: $ts, cwd: $cwd, mode: "window", pane_id: null}' \
       ~/.claude/forks.json > /tmp/forks.tmp && mv /tmp/forks.tmp ~/.claude/forks.json
    tmux new-window -n "$name" -c "$(pwd)" "claude --resume $parent_id --fork-session --session-id $new_id --name $name"
    ;;
  pane)
    current_pane=$(tmux display-message -p '#{pane_id}')
    pane_id=$(tmux split-window -h -c "$(pwd)" -P -F '#{pane_id}' "claude --resume $parent_id --fork-session --session-id $new_id --name $name")
    jq --arg id "$new_id" --arg name "$name" --arg parent "$parent_id" \
       --arg cwd "$(pwd)" --arg ts "$ts" --arg win "$current_session" \
       --arg parent_pane "$current_pane" --arg pane_id "$pane_id" \
       'if .sessions[$parent] == null then
          .sessions[$parent] = {name: $win, parent: null, children: [], created_at: $ts, cwd: $cwd, mode: "session", pane_id: $parent_pane}
        elif (.sessions[$parent].pane_id == null) then
          .sessions[$parent].pane_id = $parent_pane
        else . end |
        .sessions[$parent].children += [$id] |
        .sessions[$id] = {name: $name, parent: $parent, children: [], created_at: $ts, cwd: $cwd, mode: "pane", pane_id: $pane_id}' \
       ~/.claude/forks.json > /tmp/forks.tmp && mv /tmp/forks.tmp ~/.claude/forks.json
    ;;
esac

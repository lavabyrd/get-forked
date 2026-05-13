#!/usr/bin/env bash
set -euo pipefail

force=false
[ "${1:-}" = "--force" ] && force=true

if [ ! -f ~/.claude/forks.json ]; then
  echo "No fork state file found. Nothing to close."
  exit 1
fi

project_hash=$(pwd | sed 's|/|-|g')
session_id=$(ls -t ~/.claude/projects/${project_hash}/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl 2>/dev/null)

if [ -z "$session_id" ]; then
  echo "Could not determine current session ID."
  exit 1
fi

parent_id=$(jq -r --arg id "$session_id" '.sessions[$id].parent // empty' ~/.claude/forks.json)
parent_name=$(jq -r --arg id "$session_id" \
  'if .sessions[$id].parent then .sessions[.sessions[$id].parent].name else empty end' \
  ~/.claude/forks.json)
current_session=$(tmux display-message -p '#S')

if [ -z "$parent_name" ]; then
  echo "This session has no recorded parent — it may be the root. Not closing."
  exit 1
fi

children=$(jq -r --arg id "$session_id" '.sessions[$id].children | length' ~/.claude/forks.json 2>/dev/null)
if [ "$children" -gt 0 ] 2>/dev/null && [ "$force" = false ]; then
  echo "This fork has $children child fork(s). Use /fork-off --force to kill them all, or close them individually first."
  exit 1
fi

collect_descendants() {
  local id="$1"
  echo "$id"
  local kids
  kids=$(jq -r --arg id "$id" '.sessions[$id].children[]?' ~/.claude/forks.json 2>/dev/null)
  for kid in $kids; do
    collect_descendants "$kid"
  done
}

if [ "$force" = true ] && [ "$children" -gt 0 ]; then
  descendants=$(collect_descendants "$session_id" | tail -n +2)
  for desc_id in $descendants; do
    desc_name=$(jq -r --arg id "$desc_id" '.sessions[$id].name // empty' ~/.claude/forks.json)
    tmux kill-session -t "$desc_name" 2>/dev/null && echo "Killed fork: $desc_name"
  done
  all_ids=$(collect_descendants "$session_id" | tail -n +2 | jq -Rs '[split("\n")[] | select(. != "")]')
  jq --argjson ids "$all_ids" 'reduce $ids[] as $id (.; del(.sessions[$id]))' \
    ~/.claude/forks.json > /tmp/forks.tmp && mv /tmp/forks.tmp ~/.claude/forks.json
fi

jq --arg id "$session_id" --arg parent "$parent_id" \
  'del(.sessions[$id]) |
   if .sessions[$parent] then
     .sessions[$parent].children = [.sessions[$parent].children[] | select(. != $id)]
   else . end' \
  ~/.claude/forks.json > /tmp/forks.tmp && mv /tmp/forks.tmp ~/.claude/forks.json

tmux switch-client -t "$parent_name"
tmux kill-session -t "$current_session"

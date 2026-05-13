#!/usr/bin/env bash

if [ ! -f ~/.claude/forks.json ]; then
  echo "No fork state file found. No forks recorded yet."
  exit 0
fi

project_hash=$(pwd | sed 's|/|-|g')
current_id=$(ls -t ~/.claude/projects/${project_hash}/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl 2>/dev/null)

jq -r --arg current "$current_id" '
  . as $doc |
  def indent(n): " " * n;
  def marker(id): if id == $current then " ◀ current" else "" end;
  def render(id; depth):
    indent(depth * 2) + ($doc.sessions[id].name // id) + " (" + id + ")" + marker(id),
    ($doc.sessions[id].children[] as $child | render($child; depth + 1));
  [$doc.sessions | to_entries[]
    | select(.value.parent == null or (.value.parent as $p | $doc.sessions[$p] == null))
    | .key
  ] | .[] | render(.; 0)
' ~/.claude/forks.json

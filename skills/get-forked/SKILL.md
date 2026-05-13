---
name: get-forked
description: Use when the user wants to fork, branch, or split a Claude Code session into parallel workstreams — including when they run /fork-this, /fork-that, /fork-off, or /fork-queue. Requires tmux.
---

# get-forked

## Overview

Fork the current Claude Code session into a named tmux session, creating parallel workstreams from a shared conversation checkpoint.

## Commands

| Command | What happens |
|---------|-------------|
| `/fork-this [name]` | Fork current session, switch to fork (you become branch B) |
| `/fork-that [name]` | Fork current session, stay here (fork parked in background tmux window) |
| `/fork-off` | Close this fork, return to parent (refuses if children exist) |
| `/fork-queue` | Print the fork tree with names and session IDs |

## State File

`~/.claude/forks.json` tracks all fork relationships:

```json
{
  "sessions": {
    "<uuid>": {
      "name": "thing-a",
      "parent": "<parent-uuid>",
      "children": [],
      "created_at": "2026-05-01T00:00:00Z",
      "cwd": "/path/to/working/dir"
    }
  }
}
```

## Get Current Session ID

```bash
project_hash=$(pwd | sed 's|/|-|g')
session_id=$(ls -t ~/.claude/projects/${project_hash}/*.jsonl | head -1 | xargs basename -s .jsonl)
```

## Implementing Each Command

### /fork-this [name] and /fork-that [name]

```bash
parent_id=$(ls -t ~/.claude/projects/$(pwd | sed 's|/|-|g')/*.jsonl | head -1 | xargs basename -s .jsonl)
new_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
name="${1:-fork-$(date +%s)}"

# Update state file
jq --arg id "$new_id" --arg name "$name" --arg parent "$parent_id" \
   --arg cwd "$(pwd)" --arg ts "$(date -u +%FT%TZ)" \
   '.sessions[$id] = {name: $name, parent: $parent, children: [], created_at: $ts, cwd: $cwd} |
    .sessions[$parent].children += [$id]' \
   ~/.claude/forks.json > /tmp/forks.tmp && mv /tmp/forks.tmp ~/.claude/forks.json

# Spawn fork in new tmux window
tmux new-window -n "$name" \
  "claude --resume $parent_id --fork-session --session-id $new_id --name $name"

# /fork-this only: switch to the new window
tmux select-window -t "$name"   # omit this line for /fork-that
```

**If `~/.claude/forks.json` does not exist**, initialise it first:
```bash
echo '{"sessions":{}}' > ~/.claude/forks.json
```

### /fork-off

```bash
session_id=$(ls -t ~/.claude/projects/$(pwd | sed 's|/|-|g')/*.jsonl | head -1 | xargs basename -s .jsonl)
parent_name=$(jq -r --arg id "$session_id" '.sessions[.sessions[$id].parent].name // empty' ~/.claude/forks.json)

if [ -z "$parent_name" ]; then
  echo "No parent session recorded for this fork."
else
  tmux select-window -t "$parent_name"
fi
```

### /fork-queue

```bash
jq -r '
  . as $doc |
  def indent(n): " " * n;
  def render(id; depth):
    indent(depth * 2) + ($doc.sessions[id].name // id) + " (" + id + ")" ,
    ($doc.sessions[id].children[] as $child | render($child; depth + 1));
  [$doc.sessions | to_entries[]
    | select(.value.parent == null or (.value.parent as $p | $doc.sessions[$p] == null))
    | .key
  ] | .[] | render(.; 0)
' ~/.claude/forks.json
```

## When to Use Which Command

| Situation | Command |
|-----------|---------|
| You want to explore a rabbit hole and follow it | `/fork-this` |
| You want to spawn background/parallel work, stay in current thread | `/fork-that` |
| You're done in this branch, return to main thread | `/fork-off` |
| You've lost track of what's running | `/fork-queue` |

## NEVER

- NEVER fork without a name when running more than one fork — auto-names like `fork-1746123456` are indistinguishable in `/fork-queue` and tmux
- NEVER fork-this when the parent session has pending tool calls in flight — the fork captures mid-execution state and the child resumes in a confused context
- NEVER let two forked sessions write to the same files simultaneously — forks share no awareness of each other and will silently overwrite each other's work
- NEVER assume `/fork-off` closes the fork — it only switches your focus; the fork window stays alive in tmux

## Common Mistakes

- **State file missing**: initialise with `echo '{"sessions":{}}' > ~/.claude/forks.json` before first fork
- **tmux not running**: all commands require an active tmux session; check with `tmux ls`
- **Name collision**: if a tmux window named `$name` already exists, `new-window` will suffix it — use a unique name
- **jq not installed**: required for state management; install via `brew install jq`

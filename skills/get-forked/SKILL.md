---
name: get-forked
description: Use when the user wants to fork, branch, or split a Claude Code session into parallel workstreams — including when they run /fork-this, /fork-that, /fork-off, or /fork-queue. Requires tmux.
---

# get-forked

## Overview

Fork the current Claude Code session into a named tmux context, creating parallel workstreams from a shared conversation checkpoint.

## Commands

| Command | What happens |
|---------|-------------|
| `/fork-this [name]` | Fork current session, switch to fork (you become branch B) |
| `/fork-that [name]` | Fork current session, stay here (fork parked in background) |
| `/fork-off` | Close this fork, return to parent (refuses if children exist) |
| `/fork-queue` | Print the fork tree with names, modes, and session IDs |

## Configuration

Fork mode is set once at install time in `~/.claude/get-forked.conf`:

```bash
FORK_MODE=session   # or: window, pane
```

To change it, edit that file directly. The mode takes effect immediately on the next fork.

| Mode | Opens forks as | Navigate back via |
|------|---------------|-------------------|
| `session` | New tmux session | `tmux switch-client` |
| `window` | New window in current session | `tmux select-window` |
| `pane` | Horizontal split in current window | `tmux select-pane` |

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
      "cwd": "/path/to/working/dir",
      "mode": "session",
      "pane_id": null
    }
  }
}
```

`mode` records how the fork was opened so `/fork-off` can close it correctly regardless of what `FORK_MODE` is set to today. `pane_id` is populated only for pane-mode forks.

## Get Current Session ID

```bash
project_hash=$(pwd | sed 's|/|-|g')
session_id=$(ls -t ~/.claude/projects/${project_hash}/*.jsonl | head -1 | xargs basename -s .jsonl)
```

## Implementing Each Command

### /fork-this [name] and /fork-that [name]

Both scripts read `~/.claude/get-forked.conf` for `FORK_MODE`, then branch:

**session mode:**
```bash
tmux new-session -d -s "$name" -c "$(pwd)" "claude --resume $parent_id --fork-session --session-id $new_id --name $name"
tmux switch-client -t "$name"          # /fork-this only; omit for /fork-that
```

**window mode:**
```bash
tmux new-window -n "$name" -c "$(pwd)" "claude --resume $parent_id ..."   # /fork-this (auto-focuses)
tmux new-window -d -n "$name" -c "$(pwd)" "claude --resume $parent_id ..." # /fork-that (-d = don't switch)
```

**pane mode** (horizontal split):
```bash
# /fork-this — split and stay in new pane (default tmux behaviour)
pane_id=$(tmux split-window -h -c "$(pwd)" -P -F '#{pane_id}' "claude --resume $parent_id ...")

# /fork-that — split but keep focus on current pane
pane_id=$(tmux split-window -h -d -c "$(pwd)" -P -F '#{pane_id}' "claude --resume $parent_id ...")
```

State is always updated with the fork's `mode` and, for pane mode, the new `pane_id`. The parent entry also records its own `pane_id` when first seen in pane mode.

### /fork-off

Reads `mode` from the current session's state entry, then closes accordingly:

```bash
case "$fork_mode" in
  session)
    tmux switch-client -t "$parent_name"
    tmux kill-session -t "$current_session"
    ;;
  window)
    tmux select-window -t ":$parent_name"
    tmux kill-window -t ":$current_window"
    ;;
  pane)
    [ -n "$parent_pane_id" ] && tmux select-pane -t "$parent_pane_id"
    tmux kill-pane -t "$current_pane_id"
    ;;
esac
```

### /fork-queue

Shows the full tree with mode tags:

```
main [session] (abc123) ◀ current
  debug-flaky [window] (def456)
  try-rust [pane] (ghi789)
```

## When to Use Which Command

| Situation | Command |
|-----------|---------|
| You want to explore a rabbit hole and follow it | `/fork-this` |
| You want to spawn background/parallel work, stay in current thread | `/fork-that` |
| You're done in this branch, return to main thread | `/fork-off` |
| You've lost track of what's running | `/fork-queue` |

## NEVER

- NEVER fork without a name when running more than one fork — auto-names like `fork-1746123456` are indistinguishable in `/fork-queue`
- NEVER fork while the parent session has pending tool calls in flight — the fork captures mid-execution state and the child resumes in a confused context
- NEVER let two forked sessions write to the same files simultaneously — forks share no awareness of each other and will silently overwrite each other's work
- NEVER assume `/fork-off` closes the fork — it only switches your focus; in session mode the window stays alive in tmux until killed

## Common Mistakes

- **Config file missing**: defaults to session mode; re-run `install.sh` to write `~/.claude/get-forked.conf`
- **State file missing**: initialise with `echo '{"sessions":{}}' > ~/.claude/forks.json`
- **tmux not running**: all commands require an active tmux session; check with `tmux ls`
- **Name collision**: if a tmux session/window named `$name` already exists, use a unique name
- **jq not installed**: required for state management; install via `brew install jq`

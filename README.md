# get-forked

Fork your Claude Code session into parallel workstreams.

Each fork is a fresh Claude Code process resumed from the parent's conversation checkpoint, running in its own tmux context. Spawn a fork to chase a rabbit hole, kick off background work, or split exploration without losing the main thread.

```
parent
├── refactor-api      ◀ current
│   └── try-async
├── debug-flaky-test
└── docs-pass
```

## Why

Claude Code conversations are linear. Sometimes you want them to branch:

- **Explore a tangent** without polluting the main thread, then drop back where you left off.
- **Kick off parallel work** — let one fork triage PRs while you keep coding in another.
- **A/B different approaches** from a known-good checkpoint and compare the diffs.

`get-forked` wraps `claude --resume --fork-session` with tmux session management and a tiny state file so you can keep track of what's running.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (`claude` CLI on PATH)
- `tmux`
- `jq`
- `uuidgen` (standard on macOS/Linux)

## Install

```bash
git clone https://github.com/lavabyrd/get-forked.git
cd get-forked
./install.sh
```

The installer prompts for your preferred fork mode (see below), then copies:

- `scripts/*.sh` → `~/.claude/scripts/`
- `commands/*.md` → `~/.claude/commands/` (slash commands)
- `skills/get-forked/SKILL.md` → `~/.claude/skills/get-forked/`
- `~/.claude/get-forked.conf` — your chosen mode
- initialises `~/.claude/forks.json` if it doesn't exist

To uninstall: `./uninstall.sh`.

## Fork modes

Forks can open as tmux sessions, windows, or panes. Choose at install time — or edit `~/.claude/get-forked.conf` to change it later.

| Mode | Opens forks as | Best for |
|------|---------------|----------|
| `session` | New tmux session (default) | Fully isolated, separate terminal context |
| `window` | New window in current session | Staying in one session, easy `Ctrl-b n` switching |
| `pane` | Horizontal split in current window | Side-by-side comparison of two approaches |

```bash
# ~/.claude/get-forked.conf
FORK_MODE=window
```

```mermaid
flowchart TD
    conf["~/.claude/get-forked.conf\nFORK_MODE=?"]

    conf -- session --> S["tmux new-session -d -s name"]
    conf -- window  --> W["tmux new-window -n name"]
    conf -- pane    --> P["tmux split-window -h"]

    S --> SF["fork-this: switch-client -t name\nfork-that: stay in current session"]
    W --> WF["fork-this: auto-focuses new window\nfork-that: new-window -d (background)"]
    P --> PF["fork-this: auto-focuses new pane\nfork-that: split-window -d (background)"]

    SF --> SO["fork-off:\nswitch-client → parent\nkill-session current"]
    WF --> WO["fork-off:\nselect-window → parent\nkill-window current"]
    PF --> PO["fork-off:\nselect-pane → parent pane_id\nkill-pane current"]
```

## Commands

| Command | What happens |
|---------|-------------|
| `/fork-this <name>` | Fork and switch to it (you become the fork). |
| `/fork-that <name>` | Fork into the background and stay where you are. |
| `/fork-off` | Close the current fork, switch back to its parent. Refuses if children exist; pass `--force` to recursively kill them. |
| `/fork-queue` | Print the fork tree with modes and current position highlighted. |
| `/forking-hell` | Run diagnostics on the setup (deps, scripts, config, state file, current session). |

Names are required so you can find the fork again in `tmux ls` and `/fork-queue`.

## Examples

### Chase a tangent, then come back

You're deep in a refactor and notice a flaky test. Fork off to investigate without losing context.

```text
You    > /fork-this debug-flaky-test
Claude > Forked to debug-flaky-test — switched to new tmux window.

# ... in the fork, dig into the test, fix it, commit ...

You    > /fork-off
# back in the parent window with the refactor still in progress
```

### Spawn parallel background work

Kick off PR triage in a detached fork while you keep coding.

```text
You    > /fork-that triage-renovate-prs
Claude > Forked to triage-renovate-prs — running in background window. You remain here.

You    > /fork-queue
Claude >
        main [window] ◀ current
        └── triage-renovate-prs [window]

# switch to it later (window mode):
$ tmux select-window -t :triage-renovate-prs
# or (session mode):
$ tmux attach -t triage-renovate-prs
```

### A/B two implementations from the same starting point

```text
You    > /fork-that try-rust
You    > /fork-that try-go
You    > /fork-queue
Claude >
        main [pane] ◀ current
        ├── try-rust [pane]
        └── try-go [pane]
```

Both forks resume from the same conversation checkpoint and diverge from there. Compare diffs at the end.

## Why scripts, not a pure skill

The tmux and jq operations could be written directly into a SKILL.md and Claude would execute them as Bash tool calls. The problem: every Bash tool call requires user approval unless you've explicitly allowed it. Fork operations involve several sequential shell commands, and clicking through approval prompts for each one defeats the point of a fast workflow command.

By pre-installing named scripts into `~/.claude/scripts/`, the slash commands reduce each fork operation to a single `bash ~/.claude/scripts/fork-this.sh` call. You approve that path once in your Claude Code permissions and it runs silently from then on. The SKILL.md still exists — it tells Claude *when* to invoke the commands and how to report results — but the implementation lives in scripts that don't require repeated sign-off.

## How it works

```mermaid
sequenceDiagram
    participant User
    participant Parent as Parent
    participant Script as fork-this.sh
    participant State as ~/.claude/forks.json
    participant Child as Child (new-name)

    User->>Parent: /fork-this new-name
    Parent->>Script: bash fork-this.sh new-name
    Script->>Script: read FORK_MODE from get-forked.conf
    Script->>Script: parent_id = newest *.jsonl in cwd project dir
    Script->>Script: new_id = uuidgen
    Script->>State: record {new_id → parent_id, mode, pane_id}
    Script->>Child: tmux new-session/window/split-window<br/>"claude --resume parent_id --fork-session ..."
    Script->>Parent: switch focus to new context
    Note over Child: Child resumes parent's full transcript,<br/>then diverges from here on.
```

In words:

1. The current session's UUID is the most recent `*.jsonl` under `~/.claude/projects/<cwd-hash>/`.
2. The script reads `FORK_MODE` from `~/.claude/get-forked.conf`, generates a new UUID for the child, records the parent → child relationship (including mode) in `~/.claude/forks.json`, and spawns `claude --resume <parent> --fork-session --session-id <new>` in a new tmux session, window, or pane depending on mode.
3. Because the new process resumes the parent's transcript with `--fork-session`, the child sees the full conversation history at the point of branching, then diverges.

### Which command does what

```mermaid
flowchart LR
    A[I want to...] --> B{follow the<br/>tangent now?}
    B -- yes --> C[/fork-this/]
    B -- no, do it in parallel --> D[/fork-that/]
    A --> E{done in<br/>this fork?}
    E -- yes --> F[/fork-off/]
    A --> G{what's<br/>running?}
    G --> H[/fork-queue/]
    A --> I{something<br/>broken?}
    I --> J[/forking-hell/]
```

## State file

`~/.claude/forks.json` tracks the tree:

```json
{
  "sessions": {
    "<uuid>": {
      "name": "try-rust-rewrite",
      "parent": "<parent-uuid>",
      "children": [],
      "created_at": "2026-05-13T10:00:00Z",
      "cwd": "/path/to/repo",
      "mode": "window",
      "pane_id": null
    }
  }
}
```

`mode` records how each fork was opened so `/fork-off` always knows how to close it, regardless of what `FORK_MODE` is set to today. `pane_id` is populated only for pane-mode forks.

The file is safe to delete — it only powers `/fork-queue` and `/fork-off`'s parent-lookup. Existing tmux sessions keep running.

## Gotchas

- **Pending tool calls**: don't fork while the parent has a tool call mid-flight. The child resumes in a confused state.
- **Same files**: forks share no awareness of each other. Two forks editing the same path will silently overwrite each other.
- **`/fork-off` closes the tmux context** (session/window/pane depending on your mode) but does NOT delete the underlying Claude Code session transcript — that lives on under `~/.claude/projects/`.
- **No tmux = no forks**: all commands require an active tmux session. Start one with `tmux new -s main` before forking.

## Layout

```
get-forked/
├── .claude-plugin/plugin.json   plugin manifest (for `claude --plugin-dir`)
├── scripts/                     bash scripts installed to ~/.claude/scripts/
├── commands/                    slash commands installed to ~/.claude/commands/
├── skills/get-forked/           the SKILL.md that tells Claude how to use them
├── install.sh
├── uninstall.sh
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).

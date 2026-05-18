#!/usr/bin/env bash

PASS="✓"
FAIL="✗"
WARN="!"
ok=true

check() {
  local status="$1" label="$2" detail="$3"
  if [ "$status" = "pass" ]; then
    echo "  $PASS  $label"
  elif [ "$status" = "warn" ]; then
    echo "  $WARN  $label${detail:+: $detail}"
  else
    echo "  $FAIL  $label${detail:+: $detail}"
    ok=false
  fi
}

echo ""
echo "get-forked doctor"
echo "─────────────────"

echo ""
echo "Dependencies"
for cmd in tmux jq uuidgen; do
  if command -v "$cmd" &>/dev/null; then
    check pass "$cmd"
  else
    check fail "$cmd not found"
  fi
done

echo ""
echo "Scripts"
for script in fork-this fork-that fork-off fork-queue; do
  path="$HOME/.claude/scripts/${script}.sh"
  if [ ! -f "$path" ]; then
    check fail "$script.sh missing"
  elif [ ! -x "$path" ]; then
    check fail "$script.sh not executable"
  else
    check pass "$script.sh"
  fi
done

echo ""
echo "Config"
conf="$HOME/.claude/get-forked.conf"
if [ ! -f "$conf" ]; then
  check warn "~/.claude/get-forked.conf not found (defaults to session mode; re-run install.sh to configure)"
else
  mode=$(grep '^FORK_MODE=' "$conf" 2>/dev/null | cut -d= -f2 || true)
  case "$mode" in
    session|window|pane) check pass "FORK_MODE=$mode" ;;
    *) check fail "FORK_MODE='$mode' is invalid (must be session, window, or pane)" ;;
  esac
fi

echo ""
echo "State file"
state="$HOME/.claude/forks.json"
if [ ! -f "$state" ]; then
  check warn "~/.claude/forks.json not found (will be created on first fork)"
else
  if ! jq empty "$state" 2>/dev/null; then
    check fail "~/.claude/forks.json invalid JSON"
  else
    check pass "~/.claude/forks.json valid JSON"

    session_count=$(jq '.sessions | length' "$state")
    check pass "$session_count session(s) recorded"

    orphans=0
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      name=$(echo "$entry" | cut -f1)
      mode=$(echo "$entry" | cut -f2)
      [ -z "$name" ] && continue
      case "$mode" in
        session)
          if ! tmux has-session -t "$name" 2>/dev/null; then
            check warn "orphaned: '$name' [session] in state but no tmux session"
            orphans=$((orphans + 1))
          fi
          ;;
        window)
          if ! tmux list-windows -F '#W' 2>/dev/null | grep -qx "$name"; then
            check warn "orphaned: '$name' [window] in state but no tmux window"
            orphans=$((orphans + 1))
          fi
          ;;
      esac
    done < <(jq -r '.sessions[] | [.name, (.mode // "session")] | @tsv' "$state" 2>/dev/null)
    [ "$orphans" -eq 0 ] && check pass "no orphaned state entries"

    dupes=$(jq -r '[.sessions[].name] | group_by(.) | map(select(length > 1)) | .[] | .[0]' "$state" 2>/dev/null)
    if [ -n "$dupes" ]; then
      while IFS= read -r name; do
        check warn "duplicate name in state: '$name'"
      done <<< "$dupes"
    else
      check pass "no duplicate session names"
    fi
  fi
fi

echo ""
echo "Current session"
project_hash=$(pwd | sed 's|/|-|g')
session_id=$(ls -t "$HOME/.claude/projects/${project_hash}/"*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl 2>/dev/null)
if [ -z "$session_id" ]; then
  check fail "could not detect session ID (is this a Claude Code session directory?)"
else
  check pass "session ID: $session_id"
fi

if [ -n "${TMUX:-}" ]; then
  current_session=$(tmux display-message -p '#S' 2>/dev/null)
  check pass "tmux session: $current_session"
else
  check fail "not inside a tmux session"
fi

echo ""
if [ "$ok" = true ]; then
  echo "  All checks passed."
else
  echo "  One or more checks failed — see above."
fi
echo ""

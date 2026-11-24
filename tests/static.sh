#!/usr/bin/env bash
# Usage: bash tests/static.sh [path...]   (paths limit the existence check; default all)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

command claude plugin validate "$ROOT" --strict >/dev/null || fail "claude plugin validate --strict"

if [ -n "${BONDSMITH_PRIVATE_NAMES:-}" ]; then
  if grep -rniE --exclude-dir=.git --exclude-dir=.smoke -- "$BONDSMITH_PRIVATE_NAMES" "$ROOT"; then
    fail "private names found"
  fi
else
  echo "SKIP: private-name check"
fi

FILES=(
  .claude-plugin/plugin.json .claude-plugin/marketplace.json .gitignore README.md LICENSE
  skills/setup/SKILL.md skills/check/SKILL.md skills/orchestrate/SKILL.md skills/status/SKILL.md
  agents/checker.md
  templates/config.md templates/board.md templates/brief.md templates/start templates/watch
  tests/lib.sh tests/static.sh tests/setup.sh tests/check.sh tests/e2e.sh
)
[ $# -gt 0 ] && FILES=("$@")
for f in "${FILES[@]}"; do [ -e "$ROOT/$f" ] || fail "missing $f"; done

T="$ROOT/templates"
for f in config board; do
  [ "$(head -n1 "$T/$f.md" 2>/dev/null)" = "format: 1" ] || fail "templates/$f.md line 1 is not format: 1"
done
for h in '## Repos' '## Workers' '## Catalogue' \
  'name | path | owns | base | worktree dir | review steps' \
  'worker model | checker model | permission mode | allowed tools | extra settings | max check rounds | orchestrator name | orchestrator model' \
  'file | send when | validate'; do has "$T/config.md" "$h"; done
for h in '## Live' '## Finished'; do has "$T/board.md" "$h"; done
[ "$(count "$T/board.md" 'task | repo | worktree | session | state | round | waiting on | next | updated | notes')" = 2 ] \
  || fail "templates/board.md needs the board columns under both headings"
for h in '## Goal' '## Done when' '## Read first' '## Checked against' \
  '## Facts and decisions' '## Ask first' '## Worker rules' \
  'You never mark the task complete' 'overwrite report.md first' 'Never merge a PR'; do has "$T/brief.md" "$h"; done
[ "$(count "$T/brief.md" '<orchestrator name>')" = 1 ] || fail "templates/brief.md needs <orchestrator name> exactly once"
for h in 'exec claude' '--autocompact 200000' '/bondsmith:orchestrate $task' 'hasTrustDialogAccepted' "plugin_dir='<plugin root>'"; do has "$T/start" "$h"; done
O="$ROOT/skills/orchestrate/SKILL.md"
# Review step markers reach the brief as written; the checker skips (independent) steps.
has "$O" 'copied unchanged, markers such as ` (worker)` and ` (independent)` included'
has "$ROOT/agents/checker.md" 'A step marked `(independent)` you do not run and you return no line for'
has "$ROOT/agents/checker.md" 'tools: Bash, Read, Grep, Glob, Skill'
sh -n "$T/start" || fail "templates/start is not valid sh"
sh -n "$T/watch" || fail "templates/watch is not valid sh"

# watch: fires for a blocked worker the board shows waiting on worker, and
# ignores one waiting on the user or finished.
if command -v jq >/dev/null 2>&1; then
  W="$(mktemp -d)"
  mkdir -p "$W/h/orchestrator" "$W/bin"
  cp "$T/watch" "$W/h/orchestrator/watch"
  awk '{print} /^## Live/ {print_rows=1} /^## Finished/ {done_rows=1}
    print_rows && /^\|---/ {print "| t-1 | h | /x | s | running | 0 | worker | wait | 2026 | |"; print "| t-2 | h | /x | s | needs-user | 0 | user | answer | 2026 | |"; print_rows=0}
    done_rows && /^\|---/ {print "| t-9 | h | /x | s | closed | 0 | worker | - | 2026 | |"; done_rows=0}' "$T/board.md" > "$W/h/orchestrator/board.md"
  printf '#!/bin/sh\ncat "%s/agents.json"\n' "$W" > "$W/bin/claude"; chmod +x "$W/bin/claude"
  watch_for() { # watch_for <agents json>: prints what watch printed within 2 seconds
    echo "$1" > "$W/agents.json"
    PATH="$W/bin:$PATH" sh "$W/h/orchestrator/watch" > "$W/out" & local p=$!
    sleep 2; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; cat "$W/out"
  }
  [ "$(watch_for '[{"name":"t-2","state":"blocked"},{"name":"t-1","state":"blocked"}]')" = "t-1 blocked" ] || fail "watch did not report blocked t-1"
  [ -z "$(watch_for '[{"name":"t-2","state":"blocked"},{"name":"t-9","state":"blocked"},{"name":"t-1","state":"working"}]')" ] \
    || fail "watch fired for a task not waiting on its worker"
  rm -rf "$W"
else
  echo "SKIP: watch behaviour (no jq)"
fi

echo "PASS: static"

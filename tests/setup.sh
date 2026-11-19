#!/usr/bin/env bash
# Drives a real `claude -p` session; costs tokens.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

D="$(mktemp -d)"
D="$(cd "$D" && pwd -P)"
trap 'rm -rf "$D"' EXIT
T="$D/home"
mkdir -p "$T" "$D/api" "$D/mobile"
printf '%s\n' '- api (backend): ../api' '- mobile (app): ../mobile' > "$T/CLAUDE.md"

run_setup() {
  ( cd "$T" && command claude -p --setting-sources project --model sonnet --plugin-dir "$ROOT" \
      --permission-mode acceptEdits "/bondsmith:setup" < /dev/null > "$D/out" 2>&1 ) \
    || { cat "$D/out" >&2; fail "setup session exited non-zero"; }
}

assert_files() {
  local o="$T/orchestrator"
  [ -f "$o/config.md" ] || fail "config.md missing"
  [ -f "$o/board.md" ] || fail "board.md missing"
  [ -d "$o/tasks" ] || fail "tasks/ missing"
  [ "$(head -n1 "$o/config.md")" = "format: 1" ] || fail "config.md line 1"
  [ "$(head -n1 "$o/board.md")" = "format: 1" ] || fail "board.md line 1"
  grep -q '^|.*\.\./api' "$o/config.md" || fail "no Repos row for ../api"
  grep -q '^|.*\.\./mobile' "$o/config.md" || fail "no Repos row for ../mobile"
  grep -q '^| api | \.\./api | .* | HEAD |' "$o/config.md" || fail "api row base is not HEAD (../api has no clone)"
  [ "$(count "$T/CLAUDE.md" '## Orchestrator')" = 1 ] || fail "pointer block count is not 1"
  grep -q '^| home | \. |' "$o/config.md" || fail "home row missing"
  [ "$(count "$T/.gitignore" '.claude/worktrees/')" = 1 ] || fail ".gitignore lacks .claude/worktrees/ exactly once"
  has "$T/CLAUDE.md" '- api (backend): ../api'
  has "$T/CLAUDE.md" '- mobile (app): ../mobile'
  [ -f "$o/start" ] || fail "orchestrator/start missing"
  sh -n "$o/start" || fail "orchestrator/start is not valid sh"
  cmp -s "$o/watch" "$ROOT/templates/watch" || fail "orchestrator/watch is not templates/watch"
  has "$o/start" "plugin_dir='$ROOT'"
  run_start "$T" "$D/args" hello 2> "$D/warn" || fail "orchestrator/start failed"
  arg_has "$D/args" "Bash(sh $T/orchestrator/watch)" || fail "no allow rule for the watch"
  arg_has "$D/args" "Skill(bondsmith:check)" || fail "no allow rule for the check skill"
  arg_after "$D/args" --add-dir "$D/api"
  arg_after "$D/args" --add-dir "$D/mobile"
  arg_after "$D/args" --model fable
  arg_after "$D/args" --name bondsmith
  arg_after "$D/args" --plugin-dir "$ROOT"
  arg_has "$D/args" "Bash(git -C $T worktree *)" || fail "no git rule for the home repo"
  arg_has "$D/args" "Bash(git -C $D/api fetch *)" || fail "no git rule for ../api"
  ! arg_has "$D/args" --settings || fail "start passed --settings with extra settings (none)"
  ! tr '\0' '\n' < "$D/args" | grep -A1 -x -e --add-dir | grep -qxF -- "$T" || fail "start passed --add-dir for the home repo"
  [ "$(tr '\0' '\n' < "$D/args" | tail -n1)" = "/bondsmith:orchestrate hello" ] || fail "start's prompt is not /bondsmith:orchestrate hello"
}

run_setup
assert_files

# Config edits apply at the next start, with no setup run: a path with a space
# is one argument, a missing path is skipped with a warning.
mkdir "$D/my repo"
awk '{print} /^\| home \| \. \|/ {print "| spaced | ../my repo | x | HEAD | wt | none |"; print "| gone | ../gone | x | HEAD | wt | none |"}' \
  "$T/orchestrator/config.md" > "$D/c" && mv "$D/c" "$T/orchestrator/config.md"
run_start "$T" "$D/args" 2> "$D/warn" || fail "orchestrator/start failed after a config edit"
arg_after "$D/args" --add-dir "$D/my repo"
grep -qF 'Repos path ../gone does not exist' "$D/warn" || fail "no warning for a missing Repos path: $(cat "$D/warn")"
if command -v jq >/dev/null 2>&1 && [ -f "$HOME/.claude.json" ]; then
  grep -qF "$D/api is not trusted" "$D/warn" || fail "no warning for untrusted ../api: $(cat "$D/warn")"
fi
# A trusted parent folder hides the trust prompt in a repo under it; say so.
mkdir "$D/fh"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true},"%s":{"hasTrustDialogAccepted":true}}}' "$D" "$T" > "$D/fh/.claude.json"
if command -v jq >/dev/null 2>&1; then
  HOME="$D/fh" run_start "$T" "$D/args" 2> "$D/warn" || fail "orchestrator/start failed with a trusted parent"
  grep -qF "$D/api is not trusted, so workers cannot start in it. claude shows no trust prompt there, because its parent folder $D is trusted." "$D/warn" \
    || fail "no trusted-parent warning for ../api: $(cat "$D/warn")"
  ! grep -qF "$T is not trusted" "$D/warn" || fail "warned about the trusted home repo"
fi

echo 'USER EDIT' >> "$T/orchestrator/config.md"
run_setup
assert_files
has "$T/orchestrator/config.md" 'USER EDIT'

echo "PASS: setup"

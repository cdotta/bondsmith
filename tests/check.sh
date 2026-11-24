#!/usr/bin/env bash
# Drives real `claude -p` sessions with the checker subagent; costs tokens.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# The check skill runs each (independent) step in a general-purpose agent beside
# the checker; no fixture has one, so those runs stay as before.
C="$ROOT/skills/check/SKILL.md"
for h in 'In the same turn, so they run in parallel with the checker, spawn one `general-purpose` agent' \
  'marked ` (independent)`' 'Wait for every result.' \
  'If the report has a PR link, run the step on that PR.' '--detach' 'worktree remove' \
  '- Post nothing anywhere' '- Change no file in the task'"'"'s worktree' '- Run no full test suite.' \
  'Ran as written: yes | no' 'Severities: <the step'"'"'s own scale, highest first>' \
  '- <severity>: <finding> (<file>:<line>) declared | not declared' \
  '- pass: <step> (independent)' '- fail: <step> (independent): <reason>' \
  'did not run it as written' 'a finding of the step'"'"'s top two severities (BLOCKER and MUST-FIX, for example) is `not declared`' \
  'do not fail it' '## <step> (independent)'; do has "$C" "$h"; done
awk '/## Notes/ {n=NR} /## <step> \(independent\)/ {i=NR} END {exit !(n && i > n)}' "$C" || fail "check: independent sections must follow the checker's notes"

D="$(mktemp -d)"
D="$(cd "$D" && pwd -P)"
trap 'rm -rf "$D"' EXIT

git init -q -b main "$D/repo"
git -C "$D/repo" commit -q --allow-empty -m init

# Each case gets its own home, so cases can run at the same time without
# sharing a board. home <name> prints that case's orchestrator directory.
home() { echo "$D/$1/orchestrator"; }

# fixture <name> <answer> <review steps> [ask first]: with [ask first], the
# commit also adds extra.txt, which that Ask first item forbids without a yes.
fixture() {
  local name="$1" answer="$2" steps="$3" ask="${4:-}" wt="$D/repo/wt/$1" H
  H="$(home "$name")"
  git -C "$D/repo" worktree add -q -b "$name" "$wt" main
  echo "$answer" > "$wt/answer.txt"
  git -C "$wt" add answer.txt
  if [ -n "$ask" ]; then echo extra > "$wt/extra.txt"; git -C "$wt" add extra.txt; fi
  git -C "$wt" commit -q -m "add answer"
  mkdir -p "$H/tasks/$name"
  cat > "$H/config.md" <<CFG
format: 1

## Repos

| name | path | owns | base | worktree dir | review steps |
|---|---|---|---|---|---|
| $name | $D/repo | test | main | wt | $steps |

## Workers

| worker model | checker model | permission mode | allowed tools | extra settings | max check rounds | orchestrator name | orchestrator model |
|---|---|---|---|---|---|---|---|
| sonnet | sonnet | acceptEdits | Bash(git *) | (none) | 2 | bondsmith-test | sonnet |

## Catalogue

| file | send when | validate |
|---|---|---|
CFG
  awk -v row="| $name | $name | $wt | 00000000 | ready-for-check | 0 | orchestrator | check | 2026-01-01 00:00 | |" \
    '{print} /^## Live/ {f=1} f && /^\|---/ {print row; f=0}' "$ROOT/templates/board.md" > "$H/board.md"
  cat > "$H/tasks/$name/brief.md" <<BRIEF
# $name: write the answer

## Goal
answer.txt holds the answer.

## Done when
- [ ] \`cat answer.txt\` prints 42

## Read first

## Checked against
- Review steps: $steps

## Facts and decisions
Base: main

## Ask first
$ask
BRIEF
  cat > "$H/tasks/$name/report.md" <<REPORT
Task: $name
State: ready-for-check
Did: wrote answer.txt and committed it.
Evidence: commit $(git -C "$wt" rev-parse --short HEAD)
Reviews: $steps
Done when: cat answer.txt prints 42: met
Next: wait for the check
REPORT
}

# field <name> <n>: column n of the task's board row, trimmed (1 = task)
field() { awk -F'|' -v t="$1" -v n="$(( $2 + 1 ))" '$2 ~ "^ *"t" *$" {gsub(/^ +| +$/, "", $n); print $n; exit}' "$(home "$1")/board.md"; }

# session <name> <out> <prompt>: one claude -p session in the case's home
session() {
  ( cd "$D/$1" && BONDSMITH_WATCH=off command claude -p --setting-sources project --model sonnet --plugin-dir "$ROOT" --add-dir "$D/repo" \
      --permission-mode acceptEdits --allowedTools "Bash(git *)" "Bash(cat *)" "Bash(command claude agents *)" \
      -- "$3" < /dev/null > "$D/$2.out" 2>&1 ) || { cat "$D/$2.out" >&2; fail "$2: session exited non-zero"; }
}

check() {
  local name="$1" wt="$D/repo/wt/$1" head
  head="$(git -C "$wt" rev-parse HEAD)"
  session "$name" "$name" "/bondsmith:check $name"
  [ -z "$(git -C "$wt" status --porcelain)" ] || fail "$name: checker left changes in the worktree"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head" ] || fail "$name: worktree HEAD moved"
  [ -f "$(home "$name")/tasks/$name/check.md" ] || { cat "$D/$name.out" >&2; fail "$name: no check.md"; }
}

verdict() { head -n1 "$(home "$1")/tasks/$1/check.md"; }
expect() { [ "$2" = "$3" ] || { cat "$D/$1.out" >&2; fail "$1: expected '$3', got '$2'"; }; }

case_pass() {
  check pass-1
  expect pass-1 "$(verdict pass-1)" "Verdict: pass"
  expect pass-1 "$(field pass-1 5)" validated
  expect pass-1 "$(field pass-1 6)" 1
}

case_norun() {
  check norun-1
  expect norun-1 "$(verdict norun-1)" "Verdict: fail"
  has "$(home norun-1)/tasks/norun-1/check.md" "could not run"
}

case_fail() {
  check fail-1
  expect fail-1 "$(verdict fail-1)" "Verdict: fail"
  grep -E '^- fail:.*answer\.txt' "$(home fail-1)/tasks/fail-1/check.md" >/dev/null || fail "fail-1: no fail line mentions answer.txt"
  expect fail-1 "$(field fail-1 5)" running
  expect fail-1 "$(field fail-1 6)" 1

  check fail-1
  expect fail-1 "$(field fail-1 5)" needs-user
  expect fail-1 "$(field fail-1 6)" 2

  # The user's answer to a needs-user task goes into the brief and back to running.
  session fail-1 answer "/bondsmith:orchestrate Answer for fail-1: the right answer is 4242, write that."
  grep -qF 4242 "$(home fail-1)/tasks/fail-1/brief.md" || { cat "$D/answer.out" >&2; fail "answer: not written into the brief"; }
  expect answer "$(field fail-1 5)" running
  expect answer "$(field fail-1 6)" 2
}

case_ask() {
  check ask-1
  expect ask-1 "$(verdict ask-1)" "Verdict: fail"
  grep -E '^- ask-first:.*extra\.txt' "$(home ask-1)/tasks/ask-1/check.md" >/dev/null || fail "ask-1: no ask-first line mentions extra.txt"
  expect ask-1 "$(field ask-1 5)" needs-user
  expect ask-1 "$(field ask-1 6)" 1
}

fixture pass-1 42 none
fixture ask-1 42 none "- Adding any file other than answer.txt."
fixture fail-1 41 none
fixture norun-1 42 no-such-plugin:no-such-review

case_pass & p1=$!
case_norun & p2=$!
case_fail & p3=$!
case_ask & p4=$!
rc=0
for p in $p1 $p2 $p3 $p4; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || fail "a case failed; see above"

echo "PASS: check"

#!/usr/bin/env bash
# End to end: orchestrator spawns a real background worker in a worktree of
# this repo (it must be trusted), a second orchestrator checks it. Costs tokens.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

S="$ROOT/.smoke"
H="$S/home/orchestrator"
WT="$S/worktrees/smoke-1"

git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null || fail "this repo has no commit"
! git -C "$ROOT" show-ref -q --verify refs/heads/smoke-1 || fail "branch smoke-1 exists; delete it first"
! git -C "$ROOT" worktree list | grep -q 'smoke-1' || fail "a smoke-1 worktree exists; remove it first"
[ ! -e "$S" ] || fail ".smoke/ exists; remove it first"

# Files under a --plugin-dir are write-protected, and .smoke/home is inside
# this repo, so the sessions load a copy of the plugin from outside it.
P="$(mktemp -d)"
cp -R "$ROOT/.claude-plugin" "$ROOT/skills" "$ROOT/agents" "$ROOT/templates" "$P/"

# board column n (1 = task) of the smoke-1 row, trimmed
field() { awk -F'|' -v n="$(( $1 + 1 ))" '$2 ~ /^ *smoke-1 *$/ {gsub(/^ +| +$/, "", $n); print $n; exit}' "$H/board.md" 2>/dev/null; }

cleanup() {
  # claude stop and rm take the short id, not the board's full session id.
  local id; id="$(command claude agents --json --all 2>/dev/null | jq -r 'first(.[] | select(.name == "smoke-1") | .id) // empty' || true)"
  if [ -n "$id" ]; then
    command claude stop "$id" >/dev/null 2>&1 || true
    command claude rm "$id" >/dev/null 2>&1 || true
  fi
  git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -D smoke-1 >/dev/null 2>&1 || true
  rm -rf "$S" "$P"
}
trap cleanup EXIT

mkdir -p "$H"
echo '# Smoke-test home repo' > "$S/home/CLAUDE.md"
awk -v root="$ROOT" '
  /^\| home \|/ { print "| self | " root " | this plugin | HEAD | .smoke/worktrees | none |"; next }
  /^\| opus \|/ { print "| sonnet | sonnet | acceptEdits | Bash(git *) | (none) | 2 | bondsmith-smoke | sonnet |"; next }
  { print }' "$ROOT/templates/config.md" > "$H/config.md"

( cd "$S/home" && command claude -p --setting-sources project --model sonnet --plugin-dir "$P" --permission-mode acceptEdits \
    "/bondsmith:setup" < /dev/null > "$S/setup.out" 2>&1 ) || { cat "$S/setup.out" >&2; fail "setup"; }
[ -f "$H/start" ] || { cat "$S/setup.out" >&2; fail "setup wrote no orchestrator/start"; }

# The orchestrator runs with exactly the flags the generated start script
# passes: a fake claude on PATH records them, and -- with the prompt is dropped.
run_start "$S/home" "$S/args" 2> "$S/start.err" || fail "orchestrator/start failed"
! grep -q "not trusted" "$S/start.err" || fail "start warned about a trusted repo: $(cat "$S/start.err")"
ARGS=()
while IFS= read -r -d '' a; do [ "$a" = -- ] && break; ARGS+=("$a"); done < "$S/args"
[ "${#ARGS[@]}" -gt 0 ] || fail "orchestrator/start passed no arguments"

# orch [extra allow rule...] -- <prompt>. Extra rules append to --allowedTools,
# which the start template keeps as the last option.
# A -p session waits for its background watch, which never ends, so turn it off.
orch() { ( cd "$S/home" && BONDSMITH_WATCH=off command claude -p --setting-sources project "${ARGS[@]}" "$@" < /dev/null ); }

# Run 1: a new task. The commit is unsigned because a background worker cannot
# reach the runner's signing agent, and it does not inherit environment variables.
orch -- "/bondsmith:orchestrate New task smoke-1 in repo self: create smoke.txt containing the single line ok, and commit it with git -c commit.gpgsign=false commit. Done when: git show HEAD:smoke.txt prints ok." \
  > "$S/run1.out" 2>&1 || { cat "$S/run1.out" >&2; fail "run 1 exited non-zero"; }
B="$H/tasks/smoke-1/brief.md"
[ -f "$B" ] || { cat "$S/run1.out" >&2; fail "no brief"; }
has "$B" '## Worker rules'
has "$B" 'bondsmith-smoke'
lacks "$B" '<orchestrator name>'
has "$B" 'Base: HEAD'
[ "$(field 5)" = running ] || { cat "$S/run1.out" >&2; fail "board state after run 1: '$(field 5)'"; }
[ -n "$(field 4)" ] || fail "board row has no session"
git -C "$ROOT" worktree list | grep -q '\.smoke/worktrees/smoke-1' || fail "no worktree .smoke/worktrees/smoke-1"
command claude agents --json --all | jq -e 'any(.[]; .name == "smoke-1")' >/dev/null || fail "no session named smoke-1"

# Wait for the worker, which reports while no orchestrator runs
R="$H/tasks/smoke-1/report.md"
for _ in $(seq 60); do
  grep -qF 'State: ready-for-check' "$R" 2>/dev/null && break
  sleep 5
done
grep -qF 'State: ready-for-check' "$R" 2>/dev/null \
  || { command claude logs "$(field 4)" >&2 || true; fail "worker did not report ready-for-check in 5 minutes"; }
[ "$(field 5)" = running ] || fail "board changed while no orchestrator ran: '$(field 5)'"
[ "$(git -C "$WT" show HEAD:smoke.txt)" = ok ] || fail "smoke.txt at HEAD is not ok"

# Run 2: a new orchestrator picks up the report and checks it
# The checker's own commands are not in the start script; a user approves them.
orch "Bash(git -C $WT *)" -- "/bondsmith:orchestrate" > "$S/run2.out" 2>&1 || { cat "$S/run2.out" >&2; fail "run 2 exited non-zero"; }
[ "$(head -n1 "$H/tasks/smoke-1/check.md" 2>/dev/null)" = "Verdict: pass" ] || { cat "$S/run2.out" >&2; fail "check.md verdict is not pass"; }
[ "$(field 5)" = validated ] || { cat "$S/run2.out" >&2; fail "board state after run 2: '$(field 5)'"; }

echo "PASS: e2e"

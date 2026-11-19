# Sourced by every test. Callers start with `set -euo pipefail`.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks: $2"; }
lacks() { ! grep -qF -- "$2" "$1" || fail "$1 contains: $2"; }
count() { grep -cF -- "$2" "$1" || true; }

# run_start <home> <argsfile> [task...]: runs <home>/orchestrator/start with a
# fake claude on PATH that records its arguments, NUL-separated, in <argsfile>.
# The script's warnings go to stderr.
run_start() {
  local h="$1" out="$2" bin rc=0; shift 2
  bin="$(mktemp -d)"
  printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\0" "$a"; done > "%s"\n' "$out" > "$bin/claude"
  chmod +x "$bin/claude"
  PATH="$bin:$PATH" sh "$h/orchestrator/start" "$@" < /dev/null || rc=$?
  rm -r "$bin"
  return "$rc"
}
# arg_after <argsfile> <flag> <value>: <value> is recorded right after <flag>
arg_after() { tr '\0' '\n' < "$1" | grep -A1 -x -e "$2" | grep -qxF -- "$3" || fail "start passed no $2 $3"; }
# arg_has <argsfile> <value>: <value> is one of the recorded arguments
arg_has() { tr '\0' '\n' < "$1" | grep -qxF -- "$2"; }

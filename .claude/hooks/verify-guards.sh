#!/usr/bin/env bash
# Stop — refuse to let the turn end while the guard hooks are broken.
# Skips when: no test suite present, no guard file changed since the last green
# run, or this Stop was itself triggered by a previous block (loop guard).
#
# Guards only regress when a guard file changes, so the fingerprint covers
# .claude/hooks/ rather than src/ — this stays silent on ordinary code turns.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(pwd)}
input=$(cat)

# Loop guard: if we already blocked once for this stop, don't block again.
if [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

suite=$root/.claude/hooks/test-guards.sh
[ -x "$suite" ] || exit 0

state_file=$root/.claude/.guard-state
fingerprint=$(
  {
    find "$root/.claude/hooks" -type f -name '*.sh' \
      -printf '%P %s %T@\n' 2>/dev/null | LC_ALL=C sort
  } | sha256sum | cut -d' ' -f1
)

# No guard file changed since the last run that passed.
if [ -f "$state_file" ] && [ "$(cat "$state_file" 2>/dev/null)" = "$fingerprint" ]; then
  exit 0
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT

if "$suite" >"$log" 2>&1; then
  printf '%s' "$fingerprint" >"$state_file"
  exit 0
fi

rm -f "$state_file"
{
  echo "The permission guard hooks are failing their own tests. Fix them before finishing — do not report success."
  echo
  grep -E '^FAIL|^ +[^ ]|passed:' "$log" | grep -vE '^  ok' | head -40
  echo
  echo "(full output: $suite -v)"
} >&2
exit 2

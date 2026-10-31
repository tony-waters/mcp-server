#!/usr/bin/env bash
# Stop — refuse to let the turn end while the test suite is red.
# Skips when: no pom.xml, nothing under src/ changed since the last green run,
# or this Stop was itself triggered by a previous block (loop guard).
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(pwd)}
input=$(cat)

# Loop guard: if we already blocked once for this stop, don't block again.
if [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

[ -f "$root/pom.xml" ] || exit 0
[ -d "$root/src" ] || exit 0

state_file="$root/.claude/.verify-state"
fingerprint=$(
  {
    find "$root/src" "$root/pom.xml" -type f \
      \( -name '*.java' -o -name '*.xml' -o -name '*.properties' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sql' \) \
      -printf '%P %s %T@\n' 2>/dev/null | LC_ALL=C sort
  } | sha256sum | cut -d' ' -f1
)

# Nothing changed since the last run that passed.
if [ -f "$state_file" ] && [ "$(cat "$state_file" 2>/dev/null)" = "$fingerprint" ]; then
  exit 0
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT

if (cd "$root" && ./mvnw -q -DskipITs test) >"$log" 2>&1; then
  printf '%s' "$fingerprint" >"$state_file"
  exit 0
fi

rm -f "$state_file"
{
  echo "./mvnw test failed. Fix the failures before finishing — do not report success."
  echo
  grep -E '^\[ERROR\]|Tests run:|FAIL|expected:|but was:' "$log" | head -40
  echo
  echo "(full output: cd $root && ./mvnw test)"
} >&2
exit 2

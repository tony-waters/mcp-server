#!/usr/bin/env bash
# SessionStart — put the facts worth knowing into context once, cheaply.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(pwd)}
cd "$root" 2>/dev/null || exit 0

lines=()
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) && lines+=("branch: $branch")

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "${dirty:-0}" != "0" ] && lines+=("uncommitted files: $dirty")

if command -v java >/dev/null 2>&1; then
  lines+=("java: $(java -version 2>&1 | head -1)")
fi

if [ ! -f pom.xml ]; then
  lines+=("NOTE: no pom.xml yet — this project has only the Maven wrapper, so build/test hooks will no-op.")
fi

for port in 8080 8081; do
  if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":$port "; then
    lines+=("port $port is already in use — do not start another instance on it")
  fi
done

[ ${#lines[@]} -eq 0 ] && exit 0

ctx=$(printf '%s\n' "${lines[@]}")
jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

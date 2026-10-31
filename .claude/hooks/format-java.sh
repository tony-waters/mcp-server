#!/usr/bin/env bash
# PostToolUse / Edit|Write — format the one file that changed.
# No-ops silently when there is no pom.xml or no formatter configured.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(pwd)}
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[ -z "$file" ] && exit 0
[[ $file == *.java ]] || exit 0
[ -f "$file" ] || exit 0
[ -f "$root/pom.xml" ] || exit 0

if grep -q 'spotless-maven-plugin' "$root/pom.xml" 2>/dev/null; then
  (cd "$root" && ./mvnw -q -o spotless:apply "-DspotlessFiles=${file//\\/\\\\}" 2>/dev/null) || true
elif command -v google-java-format >/dev/null 2>&1; then
  google-java-format --replace "$file" 2>/dev/null || true
fi

exit 0

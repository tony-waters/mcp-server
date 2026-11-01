#!/usr/bin/env bash
# PostToolUse / Edit|Write — run Codacy CLI on the one file that changed.
# Issues are fed back to Claude (exit 2 + stderr) so it fixes them.
# No-ops silently when the Codacy CLI isn't installed or configured.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(pwd)}
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# Only analyze files inside the project, and skip Claude/Codacy config.
case "$file" in
  "$root"/.claude/*|"$root"/.codacy/*|"$root"/target/*) exit 0 ;;
  "$root"/*) ;;
  *) exit 0 ;;
esac

# Prefer the repo-local wrapper (created by `codacy-cli init` / the Codacy MCP),
# fall back to a global install.
if [ -x "$root/.codacy/cli.sh" ]; then
  cli=("$root/.codacy/cli.sh")
elif command -v codacy-cli >/dev/null 2>&1; then
  cli=(codacy-cli)
else
  exit 0
fi
[ -f "$root/.codacy/codacy.yaml" ] || exit 0

rel=${file#"$root"/}
args=(analyze --format sarif)
# Dependency manifests get a vulnerability scan instead of the linters.
case "${rel##*/}" in
  pom.xml|build.gradle|build.gradle.kts|package.json|package-lock.json)
    args+=(--tool trivy) ;;
esac

sarif=$(cd "$root" && "${cli[@]}" "${args[@]}" "$rel" 2>/dev/null) || true
[ -z "$sarif" ] && exit 0

# One line per finding; multi-line messages (e.g. Trivy) are joined, links dropped.
issues=$(printf '%s' "$sarif" | jq -r '
  .runs[]? | (.tool.driver.name // "codacy") as $tool | .results[]? |
  (.message.text // ""
    | split("\n") | map(select(length > 0 and (test("^Link:") | not))) | join("; ")) as $msg |
  "  \(.locations[0].physicalLocation.region.startLine // "?"): [\($tool)/\(.ruleId // "?")] \($msg)"
' 2>/dev/null)

[ -z "$issues" ] && exit 0

count=$(printf '%s\n' "$issues" | grep -c '^  ')
{
  printf 'Codacy found %d issue(s) in %s:\n%s\n' "$count" "$rel" "$issues"
  printf 'Fix these before moving on, or explain why one is a false positive.\n'
} >&2
exit 2

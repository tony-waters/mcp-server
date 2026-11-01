#!/usr/bin/env bash
# PostToolUse / Edit|Write — lint the one file that changed.
#   * shell scripts: ShellCheck (warnings and errors), including .claude/hooks
#   * everything else in the project: Codacy CLI (Trivy for dependency manifests)
# Findings are fed back to Claude (exit 2 + stderr) so it fixes them.
# Each check no-ops silently when its tool isn't installed or configured.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(pwd)}
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# Only files inside the project; never vendored Codacy files or build output.
case "$file" in
  "$root"/.codacy/*|"$root"/target/*) exit 0 ;;
  "$root"/*) ;;
  *) exit 0 ;;
esac
rel=${file#"$root"/}
issues=""

# --- ShellCheck -------------------------------------------------------------
is_shell=false
case "$rel" in
  *.sh|*.bash) is_shell=true ;;
  *) head -n1 "$file" 2>/dev/null | grep -qE '^#!.*\b(ba|da|k)?sh\b' && is_shell=true ;;
esac

if $is_shell && command -v shellcheck >/dev/null 2>&1; then
  sc=$(cd "$root" && shellcheck -x --severity=warning -f json1 "$rel" 2>/dev/null) || true
  if [ -n "$sc" ]; then
    issues+=$(printf '%s' "$sc" | jq -r '
      .comments[]? | "  \(.line): [ShellCheck/SC\(.code)] \(.message)"' 2>/dev/null)
  fi
fi

# --- Codacy CLI -------------------------------------------------------------
# Claude's own config is covered by ShellCheck above, not Codacy.
codacy_ok=true
case "$rel" in .claude/*) codacy_ok=false ;; esac

if $codacy_ok; then
  # Prefer the repo-local wrapper, fall back to a global install.
  if [ -x "$root/.codacy/cli.sh" ]; then
    cli=("$root/.codacy/cli.sh")
  elif command -v codacy-cli >/dev/null 2>&1; then
    cli=(codacy-cli)
  else
    codacy_ok=false
  fi
  [ -f "$root/.codacy/codacy.yaml" ] || codacy_ok=false
fi

if $codacy_ok; then
  args=(analyze --format sarif)
  # Dependency manifests get a vulnerability scan instead of the linters.
  case "${rel##*/}" in
    pom.xml|build.gradle|build.gradle.kts|package.json|package-lock.json)
      args+=(--tool trivy) ;;
  esac

  sarif=$(cd "$root" && "${cli[@]}" "${args[@]}" "$rel" 2>/dev/null) || true
  if [ -n "$sarif" ]; then
    # One line per finding; multi-line messages (e.g. Trivy) are joined, links dropped.
    codacy_issues=$(printf '%s' "$sarif" | jq -r '
      .runs[]? | (.tool.driver.name // "codacy") as $tool | .results[]? |
      (.message.text // ""
        | split("\n") | map(select(length > 0 and (test("^Link:") | not))) | join("; ")) as $msg |
      "  \(.locations[0].physicalLocation.region.startLine // "?"): [\($tool)/\(.ruleId // "?")] \($msg)"
    ' 2>/dev/null)
    [ -n "$codacy_issues" ] && issues+=${issues:+$'\n'}$codacy_issues
  fi
fi

# --- Report -----------------------------------------------------------------
[ -z "$issues" ] && exit 0

count=$(printf '%s\n' "$issues" | grep -c '^  ')
{
  printf 'Found %d issue(s) in %s:\n%s\n' "$count" "$rel" "$issues"
  printf 'Fix these before moving on, or explain why one is a false positive.\n'
} >&2
exit 2

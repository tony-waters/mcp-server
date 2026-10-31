#!/usr/bin/env bash
# PreToolUse / Edit|Write — refuse writes to production config and secret material.
set -uo pipefail

hook_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/protected-paths.sh
. "$hook_dir/lib/protected-paths.sh"

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

if reason=$(protected_reason "$file"); then
  deny "Blocked by .claude/hooks/guard-paths.sh: $reason"
fi

exit 0

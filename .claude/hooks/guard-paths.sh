#!/usr/bin/env bash
# PreToolUse / Edit|Write — refuse writes to production config and secret material.
set -uo pipefail

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

base=${file##*/}

case "$base" in
  application-prod.*|application-prd.*|application-production.*)
    deny "Blocked by .claude/hooks/guard-paths.sh: $base is production configuration. Change it through your deployment pipeline, not from a Claude Code session." ;;
  .env|.env.*)
    deny "Blocked by .claude/hooks/guard-paths.sh: $base holds environment secrets." ;;
  *.jks|*.p12|*.pfx|*.pem|*.key|*.keystore|*.truststore)
    deny "Blocked by .claude/hooks/guard-paths.sh: $base is key or certificate material." ;;
esac

shopt -s nocasematch
if [[ $base == *secret* || $base == *credential* ]]; then
  deny "Blocked by .claude/hooks/guard-paths.sh: $base looks like it holds credentials."
fi
shopt -u nocasematch

exit 0

#!/usr/bin/env bash
# PreToolUse / Bash — refuse release, deploy, history-rewriting and schema-destroying commands.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

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

# Maven lifecycle phases and plugins that publish or destroy.
if [[ $cmd =~ (^|[^[:alnum:]_-])(\./)?mvnw?([^[:alnum:]]|$) ]]; then
  if [[ $cmd =~ ([[:space:]]|^)deploy([[:space:]]|$) ]]; then
    deny "Blocked by .claude/hooks/guard-bash.sh: 'mvn deploy' publishes artifacts. Publish from CI, or run it yourself with '! <command>'."
  fi
  if [[ $cmd =~ release: ]]; then
    deny "Blocked by .claude/hooks/guard-bash.sh: maven-release-plugin tags and pushes. Run a release yourself."
  fi
  if [[ $cmd =~ (flyway:clean|liquibase:dropAll) ]]; then
    deny "Blocked by .claude/hooks/guard-bash.sh: that goal drops every object in the target schema."
  fi
fi

# Git history rewrites and deletions.
if [[ $cmd =~ git[[:space:]] ]]; then
  if [[ $cmd =~ push.*(--force([^-]|$)|--force$|-f([[:space:]]|$)) ]]; then
    deny "Blocked by .claude/hooks/guard-bash.sh: force-push rewrites published history. Use --force-with-lease yourself if you mean it."
  fi
  if [[ $cmd =~ push.*--delete || $cmd =~ push[[:space:]]+[^[:space:]]+[[:space:]]+: ]]; then
    deny "Blocked by .claude/hooks/guard-bash.sh: that deletes a remote branch."
  fi
fi

exit 0

#!/usr/bin/env bash
# Shared protected-path patterns. Sourced by guard-paths.sh (Edit|Write targets)
# and guard-bash.sh (shell redirection, tee, sed -i and dd targets).
#
# protected_reason <path>: prints a reason and returns 0 when the path is
# protected, returns 1 otherwise.

protected_reason() {
  local base=${1##*/}
  [ -z "$base" ] && return 1

  case "$base" in
    application-prod.*|application-prd.*|application-production.*)
      printf '%s is production configuration. Change it through your deployment pipeline, not from a Claude Code session.' "$base"
      return 0 ;;
    .env|.env.*)
      printf '%s holds environment secrets.' "$base"
      return 0 ;;
    *.jks|*.p12|*.pfx|*.pem|*.key|*.keystore|*.truststore)
      printf '%s is key or certificate material.' "$base"
      return 0 ;;
  esac

  local lower=${base,,}
  if [[ $lower == *secret* || $lower == *credential* ]]; then
    printf '%s looks like it holds credentials.' "$base"
    return 0
  fi

  return 1
}

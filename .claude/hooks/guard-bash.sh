#!/usr/bin/env bash
# PreToolUse / Bash — refuse release, deploy, history-rewriting and schema-destroying commands.
set -uo pipefail

hook_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/protected-paths.sh
. "$hook_dir/lib/protected-paths.sh"

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

unquote() {
  local t=$1
  t=${t#[\'\"]}
  t=${t%[\'\"]}
  printf '%s' "$t"
}

# Tokenised form of the command, used by the git, rm and write-target checks.
# Over-matching is deliberate throughout — a false deny is cheaper than a
# leaked secret or a deleted tree.
spaced=$(printf '%s' "$cmd" | sed -E 's/>>?/ & /g; s/\|/ | /g')
read -r -a toks <<< "$spaced"

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
  # A leading '+' on a refspec is a force push by another name.
  if [[ $cmd =~ push ]]; then
    seen_push=0
    for tok in "${toks[@]}"; do
      tok=$(unquote "$tok")
      case "$tok" in
        '|'|';'|'&&'|'||') seen_push=0; continue ;;
        push) seen_push=1; continue ;;
      esac
      [ "$seen_push" -eq 1 ] || continue
      if [[ $tok == +* ]]; then
        deny "Blocked by .claude/hooks/guard-bash.sh: the refspec '$tok' force-pushes — a leading '+' overwrites remote history just as --force does."
      fi
    done
  fi
fi

# Recursive deletes that reach outside the project, and any delete of
# protected material.
if [[ $cmd =~ (^|[^[:alnum:]_.-])rm([[:space:]]|$) ]]; then
  recursive=0
  [[ $cmd =~ rm[[:space:]]+-[[:alnum:]]*[rR] || $cmd =~ rm[[:space:]].*--recursive ]] && recursive=1
  project=${CLAUDE_PROJECT_DIR:-$PWD}

  seen_rm=0
  for tok in "${toks[@]}"; do
    tok=$(unquote "$tok")
    case "$tok" in
      '|'|';'|'&&'|'||') seen_rm=0; continue ;;
      rm|*/rm) seen_rm=1; continue ;;
    esac
    [ "$seen_rm" -eq 1 ] || continue
    [[ $tok == -* ]] && continue

    if reason=$(protected_reason "$tok"); then
      deny "Blocked by .claude/hooks/guard-bash.sh: that deletes $tok. $reason"
    fi

    [ "$recursive" -eq 1 ] || continue

    case "$tok" in
      /|'/*'|'~'|'~/'|'*'|.|./|..|../)
        deny "Blocked by .claude/hooks/guard-bash.sh: refusing to recursively delete '$tok'." ;;
    esac

    # An unexpanded variable that resolves to empty turns 'rm -rf $DIR/' into
    # 'rm -rf /'. Hooks see the command before the shell expands it, so the
    # value cannot be checked here.
    if [[ $tok == *'$'* ]]; then
      deny "Blocked by .claude/hooks/guard-bash.sh: recursive delete of '$tok' depends on a variable this hook cannot resolve. Expand it yourself, or run the command with '! <command>'."
    fi

    if [[ $tok == /* ]]; then
      case "$tok" in
        "$project"|"$project"/*|/tmp/*|/var/tmp/*) : ;;
        *) deny "Blocked by .claude/hooks/guard-bash.sh: '$tok' is outside the project directory." ;;
      esac
    fi
  done
fi

sed_inplace=0
[[ $cmd =~ sed[[:space:]]+(-[[:alnum:]]*i|--in-place) ]] && sed_inplace=1

collecting=0
for ((i = 0; i < ${#toks[@]}; i++)); do
  tok=$(unquote "${toks[i]}")

  case "$tok" in
    '>'|'>>')
      next=$(unquote "${toks[i + 1]-}")
      if reason=$(protected_reason "$next"); then
        deny "Blocked by .claude/hooks/guard-bash.sh: that redirects output into $next. $reason"
      fi
      continue ;;
    tee|dd)
      collecting=1
      continue ;;
    sed)
      [ "$sed_inplace" -eq 1 ] && collecting=1
      continue ;;
    '|'|';'|'&&'|'||')
      collecting=0
      continue ;;
  esac

  [ "$collecting" -eq 1 ] || continue
  [[ $tok == -* ]] && continue

  target=${tok#of=}
  if reason=$(protected_reason "$target"); then
    deny "Blocked by .claude/hooks/guard-bash.sh: that writes to $target. $reason"
  fi
done

exit 0

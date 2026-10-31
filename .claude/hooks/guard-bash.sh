#!/usr/bin/env bash
# PreToolUse / Bash — refuse release, deploy, history-rewriting and schema-destroying commands.
#
# Checks are scoped to the command actually being run, not to the raw command
# string, so a command that merely *mentions* a blocked pattern (in a heredoc
# body, a commit message, an echo) is not blocked. Two passes make that work:
#
#   1. Heredoc bodies and trailing comments are stripped — they are data.
#   2. The rest is split into pipeline segments, and each segment's checks are
#      chosen by its own command name. Leading env assignments and wrappers
#      (sudo, xargs, bash -c, ...) are peeled off first so they cannot hide
#      the real command.
#
# Redirection targets are still checked on every segment regardless of command.
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

# Drop heredoc bodies, keeping each line up to the '<<' operator so that any
# redirection on that line is still seen. Handles <<TAG, <<-TAG and quoted
# tags; leaves herestrings (<<<) alone.
strip_heredocs() {
  awk '
    BEGIN { tag = "" }
    {
      if (tag != "") {
        probe = $0
        gsub(/^[ \t]+|[ \t]+$/, "", probe)
        if (probe == tag) { tag = "" }
        next
      }
      sub(/[ \t]#[^\047\042]*$/, "")
      if (match($0, /<<-?[ \t]*[\047\042]?[A-Za-z_][A-Za-z0-9_]*[\047\042]?/)) {
        found = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", found)
        gsub(/[\047\042]/, "", found)
        tag = found
        print substr($0, 1, RSTART - 1)
        next
      }
      print
    }
  '
}

# Env assignments and wrappers that precede the real command.
is_assignment() { [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; }
is_wrapper() {
  case "${1##*/}" in
    sudo|doas|env|nohup|time|command|exec|xargs|bash|sh|zsh|dash|ksh) return 0 ;;
    *) return 1 ;;
  esac
}

# --- per-command checks -------------------------------------------------------

check_git() {
  local tok subcmd="" skip_next=0

  # The subcommand is the first non-flag argument. Global flags that take a
  # separate value are skipped along with it.
  for tok in "$@"; do
    tok=$(unquote "$tok")
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$tok" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path) skip_next=1; continue ;;
      -*) continue ;;
      *) subcmd=$tok; break ;;
    esac
  done
  [ "$subcmd" = push ] || return 0

  for tok in "$@"; do
    tok=$(unquote "$tok")
    case "$tok" in
      --force|--force=*|-f)
        deny "Blocked by .claude/hooks/guard-bash.sh: force-push rewrites published history. Use --force-with-lease yourself if you mean it." ;;
      --delete)
        deny "Blocked by .claude/hooks/guard-bash.sh: that deletes a remote branch." ;;
      :*)
        deny "Blocked by .claude/hooks/guard-bash.sh: the refspec '$tok' deletes a remote branch." ;;
      +*)
        deny "Blocked by .claude/hooks/guard-bash.sh: the refspec '$tok' force-pushes — a leading '+' overwrites remote history just as --force does." ;;
    esac
  done
}

check_maven() {
  local tok
  for tok in "$@"; do
    tok=$(unquote "$tok")
    case "$tok" in
      deploy)
        deny "Blocked by .claude/hooks/guard-bash.sh: 'mvn deploy' publishes artifacts. Publish from CI, or run it yourself with '! <command>'." ;;
      release:*)
        deny "Blocked by .claude/hooks/guard-bash.sh: maven-release-plugin tags and pushes. Run a release yourself." ;;
      flyway:clean|liquibase:dropAll)
        deny "Blocked by .claude/hooks/guard-bash.sh: that goal drops every object in the target schema." ;;
    esac
  done
}

check_rm() {
  local tok reason recursive=0
  local project=${CLAUDE_PROJECT_DIR:-$PWD}

  for tok in "$@"; do
    tok=$(unquote "$tok")
    [[ $tok == --recursive ]] && recursive=1
    # A short flag cluster containing r/R, e.g. -rf, -fr, -r. Long flags are
    # excluded so --interactive is not read as recursive.
    if [[ $tok == -[!-]* ]] && [[ $tok == *r* || $tok == *R* ]]; then
      recursive=1
    fi
  done

  for tok in "$@"; do
    tok=$(unquote "$tok")
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
}

# Writes that would otherwise bypass the Edit|Write hook: sed -i, tee, dd.
check_write_args() {
  local label=$1 inplace_required=$2
  shift 2
  local tok reason inplace=0

  if [ "$inplace_required" -eq 1 ]; then
    for tok in "$@"; do
      tok=$(unquote "$tok")
      [[ $tok == --in-place || $tok == --in-place=* ]] && inplace=1
      # Short flag cluster containing i, e.g. -i, -ni. Long flags excluded so
      # --expression is not read as in-place.
      if [[ $tok == -[!-]* ]] && [[ $tok == *i* ]]; then
        inplace=1
      fi
    done
    [ "$inplace" -eq 1 ] || return 0
  fi

  for tok in "$@"; do
    tok=$(unquote "$tok")
    [[ $tok == -* ]] && continue
    tok=${tok#of=}
    if reason=$(protected_reason "$tok"); then
      deny "Blocked by .claude/hooks/guard-bash.sh: $label writes to $tok. $reason"
    fi
  done
}

# Redirection targets, checked on every segment whatever the command is.
check_redirects() {
  local -a toks=("$@")
  local i tok next reason
  for ((i = 0; i < ${#toks[@]}; i++)); do
    tok=$(unquote "${toks[i]}")
    case "$tok" in
      '>'|'>>')
        next=$(unquote "${toks[i + 1]-}")
        if reason=$(protected_reason "$next"); then
          deny "Blocked by .claude/hooks/guard-bash.sh: that redirects output into $next. $reason"
        fi ;;
    esac
  done
}

# --- dispatch -----------------------------------------------------------------

# Split into segments on pipes, lists and command substitution so each is
# dispatched on its own command name.
segments=$(
  printf '%s' "$cmd" |
    strip_heredocs |
    sed -E 's/\$\(|`|\|\||&&|\||;|&|\(|\)/\n/g; s/>>?/ & /g'
)

while IFS= read -r segment; do
  [ -z "${segment//[[:space:]]/}" ] && continue
  read -r -a toks <<< "$segment"
  [ "${#toks[@]}" -eq 0 ] && continue

  check_redirects "${toks[@]}"

  # Peel env assignments, wrappers and their flags to find the real command.
  idx=0
  while [ "$idx" -lt "${#toks[@]}" ]; do
    probe=$(unquote "${toks[idx]}")
    if is_assignment "$probe" || is_wrapper "$probe" || [[ $probe == -* ]]; then
      idx=$((idx + 1))
      continue
    fi
    break
  done
  [ "$idx" -lt "${#toks[@]}" ] || continue

  name=$(unquote "${toks[idx]}")
  name=${name##*/}
  args=("${toks[@]:idx+1}")

  case "$name" in
    git)       check_git "${args[@]-}" ;;
    mvn|mvnw)  check_maven "${args[@]-}" ;;
    rm)        check_rm "${args[@]-}" ;;
    sed)       check_write_args "sed -i" 1 "${args[@]-}" ;;
    tee)       check_write_args "tee" 0 "${args[@]-}" ;;
    dd)        check_write_args "dd" 0 "${args[@]-}" ;;
  esac
done <<< "$segments"

exit 0

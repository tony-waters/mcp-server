#!/usr/bin/env bash
# Test suite for the PreToolUse guard hooks (guard-bash.sh, guard-paths.sh).
#
#   .claude/hooks/test-guards.sh          run every case
#   .claude/hooks/test-guards.sh -v       also print the deny reason for each case
#
# Exits non-zero if any case behaves differently from what it asserts, so this
# can run in CI. Add a case here whenever you change a guard.
#
# Note: these hooks match on the raw command string, so a command that merely
# mentions a blocked pattern is blocked too. That is why the cases live in a
# script file — writing them inline in a shell command trips the guards.
set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." || exit 1
project=$PWD
export CLAUDE_PROJECT_DIR=$project
hooks=$project/.claude/hooks

verbose=0
[ "${1-}" = "-v" ] && verbose=1

pass=0
fail=0

# check <DENY|ALLOW> <script> <json key> <payload> <label>
check() {
  local want=$1 script=$2 key=$3 payload=$4 label=$5
  local json out got reason mark

  json=$(jq -n --arg k "$key" --arg v "$payload" '{tool_input: {($k): $v}}')
  out=$(printf '%s' "$json" | "$hooks/$script" 2>&1)
  got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "ALLOW"' 2>/dev/null)
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)

  [ "${got^^}" = "DENY" ] && got=DENY || got=ALLOW

  if [ "$got" = "$want" ]; then
    mark="  ok"
    pass=$((pass + 1))
  else
    mark="FAIL"
    fail=$((fail + 1))
  fi

  printf '%s  want=%-5s got=%-5s %s\n' "$mark" "$want" "$got" "$label"
  if [ -n "$reason" ] && { [ "$mark" = FAIL ] || [ "$verbose" -eq 1 ]; }; then
    printf '        %s\n' "$reason"
  fi
}

# Bash tool cases.
deny_bash()  { check DENY  guard-bash.sh  command "$1" "$2"; }
allow_bash() { check ALLOW guard-bash.sh  command "$1" "$2"; }
# Edit|Write tool cases.
deny_path()  { check DENY  guard-paths.sh file_path "$1" "$2"; }
allow_path() { check ALLOW guard-paths.sh file_path "$1" "$2"; }

echo "== protected paths: Edit|Write =="
deny_path  "$project/.env"                                   ".env"
deny_path  "src/main/resources/application-prod.yml"         "prod profile"
deny_path  "src/main/resources/application-production.yaml"  "production profile"
deny_path  "certs/server.pem"                                "certificate"
deny_path  "src/main/java/Credentials.java"                  "name contains 'credential'"
deny_path  "config/app-secrets.yml"                          "name contains 'secret'"
allow_path "src/main/java/App.java"                          "ordinary source file"
allow_path "src/main/resources/application.yml"              "default profile"
allow_path "src/test/resources/application-test.yml"         "test profile"

echo
echo "== protected paths: writes via Bash =="
deny_bash  "cat > .env"                                      "redirect into .env"
deny_bash  "echo FOO=1 >> .env.local"                        "append to .env.local"
deny_bash  "cat > src/main/resources/application-prod.yml"   "redirect into prod profile"
deny_bash  "sed -i s/a/b/ src/main/resources/application-prod.yml" "sed -i on prod profile"
deny_bash  "sed --in-place s/a/b/ certs/server.pem"          "sed --in-place on certificate"
deny_bash  "echo x | tee config/secrets.yml"                 "tee into secrets.yml"
deny_bash  "dd if=/dev/zero of=certs/server.pem"             "dd of= certificate"
allow_bash "cat > src/main/resources/application.yml"        "redirect into default profile"
allow_bash "sed s/a/b/ src/main/resources/application-prod.yml" "sed without -i does not write"
allow_bash "grep FOO .env.example"                           "reading is not writing"
allow_bash "cat app.yml | grep foo > out.txt"                "pipe then safe redirect"

echo
echo "== maven =="
deny_bash  "./mvnw deploy"                                   "mvn deploy publishes"
deny_bash  "./mvnw release:prepare"                          "release plugin"
deny_bash  "./mvnw flyway:clean"                             "flyway:clean drops schema"
deny_bash  "./mvnw liquibase:dropAll"                        "liquibase:dropAll drops schema"
allow_bash "./mvnw test"                                     "mvn test"
allow_bash "./mvnw clean verify"                             "mvn clean verify"

echo
echo "== git history =="
deny_bash  "git push --force origin main"                    "--force"
deny_bash  "git push -f"                                     "-f"
deny_bash  "git push origin --delete feature"                "delete remote branch"
deny_bash  "git push origin +main"                           "'+' refspec"
deny_bash  "git push origin +refs/heads/main:refs/heads/main" "'+' refspec with colon"
allow_bash "git push --force-with-lease"                     "--force-with-lease is safe"
allow_bash "git push origin main"                            "ordinary push"
allow_bash "git status"                                      "read-only git"

echo
echo "== recursive deletes =="
deny_bash  "rm -rf /"                                        "root"
deny_bash  "rm -rf ~"                                        "home"
deny_bash  "rm -rf ."                                        "cwd"
deny_bash  "rm -rf /etc"                                     "outside project"
deny_bash  "rm -rf /usr/local/lib"                           "outside project"
deny_bash  "rm --recursive /opt/data"                        "long flag, outside project"
deny_bash  'rm -rf $BUILD_DIR/out'                           "unexpanded variable"
deny_bash  "rm .env"                                         "protected file, non-recursive"
allow_bash "rm -rf target"                                   "relative build dir"
allow_bash "rm -rf ./target/classes"                         "relative build subdir"
allow_bash "rm -rf $project/target"                          "absolute path inside project"
allow_bash "rm -rf /tmp/claude-1000/scratch"                 "scratch under /tmp"
allow_bash "rm src/main/java/Old.java"                       "single source file"
allow_bash "npm run build"                                   "'npm' is not 'rm'"


echo "== scoping: mentions are not commands =="
allow_bash 'echo "git push --force origin main"'            "pattern inside echo"
allow_bash "git commit -m 'stop using git push --force'"    "pattern inside commit message"
allow_bash 'grep -r "rm -rf /" .'                           "pattern as a grep needle"
allow_bash 'cat <<EOF
git push --force origin main
rm -rf /
./mvnw deploy
EOF'                                                        "patterns inside heredoc body"
allow_bash 'git commit -F - <<MSG
Document the rm -rf and push --force rules
MSG'                                                        "heredoc body on a real git command"
allow_bash './mvnw test # we never deploy from here'        "pattern in a trailing comment"

echo "== scoping: wrappers do not hide the command =="
deny_bash  'bash -c "git push --force origin main"'          "bash -c"
deny_bash  'sh -c "rm -rf /"'                                "sh -c"
deny_bash  "sudo rm -rf /etc"                                "sudo"
deny_bash  "FOO=1 git push --force"                          "leading env assignment"
deny_bash  "env FOO=1 rm -rf /"                              "env wrapper plus assignment"
deny_bash  "find . -name '*.tmp' | xargs rm -rf /"           "xargs"
deny_bash  'echo hi; git push --force'                       "second segment of a list"
deny_bash  'cd /tmp && ./mvnw deploy'                        "second segment of an and-list"
deny_bash  'result=$(rm -rf /)'                              "inside command substitution"
deny_bash  'cat foo | tee config/secrets.yml'                "piped tee still checked"
allow_bash 'git log --oneline | head -5'                     "piped read-only git"

echo
echo "-------------------------------------"
printf 'passed: %d   failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1

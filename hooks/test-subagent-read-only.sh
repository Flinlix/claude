#!/usr/bin/env bash
# Runs subagent-read-only.sh on tool calls from a helper agent and from the main
# session, and exits non-zero when a call gets the wrong verdict.

set -u

hook_script="$(cd "$(dirname "$0")" && pwd)/subagent-read-only.sh"

# Prints the JSON payload of a tool call; $1 is the agent id, empty for the main
# session.
payload() {
    python3 -I -c '
import json, sys
agent_id, tool_name, command = sys.argv[1:4]
call = {"session_id": "test", "tool_name": tool_name, "tool_input": {"command": command}}
if agent_id:
    call["agent_id"] = agent_id
print(json.dumps(call))
' "$1" "$2" "$3"
}

failures=0
expect() {
    local expected=$1 agent_id=$2 tool_name=$3 command=${4:-} got
    got=$(payload "$agent_id" "$tool_name" "$command" | "$hook_script")
    case "$got" in
        *'"deny"'*) got=refuse ;;
        "") got=allow ;;
        *) got="unexpected output: $got" ;;
    esac
    [ "$got" = "$expected" ] && return 0
    echo "FAIL: $tool_name '$command' from '${agent_id:-main session}': expected $expected, got $got"
    failures=$((failures + 1))
}

# Edit tools and other changing tools inside a helper agent
for tool in Edit Write NotebookEdit Artifact ArtifactData CronCreate SendToProject; do
    expect refuse helper "$tool"
done

# Shell commands inside a helper agent that write
while IFS= read -r command; do
    expect refuse helper Bash "$command"
done <<'EOF'
git commit -m message
git -C /some/repo add file
cd /some/repo && git push
git -c user.name=x commit --amend
rm -rf build
echo text > file
echo text >> file
printf x 2>/dev/null >file
cat file | tee copy
sed -i '' 's/a/b/' file
sed -E -i 's/a/b/' file
perl -pi -e 's/a/b/' file
mv a b
mkdir folder
ls | xargs -0 rm
find . -name '*.tmp' -exec rm {} \;
find . -name '*.tmp' -delete
out=$(touch file)
gh pr create --title x
gh api repos/o/r/issues -f title=x
gh api -X DELETE repos/o/r
curl -X POST https://example.invalid
curl -s -d a=b https://example.invalid
EOF

# Shell commands inside a helper agent that only read
while IFS= read -r command; do
    expect allow helper Bash "$command"
done <<'EOF'
git diff
git log --stat -3
git -C /some/repo show HEAD
git --no-pager branch -a
grep -rn 'rm ' .
grep -rn "git push" design_history.md
sed -n 1,10p file
cat file 2>/dev/null
ls > /dev/null 2>&1
grep '<title>' page.html
grep -E 'a->b' file
awk '$1 > 5' file
find . -name '*.md'
curl -s https://example.invalid
gh pr view 1
EOF

# The main session is never refused, even when its command names agent_id
expect allow "" Edit
expect allow "" Bash "git commit -m message"
expect allow "" Bash "grep '\"agent_id\":\"x\"' file > out"

# A payload the hook cannot read refuses a helper agent's call
no_python=$(mktemp -d)
trap 'rm -rf "$no_python"' EXIT
ln -s "$(command -v cat)" "$no_python/cat"; ln -s "$(command -v bash)" "$no_python/bash"
got=$(payload helper Bash "git diff" | PATH="$no_python" "$hook_script" 2>/dev/null)
case "$got" in
    *'"deny"'*) ;;
    *) echo "FAIL: a helper agent's call passed although its payload could not be read"
       failures=$((failures + 1)) ;;
esac

[ "$failures" -eq 0 ] && echo "subagent read-only: every call gets its verdict"
[ "$failures" -eq 0 ]

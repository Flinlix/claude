#!/usr/bin/env bash
# Runs subagent-read-only.sh on tool calls from a subagent and from the main
# session, and exits non-zero when a call gets the wrong verdict.

set -u

hooks_dir="$(cd "$(dirname "$0")" && pwd)"
hook_script="$hooks_dir/subagent-read-only.sh"

# Prints the JSON payload of a tool call; $1 is the agent id, empty for the main
# session, and $4 the tool's action.
payload() {
    python3 -I -c '
import json, sys
agent_id, tool_name, command, action = sys.argv[1:5]
tool_input = {"command": command}
if action:
    tool_input = {"action": action}
call = {"session_id": "test", "tool_name": tool_name, "tool_input": tool_input}
if agent_id:
    call["agent_id"] = agent_id
print(json.dumps(call))
' "$1" "$2" "$3" "${4:-}"
}

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect() {
    local expected=$1 agent_id=$2 tool_name=$3 command=${4:-} action=${5:-} got
    got=$(payload "$agent_id" "$tool_name" "$command" "$action" | "$hook_script")
    case "$got" in
        *'"deny"'*) got=refuse ;;
        "") got=allow ;;
        *) got="unexpected output: $got" ;;
    esac
    [ "$got" = "$expected" ] ||
        fail "$tool_name '$command$action' from '${agent_id:-main session}': expected $expected, got $got"
}

# Every tool the settings send to the hook, other than the shell, is refused
# inside a subagent.
matcher=$(python3 -I -c '
import json, sys
for entry in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]:
    if any("subagent-read-only.sh" in hook["command"] for hook in entry["hooks"]):
        print(entry["matcher"])
' "$hooks_dir/../settings.json")
[ -n "$matcher" ] || fail "settings.json does not send any tool to the hook"
for tool in $(printf '%s' "$matcher" | tr '|' ' '); do
    [ "$tool" = Bash ] || expect refuse helper "$tool"
done
for tool in Edit Write NotebookEdit EnterWorktree ExitWorktree TaskStop; do
    case "|$matcher|" in
        *"|$tool|"*) ;;
        *) fail "settings.json does not send $tool to the hook" ;;
    esac
done

# Read actions of the artifact tools pass; their other actions are refused.
for tool_action in Artifact:read Artifact:list ArtifactComments:read ArtifactData:get ArtifactData:query; do
    expect allow helper "${tool_action%%:*}" "" "${tool_action#*:}"
done
for tool_action in Artifact:publish Artifact:delete ArtifactComments:reply ArtifactComments:watch ArtifactData:set; do
    expect refuse helper "${tool_action%%:*}" "" "${tool_action#*:}"
done

# Shell commands inside a subagent that write
while IFS= read -r command; do
    expect refuse helper Bash "$command"
done <<'EOF'
git commit -m message
git -C /some/repo add file
git -C "/a b" commit -m x
git --git-dir /x commit
git -p commit
cd /some/repo && git push
git -c user.name=x commit --amend
git fetch
git stash
git stash pop
git branch -D old
git branch newname
git tag v1
git config user.name x
git worktree add ../tree
git remote add origin url
git notes add -m x
git submodule update
rm -rf build
sudo rm x
env rm x
env FOO=1 rm x
nohup rm x
time rm x
timeout 5 rm x
nice rm x
exec rm x
sudo -u root rm x
/bin/rm x
\rm x
{ rm -rf x; }
if true; then rm -rf x; fi
for f in *; do mv $f /tmp; done
! rm x
echo text > file
echo text >> file
echo x>file
cat a>b
echo x > 1.txt
printf x 2>/dev/null >file
sort <in >out
cat file | tee copy
sed -i '' 's/a/b/' file
sed -E -i 's/a/b/' file
sed -i.bak 's/a/b/' file
perl -pi -e 's/a/b/' file
mv a b
mkdir folder
ls | xargs -0 rm
xargs -n 1 rm
find . -name '*.tmp' -exec rm {} \;
find . -name '*.tmp' -delete
out=$(touch file)
gh pr create --title x
gh pr checkout 1
gh repo clone o/r
gh workflow run build
gh api repos/o/r/issues -f title=x
gh api -X DELETE repos/o/r
gh api graphql -f query='mutation { x }'
curl -X POST https://example.invalid
curl -s -d a=b https://example.invalid
curl -dx=1 https://example.invalid
curl --json '{}' https://example.invalid
curl -o out https://example.invalid
curl -sLO https://example.invalid
wget https://example.invalid
brew install x
pip install x
python3 -m pip install x
npm install
EOF

# Shell commands inside a subagent that only read
while IFS= read -r command; do
    expect allow helper Bash "$command"
done <<'EOF'
git diff
git log --stat -3
git -C /some/repo show HEAD
git --no-pager branch -a
git branch
git stash list
git tag -l
git config --get user.name
git remote -v
git worktree list
grep -rn 'rm ' .
grep -rn "git push" design_history.md
sed -n 1,10p file
cat file 2>/dev/null
ls > /dev/null 2>&1
grep '<title>' page.html
grep -E 'a->b' file
awk '$1 > 5' file
awk 'NR > 1' file
find . -name '*.md'
find . -exec grep -l x {} \;
command -v python3 jq
curl -s https://example.invalid
curl -fsSL https://example.invalid
gh pr view 1
gh run view 1 --log
gh api repos/o/r/issues
gh api graphql -f query='query { viewer { login } }'
gh api -X GET search/issues -f q=x
perl -MList::Util -e 'print 1'
EOF

# The main session is never refused, even when its command names agent_id
expect allow "" Edit
expect allow "" Bash "git commit -m message"
expect allow "" Bash "grep '\"agent_id\":\"x\"' file > out"

# A payload the hook cannot read refuses a subagent's call
no_python=$(mktemp -d)
trap 'rm -rf "$no_python"' EXIT
ln -s "$(command -v cat)" "$no_python/cat"; ln -s "$(command -v bash)" "$no_python/bash"
got=$(payload helper Bash "git diff" | PATH="$no_python" "$hook_script" 2>/dev/null)
case "$got" in
    *'"deny"'*) ;;
    *) fail "a subagent's call passed although its payload could not be read" ;;
esac

[ "$failures" -eq 0 ] && echo "subagent read-only: every call gets its verdict"
[ "$failures" -eq 0 ]

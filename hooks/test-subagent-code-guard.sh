#!/usr/bin/env bash
# Runs subagent-code-guard.sh on tool calls from a subagent and from the main
# session against a throwaway repository, and exits non-zero when a call gets
# the wrong verdict.

set -u

hooks_dir="$(cd "$(dirname "$0")" && pwd)"
hook_script="$hooks_dir/subagent-code-guard.sh"

# The fixture lies outside every folder the hook treats as temporary; the hook's
# temporary folder is one inside it.
work=$(mktemp -d /var/tmp/subagent-code-guard-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/build/cache" "$work/repo/sub" "$work/repo/.claude" "$work/plain" "$work/tmp"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
(cd "$work/repo" && git init -q && printf 'build/\n.claude/\nCLAUDE.local.md\n' > .gitignore &&
    echo code > src.py && echo kept > build/kept.txt && git add . && git add -f build/kept.txt &&
    git -c user.email=test@example.invalid -c user.name=test commit -qm first) || exit 1
repo="$work/repo" temp="$work/tmp"

# Prints the JSON payload of a tool call: agent id (empty for the main session),
# tool name, working directory, and the tool_input field and its value.
payload() {
    python3 -I -c '
import json, sys
agent_id, tool_name, cwd, key, value = sys.argv[1:6]
call = {"session_id": "test", "tool_name": tool_name, "cwd": cwd, "tool_input": {key: value}}
if agent_id:
    call["agent_id"] = agent_id
print(json.dumps(call))
' "$@"
}

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect() {
    local expected=$1 agent_id=$2 tool_name=$3 key=$4 value=$5 got
    got=$(payload "$agent_id" "$tool_name" "$repo" "$key" "$value" | TMPDIR="$temp" "$hook_script")
    case "$got" in
        *'could not check'*) got="refuse without a decision" ;;
        *'"deny"'*) got=refuse ;;
        "") got=allow ;;
        *) got="unexpected output: $got" ;;
    esac
    [ "$got" = "$expected" ] ||
        fail "$tool_name '$value' from '${agent_id:-main session}': expected $expected, got $got"
}
shell() { expect "$1" helper Bash command "$2"; }

# Every tool the settings send to the hook is one the hook knows.
matcher=$(python3 -I -c '
import json, sys
for entry in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]:
    if any("subagent-code-guard.sh" in hook["command"] for hook in entry["hooks"]):
        print(entry["matcher"])
' "$hooks_dir/../settings.json")
[ "$matcher" = "Edit|Write|NotebookEdit|Bash|Monitor|Agent|EnterWorktree|ExitWorktree" ] ||
    fail "settings.json sends '$matcher' to the hook"

# File tools inside a subagent
expect refuse helper Edit file_path "$repo/src.py"
expect refuse helper Write file_path "$repo/README.md"
expect refuse helper Write file_path "sub/new.md"
expect refuse helper NotebookEdit notebook_path "$repo/notes.ipynb"
expect refuse helper Write file_path "$work/plain/notes.md"
expect refuse helper Write file_path "$repo/.git/config"
expect refuse helper Write file_path "$repo/.claude/settings.local.json"
expect refuse helper Write file_path "$repo/CLAUDE.local.md"
expect refuse helper Write file_path "$HOME/.claude/agents/x.md"
expect refuse helper Write file_path "$HOME/.claude/state/check-settled-x"
expect refuse helper Monitor command "rm src.py"
expect refuse helper Agent isolation worktree
expect allow helper Agent prompt "review"
expect refuse helper EnterWorktree name tree
expect refuse helper ExitWorktree action remove
expect refuse helper Write file_path "$HOME/.claude/projects/some-project/memory/note.md"
expect allow helper Write file_path "$repo/build/result.json"
expect allow helper Write file_path "$temp/bench.txt"
expect allow helper Write file_path "/tmp/subagent-code-guard-probe"

# Shell commands inside a subagent that change code or documentation
while IFS= read -r command; do shell refuse "$command"; done <<EOF
rm src.py
rm -rf $repo/sub
echo x > notes.md
echo x>notes.md
echo x >> src.py
printf x 2>/dev/null >src.py
sudo rm src.py
sudo -u root rm src.py
env FOO=1 rm src.py
time rm src.py
timeout 5 rm src.py
/bin/rm src.py
\\rm src.py
{ rm src.py; }
if true; then rm src.py; fi
for f in *; do mv \$f $temp; done
cd sub && rm a.md
cd $temp && rm $repo/src.py
sed -i '' 's/a/b/' src.py
sed -E -i 's/a/b/' src.py
sed -i.bak 's/a/b/' src.py
perl -pi -e 's/a/b/' src.py
cp $temp/x src.py
mv $temp/x src.py
cat x | tee src.py
dd if=/dev/zero of=src.py
touch $work/plain/x
ls | xargs rm
find . -name '*.py' -delete
find . -name '*.py' -exec rm {} \\;
out=\$(touch src.py)
git commit -m x
git -C $repo add src.py
git -C "$repo" commit -m x
git -c user.name=x commit --amend
git push
git fetch
git stash
git stash pop
git branch -D old
git branch newname
git tag v1
git config user.name x
git worktree add ../tree
git checkout -- src.py
gh pr merge 1
git clone https://example.invalid/r
find -name '*.py' -delete
curl -o src.py https://example.invalid
curl -sLO https://example.invalid
wget https://example.invalid
npm install
ruff check --fix .
ruff format .
black src.py
prettier --write .
rm "\$UNKNOWN/x"
cd build && git commit -am x
cd build/cache && git commit -am x
(cd $temp && ls) && rm src.py
git -C $repo/build reset --hard HEAD~1
cd /tmp && git --git-dir=$repo/.git --work-tree=$repo commit -am x
cd /tmp && GIT_DIR=$repo/.git git commit -am x
(cd $temp && ls); rm src.py
cd /does-not-exist; rm src.py
false && cd $temp; rm src.py
pushd $temp; popd; rm src.py
rm -rf build
rm -rf $HOME/.claude/projects/p
git -C $temp/clone push
env -i rm src.py
sudo -n rm src.py
time -p rm src.py
command -p rm src.py
env -S 'rm src.py'
bash -c 'rm src.py'
sh -c "echo x > src.py"
eval "rm src.py"
xargs sh -c 'rm "\$@"' _
watch -n1 rm src.py
git merge-file src.py $temp/a $temp/b
git checkout-index -f -a
git update-index --assume-unchanged src.py
git symbolic-ref HEAD refs/heads/x
git reflog expire --expire=now --all
git format-patch -1
git ci -m x
git branch --set-upstream-to=origin/main
gh api -X PUT repos/o/r/contents/f -f message=x
gh release create v1
gzip src.py
tar -xf $temp/x.tar
unzip -o $temp/x.zip
cargo fmt
go fmt ./...
awk -i inplace '{print}' src.py
find . -fprint list.txt
chmod --reference=$temp/a src.py
coproc rm src.py
echo \$((1<<2)) ; rm src.py
echo a\ #; rm src.py
x=/tmp/y; x=\$PWD; rm -rf "\$x/src.py"
d=/tmp/../$repo; rm "\$d/src.py"
TMPDIR=. ; echo x > \$TMPDIR/src.py
echo x > \`pwd\`/src.py
ln -s $repo/src.py $temp/l
echo 'unbalanced
EOF
shell refuse $'cat <<\'END\' > src.py\nit\'s text\nEND'
shell refuse $'cd /tmp\nrm '"$repo/src.py"

# Shell commands inside a subagent that change no code or documentation
while IFS= read -r command; do shell allow "$command"; done <<EOF
git diff
git log --stat -3
git -C $repo show HEAD
git stash list
git branch -a
git branch
git tag -l
git config --get user.name
grep -rn 'rm ' .
grep "; rm -rf" src.py
grep '<title>' page.html
awk '\$1 > 5' src.py
jq '.a > .b' data.json
cat src.py 2>/dev/null
ls > /dev/null 2>&1
command -v rm
echo x > $temp/out
mkdir -p $temp/bench && cd $temp/bench && echo x > result && rm result
tmp=\$(mktemp -d); echo x > "\$tmp/out"; rm -rf "\$tmp"
rm -rf /tmp/subagent-code-guard-probe
echo x > build/log
python3 bench.py > $temp/result.txt 2>&1
cd $temp && git init -q t && git -C t commit --allow-empty -m x
curl -s https://example.invalid
cd $temp && git clone https://example.invalid/r
rm -rf build/cache
(cd $temp && git init -q c && git -C c commit --allow-empty -m x)
gh api repos/o/r/contents/f
gh release view v1
gzip -c src.py > $temp/src.gz
tar -tf $temp/x.tar
tar -czf $temp/x.tgz .
unzip -l $temp/x.zip
cargo fmt --check
git branch --contains HEAD
echo \$((2 > 1))
bash -c 'git status'
find $temp -name '*.txt' -delete
curl -o $temp/page https://example.invalid
wget -qO- https://example.invalid
gh pr create --title x
brew install x
black --check .
ruff check .
diff <(git diff) <(git diff --cached)
find . -name '*.md' -exec grep -l x {} \\;
EOF
shell allow $'# don\'t change anything\nls'
shell allow $'cat <<\'END\'\nit\'s > text\nEND\nls'
shell allow $'python3 - <<\'END\'\nopen("x", "w")\nEND'

# Claude's folder stays protected when it is a link into a repository that
# ignores its contents.
mkdir -p "$work/home" "$work/dotfiles/claude/state"
(cd "$work/dotfiles" && git init -q && echo 'claude/state/' > .gitignore) || exit 1
ln -s "$work/dotfiles/claude" "$work/home/.claude"
got=$(payload helper Write "$repo" file_path "$work/home/.claude/state/check-settled-x" |
    HOME="$work/home" TMPDIR="$temp" "$hook_script")
case "$got" in
    *'"deny"'*) ;;
    *) fail "a write into Claude's linked folder passed" ;;
esac

# The main session is never refused, even when its command names agent_id
expect allow "" Edit file_path "$repo/src.py"
expect allow "" Bash command "git commit -m x"
expect allow "" Bash command "grep '\"agent_id\":\"x\"' src.py > out"

# A subagent's call is refused when the hook cannot decide
no_python=$(mktemp -d)
trap 'rm -rf "$work" "$no_python"' EXIT
ln -s "$(command -v cat)" "$no_python/cat"; ln -s "$(command -v bash)" "$no_python/bash"
ln -s "$(command -v dirname)" "$no_python/dirname"
got=$(payload helper Bash "$repo" command "git diff" | PATH="$no_python" "$hook_script")
case "$got" in
    *'"deny"'*) ;;
    *) fail "a subagent's call passed although the hook could not run its check" ;;
esac

[ "$failures" -eq 0 ] && echo "subagent code guard: every call gets its verdict"
[ "$failures" -eq 0 ]

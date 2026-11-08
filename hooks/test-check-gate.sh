#!/usr/bin/env bash
# Runs check-gate.sh through turn patterns in a throwaway home folder and
# repository, and exits non-zero when a pattern gets the wrong verdict. A pattern
# named an accepted gap pins a behaviour that design_history.md accepts.

set -u

gate_script="$(cd "$(dirname "$0")" && pwd)/check-gate.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/repo" "$work/plain"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
cd "$work/repo" || exit 1
git init -q && echo first > file && git add file &&
    git -c user.email=test@example.invalid -c user.name=test commit -qm first || exit 1

cwd="$work/repo"
send() {
    printf '{"session_id":"test","cwd":"%s","tool_name":"%s","tool_input":{"skill":"%s"}}' \
        "$cwd" "${2:-}" "${3:-}" | HOME="$work/home" "$gate_script" "$1"
}
verdict() { [ -n "$(send gate)" ] && echo block || echo allow; }
run_check() { send satisfied "" check; }
change_file() { echo "$1" >> file; }

failures=0
expect() {
    local got
    got=$(verdict)
    [ "$got" = "$2" ] && return 0
    echo "FAIL: $1: got $got, expected $2"
    failures=$((failures + 1))
}

send reset; send mark Edit; expect "edit without check" block; run_check; expect "edit after check" allow
send reset; send mark Bash; expect "read-only shell" allow
send reset; change_file b; send mark Bash; expect "shell write" block; run_check; expect "shell write after check" allow
send reset; send mark Edit; send reset; expect "interrupted edit carried over" block; run_check; verdict >/dev/null
send reset; change_file c; send mark Bash; send reset; expect "interrupted shell write carried over" block; run_check; verdict >/dev/null
send reset; send mark Edit; verdict >/dev/null; run_check; expect "checked turn ends" allow
send mark Edit; expect "resumed turn edits" block; run_check; verdict >/dev/null
send mark Bash; expect "resumed read-only shell" allow
change_file d; send reset; send mark Bash; expect "own edit between typed turns" allow
send reset; send mark Edit; verdict >/dev/null; send reset; expect "forced check interrupted" block; run_check; verdict >/dev/null
send reset; send mark Edit; verdict >/dev/null; expect "blocked turn may end" allow; send reset; expect "next turn blocks again" block
run_check; verdict >/dev/null
send reset; send mark Edit; run_check; send mark Edit; send reset; expect "checked then interrupted" allow
send reset; send mark Edit; send satisfied "" iterate; expect "another skill does not settle" block; run_check; verdict >/dev/null
send reset; send mark Edit; run_check; send reset; send mark Edit; expect "typed turn after a checked, interrupted turn" block
run_check; verdict >/dev/null
send reset; change_file e; send mark Bash; run_check; verdict >/dev/null
send mark Bash; expect "resumed read-only shell after a checked write" allow
cwd="$work/plain"; send reset; send mark Bash; expect "shell outside a repository" block; run_check; verdict >/dev/null
cwd="$work/repo"
send reset; send mark Edit; run_check; send mark Edit; expect "turn resumed after a checked, interrupted turn (accepted gap)" allow
send reset; send mark Edit; verdict >/dev/null; send mark Edit; expect "turn resumed after an interrupted forced check (accepted gap)" allow
send reset; expect "its writes stay pending" block; run_check; verdict >/dev/null
send reset; expect "question only" allow

[ "$failures" -eq 0 ] && echo "check gate: every pattern passes"
[ "$failures" -eq 0 ]

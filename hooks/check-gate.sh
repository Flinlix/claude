#!/usr/bin/env bash
# Enforces that the [Check] skill runs after a turn that could have written.
#
# Wired to four hook events in ~/.claude/settings.json:
#   mark       PostToolUse (Edit|Write|NotebookEdit|Bash)  a write-capable tool ran
#   satisfied  PostToolUse (Skill)                         Check ran; settle the gate
#   gate       Stop                                        block once until Check ran
#   reset      UserPromptSubmit                            start the turn
#
# An edit tool always counts as a write; a Bash command counts when the git
# tree differs from the one recorded after the last check or at the start of a
# turn with nothing pending. Writes that no check has seen stay pending across
# turns. State is up to five files per session, expiring after 7 days. Reads the
# hook payload from stdin. test-check-gate.sh tests it. See design_history.md.

set -u

mode=${1:-}
state_dir="$HOME/.claude/state"

payload=$(cat)

# Hook payloads are single-line JSON, so a sed capture reads a field.
read_session_id() {
    local id
    id=$(printf '%s' "$payload" |
        sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    printf '%s' "${id:-default}"
}

read_field() {
    printf '%s' "$payload" |
        sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

# Prints the state of the repository at $1: its commit, stash, index and files.
repository_state() {
    git -C "$1" rev-parse HEAD
    git -C "$1" stash list
    git -C "$1" status --porcelain=v1 -uall
    git -C "$1" diff --binary
    git -C "$1" diff --cached --binary
    git -C "$1" ls-files -o --exclude-standard -z |
        (cd "$1" && xargs -0 -r git hash-object --)
}

# Prints a hash of the working tree's state: the repository holding $1, or else
# the repositories directly below it; nothing where there is none.
tree_fingerprint() {
    local top dir found=""
    export GIT_OPTIONAL_LOCKS=0
    if top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null); then
        repository_state "$top" 2>/dev/null | shasum | cut -d ' ' -f 1
        return 0
    fi
    for dir in "$1"/*/; do
        [ -e "$dir.git" ] && found=1 && break
    done
    [ -n "$found" ] || return 0
    for dir in "$1"/*/; do
        [ -e "$dir.git" ] || continue
        printf '%s\n' "$dir"
        repository_state "$dir"
    done 2>/dev/null | shasum | cut -d ' ' -f 1
}

session_id=$(read_session_id)
pending="$state_dir/check-pending-$session_id"
pending_shell="$state_dir/check-pending-shell-$session_id"
baseline="$state_dir/check-tree-$session_id"
settled="$state_dir/check-settled-$session_id"
blocked="$state_dir/check-blocked-$session_id"

case "$mode" in
    mark)
        mkdir -p "$state_dir"
        if [ "$(read_field tool_name)" = "Bash" ]; then
            touch "$pending_shell"
        else
            touch "$pending"
        fi
        ;;
    satisfied)
        # Fires for every Skill call; only the check skill settles the gate.
        if printf '%s' "$payload" | grep -q '"skill"[[:space:]]*:[[:space:]]*"check"'; then
            mkdir -p "$state_dir" && touch "$settled"
        fi
        ;;
    reset)
        mkdir -p "$state_dir"
        if [ -f "$settled" ]; then
            rm -f "$pending" "$pending_shell" "$settled"
        fi
        rm -f "$blocked"
        if [ ! -f "$pending" ] && [ ! -f "$pending_shell" ]; then
            tree_fingerprint "$(read_field cwd)" > "$baseline"
        fi
        find "$state_dir" -maxdepth 1 -name 'check-*' -type f -mtime +7 -delete 2>/dev/null
        ;;
    gate)
        if [ -f "$settled" ]; then
            rm -f "$pending" "$pending_shell" "$settled" "$blocked"
            tree_fingerprint "$(read_field cwd)" > "$baseline"
            exit 0
        fi
        if [ -f "$blocked" ]; then
            rm -f "$blocked"
            exit 0
        fi
        if [ ! -f "$pending" ] && [ -f "$pending_shell" ]; then
            current=$(tree_fingerprint "$(read_field cwd)")
            if [ -n "$current" ] && [ "$current" = "$(cat "$baseline" 2>/dev/null)" ]; then
                rm -f "$pending_shell"
            fi
        fi
        if [ -f "$pending" ] || [ -f "$pending_shell" ]; then
            touch "$blocked"
            printf '%s\n' '{"decision":"block","reason":"A write-capable tool ran since the last [Check], and [Check] has not run. Invoke the Skill tool with skill: \"check\". If it finds nothing changed, it reports nothing about itself; that is not a reason to review anything else. If the skill is not registered (it loads at session start, so a skill created during this session is not available until restart), do not stop: carry out the same review inline by following ~/.claude/skills/check/SKILL.md, and say that the skill was unavailable. An inline review does not settle this gate, so this block comes back at the end of every turn until a restart loads the skill; say that too."}'
        fi
        ;;
    *)
        echo "usage: check-gate.sh mark|satisfied|gate|reset" >&2
        ;;
esac

exit 0

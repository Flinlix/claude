#!/usr/bin/env bash
# Enforces that the [Check] skill runs after a turn that could have written.
#
# Wired to four hook events in ~/.claude/settings.json:
#   mark       PostToolUse (Edit|Write|NotebookEdit|Bash)  a write-capable tool ran
#   satisfied  PostToolUse (Skill)                         Check ran; settle the gate
#   gate       Stop                                        block the turn until Check ran
#   reset      UserPromptSubmit                            clear state, record the tree
#
# An edit tool always counts as a write. A Bash command counts as one only if
# the git tree of the session's working directory differs from the one recorded
# at the start of the turn; outside a repository it always counts. What changed
# is still established by [Check] itself. See design_history.md.
#
# State is up to four files per session, expiring after 7 days. "settled" means
# the gate is resolved for this turn, raised either by blocking once or by Check
# having run, so the edits Check itself makes cannot trigger a second block.
#
# Reads the hook payload from stdin. jq is not assumed to be installed.

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

# Prints a hash of the working tree's state, or nothing outside a repository.
tree_fingerprint() {
    local top
    export GIT_OPTIONAL_LOCKS=0
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
    {
        git -C "$top" rev-parse HEAD
        git -C "$top" stash list
        git -C "$top" status --porcelain=v1 -uall
        git -C "$top" diff --binary
        git -C "$top" diff --cached --binary
        git -C "$top" ls-files -o --exclude-standard -z |
            (cd "$top" && xargs -0 -r git hash-object --)
    } 2>/dev/null | shasum | cut -d ' ' -f 1
}

session_id=$(read_session_id)
pending="$state_dir/check-pending-$session_id"
pending_shell="$state_dir/check-pending-shell-$session_id"
baseline="$state_dir/check-tree-$session_id"
settled="$state_dir/check-settled-$session_id"

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
        rm -f "$pending" "$pending_shell" "$settled"
        mkdir -p "$state_dir" && tree_fingerprint "$(read_field cwd)" > "$baseline"
        # A session that ends right after a tool call orphans its flags: "reset"
        # only ever fires within the same session, so nothing else clears them.
        find "$state_dir" -maxdepth 1 -name 'check-*' -type f -mtime +7 -delete 2>/dev/null
        ;;
    gate)
        if [ -f "$settled" ]; then
            exit 0
        fi
        if [ ! -f "$pending" ] && [ -f "$pending_shell" ]; then
            current=$(tree_fingerprint "$(read_field cwd)")
            if [ -n "$current" ] && [ "$current" = "$(cat "$baseline" 2>/dev/null)" ]; then
                rm -f "$pending_shell"
            fi
        fi
        if [ -f "$pending" ] || [ -f "$pending_shell" ]; then
            rm -f "$pending" "$pending_shell"
            touch "$settled"
            printf '%s\n' '{"decision":"block","reason":"A write-capable tool ran this turn but the [Check] skill has not. Invoke the Skill tool with skill: \"check\". If it finds the turn changed nothing, it stops without a report; that is not a reason to review anything else. If the skill is not registered (it loads at session start, so a skill created during this session is not available until restart), do not stop: carry out the same review inline by following ~/.claude/skills/check/SKILL.md, and say that the skill was unavailable."}'
        fi
        ;;
    *)
        echo "usage: check-gate.sh mark|satisfied|gate|reset" >&2
        ;;
esac

exit 0

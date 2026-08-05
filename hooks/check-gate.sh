#!/usr/bin/env bash
# Enforces that the [Check] skill runs after files are modified.
#
# Wired to four hook events in ~/.claude/settings.json:
#   mark       PostToolUse (Edit|Write|NotebookEdit)  record changes; expire old flags
#   satisfied  PostToolUse (Skill)                    Check ran; settle the gate
#   gate       Stop                                   block the turn until Check ran
#   reset      UserPromptSubmit                       clear state for a new user turn
#
# State is two flag files per session, expiring after 7 days. "settled" means the
# gate is resolved for this turn, raised either by blocking once or by Check
# having run, so the edits Check itself makes cannot trigger a second block.
#
# Reads the hook payload from stdin. jq is not assumed to be installed.

set -u

mode=${1:-}
state_dir="$HOME/.claude/state"

payload=$(cat)

# Hook payloads are single-line JSON; a sed capture avoids a jq dependency and
# an interpreter spawn on every single edit.
read_session_id() {
    local id
    id=$(printf '%s' "$payload" |
        sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    printf '%s' "${id:-default}"
}

session_id=$(read_session_id)
pending="$state_dir/check-pending-$session_id"
settled="$state_dir/check-settled-$session_id"

case "$mode" in
    mark)
        mkdir -p "$state_dir" && touch "$pending"
        # A session that ends right after an edit orphans its flags: "reset"
        # only ever fires within the same session, so nothing else clears them.
        find "$state_dir" -maxdepth 1 -name 'check-*' -type f -mtime +7 -delete 2>/dev/null
        ;;
    satisfied)
        # Fires for every Skill call; only the check skill settles the gate.
        if printf '%s' "$payload" | grep -q '"skill"[[:space:]]*:[[:space:]]*"check"'; then
            mkdir -p "$state_dir" && touch "$settled"
        fi
        ;;
    reset)
        rm -f "$pending" "$settled"
        ;;
    gate)
        if [ -f "$pending" ] && [ ! -f "$settled" ]; then
            rm -f "$pending"
            touch "$settled"
            printf '%s\n' '{"decision":"block","reason":"Files were modified this turn but the [Check] skill has not run. Invoke the Skill tool with skill: \"check\", scoped to exactly those changes, fix everything it surfaces, then finish the turn. If that skill is not registered (it loads at session start, so a skill created during this session is not available until restart), do not stop: carry out the same review inline by following ~/.claude/skills/check/SKILL.md, and say that the skill was unavailable."}'
        fi
        ;;
    *)
        echo "usage: check-gate.sh mark|satisfied|gate|reset" >&2
        ;;
esac

exit 0

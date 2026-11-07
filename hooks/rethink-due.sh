#!/usr/bin/env bash
# Asks for [Rethink] on every RETHINK_INTERVAL_TURNS-th user turn of a session.
#
# Runs on UserPromptSubmit. Its output enters the session's context, and only
# on the turns that are due. See design_history.md.

set -u

RETHINK_INTERVAL_TURNS=10

state_dir="$HOME/.claude/state"
payload=$(cat)

session_id=$(printf '%s' "$payload" |
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
turn_file="$state_dir/rethink-turn-${session_id:-default}"

mkdir -p "$state_dir"
turn=$(( $(cat "$turn_file" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$turn" > "$turn_file"
find "$state_dir" -maxdepth 1 -name 'rethink-turn-*' -type f -mtime +7 -delete 2>/dev/null

if [ $((turn % RETHINK_INTERVAL_TURNS)) -eq 0 ]; then
    printf 'This is user turn %s of the session: invoke [Rethink] on the project this session works on, besides the request, and put its findings and decisions into this round'"'"'s report.\n' "$turn"
fi

exit 0

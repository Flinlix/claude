#!/usr/bin/env bash
# Tells a session on Saturday or Sunday that the weekly configuration review is
# due, unless one started or finished within REVIEW_INTERVAL_S, on this machine
# or, by the newest weekly review recorded in design_history.md, on any. A
# missing, unreadable or future stamp counts as never. See design_history.md.

REVIEW_INTERVAL_S=$((2 * 24 * 3600))

state_dir="$HOME/.claude/state"
weekday=$(date +%u)
[ "$weekday" -ge 6 ] || exit 0

now=$(date +%s)

read_stamp() {
    local value
    value=$(cat "$1" 2>/dev/null)
    case "$value" in
        ''|*[!0-9]*) echo 0 ;;
        *) if [ "$value" -le "$now" ] 2>/dev/null; then echo "$value"; else echo 0; fi ;;
    esac
}

last=$(read_stamp "$state_dir/config-review-last")
started=$(read_stamp "$state_dir/config-review-started")
[ "$started" -gt "$last" ] && last=$started
# (a review recorded in the configuration repository, which every machine pulls, counts too)
logged=$(grep -o '^## [0-9]\{4\}-[0-9][0-9]-[0-9][0-9]: Weekly review' "$HOME/.claude/design_history.md" 2>/dev/null | tail -1 | cut -c4-13)
logged_s=$(date -j -f '%Y-%m-%d %H:%M:%S' "$logged 00:00:00" +%s 2>/dev/null || echo 0)
[ "$logged_s" -gt "$last" ] && last=$logged_s
[ $((now - last)) -ge "$REVIEW_INTERVAL_S" ] || exit 0

printf '%s\n' "The weekly configuration review is due. In this session's next [Iterate] loop, invoke the review-config skill before writing the hand-back, and put its proposals into that hand-back's decisions."
exit 0

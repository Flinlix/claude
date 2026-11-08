#!/usr/bin/env bash
# Tells a session starting on Saturday or Sunday that the weekly configuration
# review is due, unless one ran within REVIEW_INTERVAL_S.
#
# The output enters the session's context. A Saturday review covers the
# Sunday, so the review runs on Sunday only when Saturday had none. The review
# itself writes the stamp, so a session that is told and then ends without it
# leaves the review due. See design_history.md.

REVIEW_INTERVAL_S=$((2 * 24 * 3600))

stamp="$HOME/.claude/state/config-review-last"
weekday=$(date +%u)
[ "$weekday" -ge 6 ] || exit 0

last=$(cat "$stamp" 2>/dev/null || echo 0)
[ $(($(date +%s) - last)) -ge "$REVIEW_INTERVAL_S" ] || exit 0

printf '%s\n' "The weekly configuration review is due. In this session's next [Iterate] loop, invoke the review-config skill before writing the hand-back, and put its proposals into that hand-back's decisions."
exit 0

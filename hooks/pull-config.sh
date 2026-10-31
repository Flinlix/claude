#!/usr/bin/env bash
# Pulls the configuration repository at session start, in the background.
#
# The pull finishes after the session has loaded its configuration, so what it
# brings takes effect from the next session on. A failed pull is reported to
# the next session through this hook's output, which enters its context. Only
# fast-forwards are taken: local commits or edits are never merged or
# overwritten. See design_history.md.

set -u

repo="$HOME/.claude"
log="$repo/state/config-pull.log"
mkdir -p "$repo/state"

if [ -f "$log" ] && [ "$(head -n 1 "$log" | cut -d ' ' -f 1)" = "failed" ]; then
    printf 'The last automatic pull of %s failed (%s). Tell the user once, with its cause:\n%s\n' \
        "$repo" "$(head -n 1 "$log" | cut -d ' ' -f 2-)" "$(tail -n +2 "$log")"
fi

(
    if output=$(GIT_TERMINAL_PROMPT=0 git -C "$repo" pull --ff-only --quiet 2>&1); then
        printf 'ok %s\n' "$(date '+%F %T')" > "$log"
    else
        printf 'failed %s\n%s\n' "$(date '+%F %T')" "$output" > "$log"
    fi
) </dev/null >/dev/null 2>&1 &

exit 0

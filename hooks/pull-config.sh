#!/usr/bin/env bash
# Pulls the configuration repository in the background, fast-forward only, and
# reports the previous pull's failure to the session. See design_history.md.

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

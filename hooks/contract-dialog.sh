#!/usr/bin/env bash
# Limits project contract dialogs to one per DIALOG_INTERVAL_TURNS user turns.
#
#   turn   UserPromptSubmit           count the turn; say if no dialog is allowed
#   asked  PostToolUse (AskUserQuestion)  a dialog headed "Contract" was shown
#
# A contract dialog is an AskUserQuestion whose question header is "Contract".
# The output of "turn" enters the session's context, and only on the turns
# that allow no dialog. See design_history.md.

set -u

DIALOG_INTERVAL_TURNS=5

mode=${1:-}
state_dir="$HOME/.claude/state"
payload=$(cat)

session_id=$(printf '%s' "$payload" |
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
turn_file="$state_dir/contract-turn-${session_id:-default}"
asked_file="$state_dir/contract-asked-${session_id:-default}"

mkdir -p "$state_dir"
turn=$(cat "$turn_file" 2>/dev/null || echo 0)

case "$mode" in
    turn)
        turn=$((turn + 1))
        printf '%s\n' "$turn" > "$turn_file"
        find "$state_dir" -maxdepth 1 -name 'contract-*' -type f -mtime +7 -delete 2>/dev/null
        asked=$(cat "$asked_file" 2>/dev/null || echo -"$DIALOG_INTERVAL_TURNS")
        wait_turns=$((asked + DIALOG_INTERVAL_TURNS - turn))
        if [ "$wait_turns" -gt 0 ]; then
            printf 'No project contract dialog in this turn: the next one is allowed in %s turn(s). Keep any contract proposal until then.\n' "$wait_turns"
        fi
        ;;
    asked)
        if printf '%s' "$payload" | grep -q '"header"[[:space:]]*:[[:space:]]*"Contract"'; then
            printf '%s\n' "$turn" > "$asked_file"
        fi
        ;;
    *)
        echo "usage: contract-dialog.sh turn|asked" >&2
        ;;
esac

exit 0

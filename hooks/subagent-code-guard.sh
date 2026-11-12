#!/usr/bin/env bash
# Refuses a subagent's tool calls that would change code or documentation, so
# that every such change is made by the main session.
#
# Wired to PreToolUse in ~/.claude/settings.json for the tools that can write. A
# payload carries agent_id only when the call comes from a subagent; the main
# session's calls pass at the first check. subagent_code_guard.py decides the
# rest, and a subagent's call is refused when it cannot decide. Reads the hook
# payload from stdin. test-subagent-code-guard.sh tests it. See design_history.md.

set -u

payload=$(cat)

case "$payload" in
    *'"agent_id"'*) ;;
    *) exit 0 ;;
esac

printf '%s' "$payload" | python3 -I "$(dirname "$0")/subagent_code_guard.py" 2>/dev/null && exit 0
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The hook could not check whether this subagent call changes code or documentation, so it is refused. Report the call to the main session instead."}}'

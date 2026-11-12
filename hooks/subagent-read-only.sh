#!/usr/bin/env bash
# Refuses a helper agent's tool calls that would change files, git or another
# system, so that every change is made by the main session.
#
# Wired to PreToolUse in ~/.claude/settings.json for the tools that can change
# something. A payload carries agent_id only when the call comes from a helper
# agent; the main session's calls pass untouched. A shell command is refused
# when it matches one of the writing forms below, and every call from a helper
# agent is refused when its payload cannot be read. Reads the payload from stdin.
# test-subagent-read-only.sh tests it. See design_history.md.

set -u

payload=$(cat)

refuse() {
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"A helper agent reads and reports; it changes nothing. Name the change you would make, with file and line, in your report, and the main session makes it. A read-only command that was refused by mistake can be rewritten, for example without a redirection."}}'
    exit 0
}

case "$payload" in
    *'"agent_id"'*) ;;
    *) exit 0 ;;
esac

# Prints the tool name on the first line and the shell command after it, or
# nothing when the call does not come from a helper agent.
fields=$(printf '%s' "$payload" | python3 -I -c '
import json, sys
call = json.load(sys.stdin)
if call.get("agent_id"):
    print(call.get("tool_name", ""))
    print((call.get("tool_input") or {}).get("command", ""))
') || refuse
[ -n "$fields" ] || exit 0
tool_name=${fields%%$'\n'*}
command=${fields#*$'\n'}

case "$tool_name" in
    Bash) ;;
    *) refuse ;;
esac

# A redirection to /dev/null and a duplicated descriptor write nothing.
command=$(printf '%s' "$command" | sed -E 's#[0-9&]*>>?[[:space:]]*/dev/null##g; s#[0-9]*>&[0-9-]##g')

start='(^|[;&|(`]|\$\(|[[:space:]](xargs|sudo|nohup|env|command|time|-exec|-execdir))[[:space:]]*(-[^[:space:]]+[[:space:]]+)*'
git_options='([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--[^[:space:]]+))*'
writing_forms=(
    "${start}(rm|rmdir|mv|cp|touch|mkdir|ln|chmod|chown|tee|truncate|dd|install|rsync|unlink|patch)([[:space:]]|$)"
    "${start}git${git_options}[[:space:]]+(add|commit|push|pull|reset|checkout|switch|restore|rebase|merge|cherry-pick|revert|apply|am|clean|rm|mv|init|clone|update-ref|gc)([[:space:]]|$)"
    "${start}(sed|perl)[[:space:]]+([^|;&]*[[:space:]])?(-[a-zA-Z]*i|--in-place)"
    "(^|[[:space:]0-9&])>>?[[:space:]]*[^[:space:]&>0-9]"
    "[[:space:]]-delete([[:space:]]|$)"
    "${start}gh[[:space:]]+[a-z-]+[[:space:]]+(create|merge|close|edit|comment|delete|review|reopen|ready|lock|unlock|set|enable|disable|cancel|rerun|fork|rename|archive|upload)([[:space:]]|$)"
    "${start}gh[[:space:]]+api([[:space:]].*)?[[:space:]](-X|--method|-f|-F|--field|--raw-field|--input)([[:space:]=]|$)"
    "${start}curl([[:space:]].*)?([[:space:]](-X|--request)[[:space:]=]*(POST|PUT|PATCH|DELETE)|[[:space:]](-d|--data[a-z-]*|-F|--form|-T|--upload-file)([[:space:]=]|$))"
)

for form in "${writing_forms[@]}"; do
    printf '%s\n' "$command" | grep -Eq -- "$form" && refuse
done

exit 0

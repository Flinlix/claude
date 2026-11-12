#!/usr/bin/env bash
# Refuses a subagent's tool calls that would change files, git or another
# system, so that every change is made by the main session.
#
# Wired to PreToolUse in ~/.claude/settings.json for the tools that can change
# something. A payload carries agent_id only when the call comes from a
# subagent; the main session's calls pass untouched. A tool with read actions
# passes for those actions only, and a shell command is refused when it matches
# one of the writing forms below. Every call from a subagent is refused when its
# payload cannot be read. Reads the payload from stdin.
# test-subagent-read-only.sh tests it. See design_history.md.

set -u

payload=$(cat)

refuse() {
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"A subagent reads and reports; it changes nothing. Name the change you would make, with file and line, in your report, and the main session makes it. A read-only command that was refused by mistake can be rewritten, for example without a redirection or a comparison sign."}}'
    exit 0
}

case "$payload" in
    *'"agent_id"'*) ;;
    *) exit 0 ;;
esac

# Prints the tool name, the action and the shell command on lines of their own,
# or nothing when the call does not come from a subagent.
fields=$(printf '%s' "$payload" | python3 -I -c '
import json, sys
call = json.load(sys.stdin)
if call.get("agent_id"):
    tool_input = call.get("tool_input") or {}
    print(call.get("tool_name", ""))
    print(tool_input.get("action", ""))
    print(tool_input.get("command", ""))
') || refuse
[ -n "$fields" ] || exit 0
tool_name=$(printf '%s\n' "$fields" | sed -n 1p)
action=$(printf '%s\n' "$fields" | sed -n 2p)
command=$(printf '%s\n' "$fields" | sed -n '3,$p')

case "$tool_name:$action" in
    Artifact:read | Artifact:list | ArtifactComments:read) exit 0 ;;
    ArtifactData:get | ArtifactData:list | ArtifactData:query | ArtifactData:profiles) exit 0 ;;
    Bash:*) ;;
    *) refuse ;;
esac

# Text that looks like a redirection but writes nothing: output to /dev/null, a
# duplicated descriptor, an HTML tag, a comparison with a number, and a read
# through gh api (a GraphQL query, or a GET whose fields become query string).
command=$(printf '%s\n' "$command" | sed -E '
    s#[0-9&]*>>?[[:space:]]*/dev/null##g
    s#[0-9]*>&[0-9-]##g
    s#</?[A-Za-z][^<>[:space:]]*>##g
    s#>=?[[:space:]]*[0-9]+([[:space:]"'"'"')}]|$)#\1#g
    /mutation/!s#gh[[:space:]]+api[[:space:]]+graphql#gh-api-graphql#g
    /(-X|--method)[[:space:]=]*GET/s#gh[[:space:]]+api#gh-api-get#g
')

# A command word counts where a command starts: after a separator or a shell
# keyword, behind variable assignments, a wrapper such as sudo, a path or a
# backslash.
separator='(^|[;&|({!`]|\$\(|[[:space:]](then|do|else|elif|-exec|-execdir))'
wrapper='((xargs|sudo|nohup|env|time|timeout|nice|exec)([[:space:]]+[^[:space:];&|]+)*[[:space:]]+)?'
start="${separator}[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${wrapper}\\\\?([^[:space:];&|]*/)?"
end='([[:space:];&|)]|$)'
value='("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)'
git="${start}git([[:space:]]+(-[Cc][[:space:]]+${value}|--(git-dir|work-tree|namespace|config-env)[[:space:]]+${value}|-[a-zA-Z]|--[^[:space:]]+))*[[:space:]]+"
gh="${start}gh[[:space:]]+"

writing_forms=(
    "${start}(rm|rmdir|mv|cp|touch|mkdir|ln|chmod|chown|tee|truncate|dd|install|rsync|unlink|patch|wget)${end}"
    "${start}(sed|perl)[[:space:]]+([^|;&]*[[:space:]])?(-[a-hj-z]*i([[:space:]\"'.]|$)|--in-place)"
    "(^|[^-=<>])>>?[[:space:]]*[^[:space:]&>]"
    "[[:space:]]-delete${end}"
    "${git}(add|commit|push|pull|fetch|reset|checkout|switch|restore|rebase|merge|cherry-pick|revert|apply|am|clean|rm|mv|init|clone|update-ref|gc|prune|repack|bisect|filter-branch|replace|sparse-checkout|maintenance)${end}"
    "${git}stash([[:space:]]*([;&|)]|$)|[[:space:]]+(push|pop|apply|drop|clear|save|create|store|branch|-))"
    "${git}tag[[:space:]]+([^-[:space:];&|]|-[adfsmu])"
    "${git}branch[[:space:]]+(([^-[:space:];&|])|(.*[[:space:]])?-([dDmMcC]|-delete|-move|-copy|-set-upstream-to|-unset-upstream))"
    "${git}config[[:space:]]+(set|unset|edit|rename-section|remove-section|--(global|local|system|worktree|file|unset|unset-all|add|replace-all|rename-section|remove-section|edit)|-e|[A-Za-z][A-Za-z0-9-]*\.[^[:space:]]+[[:space:]]+[^[:space:];&|])"
    "${git}worktree[[:space:]]+(add|remove|move|prune|lock|unlock|repair)${end}"
    "${git}remote[[:space:]]+(add|remove|rm|rename|set-url|set-head|set-branches|prune|update)${end}"
    "${git}notes([[:space:]]+--ref[= ][^[:space:]]+)?[[:space:]]+(add|append|copy|edit|merge|prune|remove)${end}"
    "${git}submodule[[:space:]]+(add|update|init|deinit|sync|absorbgitdirs|set-branch|set-url)${end}"
    "${gh}[a-z-]+[[:space:]]+(create|merge|close|edit|comment|delete|review|reopen|ready|lock|unlock|set|enable|disable|cancel|rerun|run|fork|rename|archive|upload|checkout|clone|sync|transfer|pin|unpin|add|remove|install|upgrade|login|logout|develop)${end}"
    "${gh}api([[:space:]].*)?[[:space:]](-X|--method|-f|-F|--field|--raw-field|--input)([[:space:]=]|$)"
    "${start}curl([[:space:]].*)?([[:space:]](-X|--request)[[:space:]=]*(POST|PUT|PATCH|DELETE)|[[:space:]](--data[a-z-]*|--form|--upload-file|--json|--output|--remote-name[a-z-]*)([[:space:]=]|$)|[[:space:]]-[a-zA-Z]*[dFToO])"
    "${start}(brew|pip|pip3|npm|pnpm|yarn|gem|cargo|go|python3?[[:space:]]+-m[[:space:]]+pip)[[:space:]]+(install|uninstall|remove|upgrade|update|add|link|unlink|tap|untap|publish|ci|i|rm)${end}"
)

for form in "${writing_forms[@]}"; do
    printf '%s\n' "$command" | grep -Eq -- "$form" && refuse
done

exit 0

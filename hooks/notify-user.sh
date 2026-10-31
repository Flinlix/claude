#!/usr/bin/env bash
# Tells the user that Claude is waiting for them: notify-user.sh TITLE [MESSAGE]
#
# Reads the hook payload from stdin. Without a MESSAGE argument it shows the
# payload's "message" field, and it stays silent if the same session was
# notified within DUPLICATE_WINDOW_S: that call comes from a Notification event,
# which can follow a question that was already announced. See design_history.md.
#
# Rings the terminal bell and shows a desktop notification with whichever
# notifier the system has: terminal-notifier, then the built-in osascript on
# macOS, then notify-send on Linux. Clicking it on macOS brings back the app the
# session runs in, named by the bundle identifier macOS passes to the processes
# an app starts.

DUPLICATE_WINDOW_S=15

payload=$(cat 2>/dev/null)

read_field() {
    printf '%s' "$payload" |
        sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

title=${1:-Claude Code}
message=${2:-}

state_dir="$HOME/.claude/state"
last_file="$state_dir/notified-$(read_field session_id)"
now=$(date +%s)
if [ -z "$message" ]; then
    last=$(cat "$last_file" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt "$DUPLICATE_WINDOW_S" ]; then
        exit 0
    fi
    message=$(read_field message)
    message=${message:-Claude is waiting for you}
fi
mkdir -p "$state_dir" && printf '%s\n' "$now" > "$last_file"
find "$state_dir" -maxdepth 1 -name 'notified-*' -type f -mtime +7 -delete 2>/dev/null

{ printf '\a' > /dev/tty; } 2>/dev/null

if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$message" \
        ${__CFBundleIdentifier:+-activate "$__CFBundleIdentifier"} >/dev/null 2>&1
elif command -v osascript >/dev/null 2>&1; then
    osascript -e 'on run argv' \
        -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
        -e 'end run' "$title" "$message" >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" >/dev/null 2>&1
fi

exit 0

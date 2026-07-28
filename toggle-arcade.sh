#!/bin/bash
# toggle-arcade.sh — enable or disable the single-native-arcade autolaunch.
# Run as the arcade user (usually pi) from any tty except tty1, or from another
# console/SSH session.  This does not touch the autologin config; it just
# comments/uncomments the launcher block in ~/.bash_profile and ~/.profile.

set -e

BASH_PROFILE="$HOME/.bash_profile"
PROFILE="$HOME/.profile"

is_enabled_in_file() {
    grep -q '^[[:space:]]*exec bash.*launcher\.sh' "$1" 2>/dev/null
}

toggle_file() {
    local file="$1"
    [ -f "$file" ] || return 0

    awk '
        /^# single-native-arcade launcher$/ { in_block=1; print; next }
        in_block {
            if (/^fi$/) {
                print "# " $0
                in_block = 0
                next
            }
            if (/^# fi$/) {
                sub(/^# /, "")
                print
                in_block = 0
                next
            }
            if (/^# /) {
                sub(/^# /, "")
            } else {
                $0 = "# " $0
            }
            print
            next
        }
        { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
}

kill_running() {
    pkill -9 -f "games/[^/]+/Game" 2>/dev/null || true
    pkill -9 -f launcher.sh 2>/dev/null || true
    pkill -9 -f single-native-launch.sh 2>/dev/null || true
}

case "${1:-}" in
    disable|off)
        if is_enabled_in_file "$BASH_PROFILE" || is_enabled_in_file "$PROFILE"; then
            toggle_file "$BASH_PROFILE"
            toggle_file "$PROFILE"
            kill_running
            echo "Autolaunch disabled.  Re-login on tty1 to get a normal shell."
        else
            echo "Autolaunch is already disabled."
        fi
        ;;
    enable|on)
        if ! is_enabled_in_file "$BASH_PROFILE" && ! is_enabled_in_file "$PROFILE"; then
            toggle_file "$BASH_PROFILE"
            toggle_file "$PROFILE"
            echo "Autolaunch enabled.  Re-login on tty1 to start the arcade."
        else
            echo "Autolaunch is already enabled."
        fi
        ;;
    *)
        echo "Usage: $0 {enable|disable}" >&2
        exit 1
        ;;
esac

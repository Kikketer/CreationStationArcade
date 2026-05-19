#!/bin/bash
# Openbox autostart with lightweight splash screen

# Start audio system
pulseaudio --start &

# Hide cursor after 1s of inactivity
unclutter -idle 1 -root &

# Disable screen saver / blanking
xset s off
xset s noblank
xset -dpms

# Show splash screen with feh (instant)
SPLASH_IMG="/home/arcade/CreationStationArcade-run/install/splash.png"
if [ -f "$SPLASH_IMG" ]; then
    feh --bg-center --no-xinerama "$SPLASH_IMG" &
    FEH_PID=$!
else
    # Fallback to smaller image
    SPLASH_IMG="/home/arcade/CreationStationArcade-run/install/splash-1024.png"
    if [ -f "$SPLASH_IMG" ]; then
        feh --bg-center --no-xinerama "$SPLASH_IMG" &
        FEH_PID=$!
    fi
fi

# Start the arcade launcher
/home/arcade/CreationStationArcade-run/launcher.sh &

# Wait for launcher to start Chromium, then kill splash
sleep 8
if [ ! -z "$FEH_PID" ]; then
    kill $FEH_PID 2>/dev/null || true
fi

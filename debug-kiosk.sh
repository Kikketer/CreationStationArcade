#!/bin/bash
# debug-kiosk.sh - Diagnostic script for Creation Station Arcade kiosk issues
# Run on the Pi and share the full output

echo "=========================================="
echo "Creation Station Arcade - Kiosk Debug"
echo "=========================================="
echo ""

echo "--- System Info ---"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "Kernel: $(uname -r)"
echo "Arch: $(uname -m)"
echo "GPU Memory: $(vcgencmd get_mem gpu 2>/dev/null || echo 'N/A')"
echo ""

echo "--- Display/Session ---"
echo "TTY: $(tty 2>/dev/null || echo 'SSH')"
echo "DISPLAY: ${DISPLAY:-'not set'}"
echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-'not set'}"
echo ""

echo "--- Xorg Processes ---"
ps aux | grep -E 'Xorg|openbox|xinit' | grep -v grep
echo ""

echo "--- Chromium Process ---"
pgrep -a chromium | head -3
echo ""

echo "--- Window Tree ---"
if command -v xwininfo >/dev/null 2>&1; then
    DISPLAY=:0 xwininfo -root -tree 2>/dev/null | head -15 || echo "Cannot query window tree (X may not be accessible via SSH)"
else
    echo "xwininfo not installed - run: sudo apt-get install x11-utils"
fi
echo ""

echo "--- Visible Windows ---"
if command -v xdotool >/dev/null 2>&1; then
    visible=$(DISPLAY=:0 xdotool search --onlyvisible . 2>/dev/null | wc -l)
    echo "Visible windows: $visible"
    if [ "$visible" -gt 0 ]; then
        echo "Window IDs:"
        DISPLAY=:0 xdotool search --onlyvisible . 2>/dev/null
    fi
else
    echo "xdotool not installed - run: sudo apt-get install xdotool"
fi
echo ""

echo "--- Arcade Log (last 20 lines) ---"
tail -20 ~/arcade.log 2>/dev/null || echo "No arcade.log found"
echo ""

echo "--- Xorg Log Errors (last 10) ---"
XLOG="$HOME/.local/share/xorg/Xorg.0.log"
[ -f "$XLOG" ] && grep -i "(EE)" "$XLOG" | tail -10 || echo "No Xorg log found or no errors"
echo ""

echo "--- Launcher Script Check ---"
RUN_DIR="$HOME/CreationStationArcade-run"
if [ -f "$RUN_DIR/launcher.sh" ]; then
    echo "Runtime launcher exists: $RUN_DIR/launcher.sh"
    echo "Chromium flags in use:"
    grep -A20 'Launching Chromium' "$RUN_DIR/launcher.sh" | grep '^\s*--' | head -10
else
    echo "WARNING: Runtime launcher NOT found at $RUN_DIR/launcher.sh"
fi
echo ""

echo "--- Test Launch (dry run) ---"
echo "If X is running, this will show what command would execute:"
CHROMIUM_BIN=""
for bin in chromium-browser chromium google-chrome; do
    if command -v $bin >/dev/null 2>&1; then
        CHROMIUM_BIN=$bin
        break
    fi
done
echo "Chromium binary: ${CHROMIUM_BIN:-'NOT FOUND'}"
if [ -n "$CHROMIUM_BIN" ]; then
    echo "Command preview:"
    echo "$CHROMIUM_BIN --start-fullscreen --window-size=1920,1080 --window-position=0,0 --noerrdialogs --disable-infobars --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI,VizDisplayCompositor,CanvasOopRasterization --no-default-browser-check --disable-pinch --no-sandbox --disable-gpu http://localhost:3000"
fi
echo ""

echo "=========================================="
echo "Debug complete"
echo "=========================================="

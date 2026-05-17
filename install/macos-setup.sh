#!/bin/bash
# macos-setup.sh - Configure MacBook for Creation Station Arcade kiosk mode
# Chrome-based kiosk (ElectroBun requires newer macOS)

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$HOME/arcade-setup.log"
PLIST_NAME="com.creationstation.arcade"
LAUNCHER="$REPO_DIR/launcher-macos.sh"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Creation Station Arcade macOS Setup ==="
log "Repo: $REPO_DIR"

# ── 1. Check macOS version ─────────────────────────────────────────────────
OSX_VERSION=$(sw_vers -productVersion)
log "macOS version: $OSX_VERSION"

# ── 2. Check Chrome installation ───────────────────────────────────────────
log "Checking Chrome installation..."
CHROME_PATH=""
for path in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
            "/Applications/Chrome.app/Contents/MacOS/Chrome"; do
    if [ -f "$path" ]; then
        CHROME_PATH="$path"
        break
    fi
done

if [ -z "$CHROME_PATH" ]; then
    log "ERROR: Chrome not found. Please install Chrome:"
    log "  brew install --cask google-chrome"
    log "Or download from https://google.com/chrome"
    exit 1
fi

log "Chrome found: $CHROME_PATH"

# ── 3. Check Node.js ───────────────────────────────────────────────────────
log "Checking Node.js..."
if ! command -v node &> /dev/null; then
    log "ERROR: Node.js not found. Please install:"
    log "  brew install node"
    exit 1
fi
NODE_VER=$(node --version)
log "Node.js version: $NODE_VER"

# ── 4. Disable sleep on AC power ───────────────────────────────────────────
log "Configuring power settings..."

# Disable sleep when plugged in
sudo pmset -c sleep 0 2>/dev/null || log "WARNING: Could not disable sleep"
sudo pmset -c disablesleep 1 2>/dev/null || log "WARNING: Could not set disablesleep"

# Disable display sleep on AC
sudo pmset -c displaysleep 0 2>/dev/null || log "WARNING: Could not disable display sleep"

log "Power settings configured."

# ── 5. Auto-login reminder ────────────────────────────────────────────────
log ""
log "NOTE: Enable auto-login manually:"
log "  System Settings -> Users & Groups -> Automatic login"
log ""

# ── 6. Create macOS launcher script ───────────────────────────────────────
log "Creating macOS launcher script..."

cat > "$LAUNCHER" <<'LAUNCHER_EOF'
#!/bin/bash
# launcher-macos.sh - Launch arcade server and Chrome kiosk

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOME/arcade.log"
PID_FILE="/tmp/arcade-macos.pid"

# Kill existing processes
pkill -f "node.*server.js" 2>/dev/null || true
pkill -f "Google Chrome" 2>/dev/null || true
sleep 1

cd "$REPO_DIR"

# Start Node server
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting Node server..." >> "$LOG_FILE"
node server.js >> "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$PID_FILE"

# Wait for server to be ready
sleep 2

# Find Chrome
CHROME=""
for path in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
            "/Applications/Chrome.app/Contents/MacOS/Chrome"; do
    if [ -f "$path" ]; then
        CHROME="$path"
        break
    fi
done

if [ -z "$CHROME" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Chrome not found" >> "$LOG_FILE"
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting Chrome kiosk..." >> "$LOG_FILE"

# Launch Chrome in kiosk mode
"$CHROME" \
    --kiosk \
    --app=http://localhost:3000 \
    --no-first-run \
    --no-default-browser-check \
    --disable-features=TranslateUI \
    --disable-pinch \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --noerrdialogs \
    --user-data-dir=/tmp/chrome-arcade \
    >> "$LOG_FILE" 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Chrome exited" >> "$LOG_FILE"

# Cleanup
kill $SERVER_PID 2>/dev/null || true
rm -f "$PID_FILE"
LAUNCHER_EOF

chmod +x "$LAUNCHER"
log "Launcher created at: $LAUNCHER"

# ── 7. Create LaunchAgent for boot launch ──────────────────────────────────
log "Creating LaunchAgent for auto-start..."

LAUNCH_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_DIR"

cat > "$LAUNCH_DIR/${PLIST_NAME}.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${LAUNCHER}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/arcade.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/arcade-error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
EOF

launchctl load "$LAUNCH_DIR/${PLIST_NAME}.plist" 2>/dev/null || log "LaunchAgent created (loads on next login)"
log "LaunchAgent configured."

# ── 8. Auto-hide dock ───────────────────────────────────────────────────
log "Configuring dock..."
osascript -e 'tell application "System Events" to set autohide of dock preferences to true' 2>/dev/null || true
log "Dock auto-hide enabled."

# ── 9. Disable screensaver ─────────────────────────────────────────────────
log "Disabling screensaver..."
defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null || log "WARNING: Could not disable screensaver"

# ── 10. Summary ──────────────────────────────────────────────────────────
log ""
log "=== Setup Complete ==="
log "1. Enable auto-login: System Settings -> Users & Groups"
log "2. Connect Arduino USB bridge for arcade controls"
log "3. Reboot to test auto-launch"
log ""
log "Manual test: bash $LAUNCHER"
log "Log files: ~/arcade.log, ~/arcade-error.log"
log ""
log "To disable: launchctl unload ~/Library/LaunchAgents/${PLIST_NAME}.plist"

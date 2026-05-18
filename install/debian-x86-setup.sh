#!/bin/bash
# debian-x86-setup.sh — one-shot Debian x86 setup for Creation Station Arcade kiosk mode
# For Intel/AMD desktop/laptop systems (NOT Raspberry Pi)
# This script:
#   1. Installs required packages
#   2. Configures auto-login and Xorg
#   3. Creates runtime folder from git repo
#   4. Sets up Chromium kiosk with proper flags
# Usage: bash install/debian-x86-setup.sh (run from repo root)

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="${REPO_DIR}-run"
LOG="$HOME/arcade-setup.log"
USER_NAME=$(whoami)

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Creation Station Arcade Debian x86 Setup ==="
log "Repo: $REPO_DIR"
log "Runtime: $RUN_DIR"
log "User: $USER_NAME"

# ── 0. Verify we're in a git repo ─────────────────────────────────────────────
if [ ! -d "$REPO_DIR/.git" ]; then
    log "ERROR: $REPO_DIR is not a git repo. This script must be run from the cloned repository."
    exit 2
fi

# ── 1. System packages ────────────────────────────────────────────────────────
log "Installing system packages..."
sudo apt-get update -y >> "$LOG" 2>&1
sudo apt-get install -y \
    chromium \
    nodejs \
    npm \
    xserver-xorg \
    xinit \
    openbox \
    unclutter \
    xdotool \
    git \
    mesa-utils \
    >> "$LOG" 2>&1
log "Packages installed."

# ── 2. Verify node ────────────────────────────────────────────────────────────
NODE_VER=$(node --version 2>/dev/null || echo "missing")
log "Node version: $NODE_VER"
if [ "$NODE_VER" = "missing" ]; then
    log "ERROR: node not found after install. Check your apt sources."
    exit 1
fi

# ── 3. Auto-login on TTY1 ─────────────────────────────────────────────────────
log "Configuring auto-login on TTY1..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
sudo systemctl daemon-reload
log "Auto-login configured for user: $USER_NAME"

# ── 4. Auto-start Xorg on TTY1 ───────────────────────────────────────────────
log "Configuring Xorg to start on TTY1..."
PROFILE="$HOME/.bash_profile"

# Add startx block first (before DISPLAY export, since we check -z "$DISPLAY")
STARTX_BLOCK='# Auto-start X on TTY1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi

# DISPLAY for X sessions
export DISPLAY=:0'

if ! grep -qF "exec startx" "$PROFILE" 2>/dev/null; then
    echo "$STARTX_BLOCK" >> "$PROFILE"
fi

# ── 5. Xorg config (openbox, no login manager) ───────────────────────────────
XINITRC="$HOME/.xinitrc"
cat > "$XINITRC" <<'XEOF'
#!/bin/sh
# Hide cursor after 1s of inactivity
unclutter -idle 1 -root &
# Disable screen saver / blanking
xset s off
xset s noblank
xset -dpms
# Let openbox manage the window (bare WM for kiosk)
exec openbox-session
XEOF
chmod +x "$XINITRC"
log "Xorg startx configured."

# ── 6. Create runtime folder (sync from repo) ────────────────────────────────
log "Creating runtime folder at $RUN_DIR..."
mkdir -p "$RUN_DIR"

if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude "arcade.log" "$REPO_DIR"/ "$RUN_DIR"/
else
    cp -a "$REPO_DIR"/ "$RUN_DIR"/
fi

chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/simpleLaunch.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/pullFromGit.sh" 2>/dev/null || true
log "Runtime folder created."

# ── 7. Create x86-optimized launcher ──────────────────────────────────────────
log "Creating x86-optimized launcher..."
cat > "$RUN_DIR/launcher.sh" <<LAUNCHER_EOF
#!/bin/bash
# launcher.sh - x86 Debian optimized launcher for Creation Station Arcade
# Run from runtime folder: cd ~/CreationStationArcade-run && bash launcher.sh

LOG_FILE="\$HOME/arcade.log"
PID_FILE="/tmp/arcade-server.pid"
CHROMIUM_PID_FILE="/tmp/arcade-chromium.pid"

# Find chromium
CHROMIUM_BIN=\$(which chromium 2>/dev/null || which chromium-browser 2>/dev/null || which google-chrome 2>/dev/null)

if [ -z "\$CHROMIUM_BIN" ]; then
    echo "[\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Chromium not found" >> \$LOG_FILE
    exit 1
fi

echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Using Chromium: \$CHROMIUM_BIN" >> \$LOG_FILE

# Kill any existing processes
kill \$(cat \$PID_FILE 2>/dev/null) 2>/dev/null || true
kill \$(cat \$CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
sleep 1

# Start Node server
echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Starting Node server..." >> \$LOG_FILE
cd "\$(dirname "\$0")"
node server.js >> \$LOG_FILE 2>&1 &
SERVER_PID=\$!
echo \$SERVER_PID > \$PID_FILE

# Wait for server
echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Waiting for server..." >> \$LOG_FILE
for i in {1..30}; do
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Server ready" >> \$LOG_FILE
        break
    fi
    sleep 1
done

# Check GPU acceleration
echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Checking GPU acceleration..." >> \$LOG_FILE
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo | grep -E "(direct rendering|OpenGL renderer)" >> \$LOG_FILE 2>&1 || echo "No glxinfo output" >> \$LOG_FILE
else
    echo "glxinfo not available" >> \$LOG_FILE
fi

echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Launching Chromium kiosk" >> \$LOG_FILE
"\$CHROMIUM_BIN" \\
    --user-data-dir=/tmp/chromium-arcade \\
    --kiosk \\
    --app=http://localhost:3000 \\
    --noerrdialogs \\
    --disable-infobars \\
    --no-first-run \\
    --disable-session-crashed-bubble \\
    --disable-features=TranslateUI \\
    --no-default-browser-check \\
    --disable-pinch \\
    --disable-extensions \\
    --disable-background-networking \\
    --disable-sync \\
    --disable-default-apps \\
    --disable-component-extensions-with-background-pages \\
    --enable-gpu-rasterization \\
    --enable-zero-copy \\
    --ignore-gpu-blacklist \\
    http://localhost:3000 >> \$LOG_FILE 2>&1 &

CHROMIUM_PID=\$!
echo \$CHROMIUM_PID > \$CHROMIUM_PID_FILE

echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Chromium started (PID: \$CHROMIUM_PID)" >> \$LOG_FILE
wait \$CHROMIUM_PID
echo "[\$(date +'%Y-%m-%d %H:%M:%S')] Chromium exited" >> \$LOG_FILE

# Cleanup
kill \$SERVER_PID 2>/dev/null || true
rm -f \$PID_FILE \$CHROMIUM_PID_FILE
LAUNCHER_EOF

chmod +x "$RUN_DIR/launcher.sh"
log "x86 launcher created."

# ── 8. Openbox autostart — launch the arcade ─────────────────────────────────
OPENBOX_DIR="$HOME/.config/openbox"
mkdir -p "$OPENBOX_DIR"
cat > "$OPENBOX_DIR/autostart" <<OEOF
# Creation Station Arcade kiosk autostart
# Runtime folder: $RUN_DIR
$RUN_DIR/launcher.sh &
OEOF
log "Openbox autostart configured."

# ── 9. Suppress boot messages (Debian x86 paths) ────────────────────────────
log "Suppressing boot messages..."
# Debian uses /etc/default/grub for kernel parameters
if [ -f /etc/default/grub ]; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash"/' /etc/default/grub 2>/dev/null || \
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash"/' /etc/default/grub 2>/dev/null || \
    sudo sed -i '$aGRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash"' /etc/default/grub 2>/dev/null || true
    sudo update-grub 2>/dev/null || log "WARNING: Could not update GRUB"
    log "Boot quiet flags configured."
else
    log "WARNING: /etc/default/grub not found; skipping boot flag update."
fi

log "=== Setup complete. Reboot to activate. ==="
echo ""
echo "Run: sudo reboot"
echo ""
echo "After reboot, the arcade will auto-start."
echo "Runtime folder: $RUN_DIR"
echo "Source folder:  $REPO_DIR"
echo ""
echo "To manually test first:"
echo "  cd $RUN_DIR && bash launcher.sh"

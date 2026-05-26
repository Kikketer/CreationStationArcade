#!/bin/bash
# debian-x86-setup.sh — one-shot Debian x86 setup for Creation Station Arcade kiosk mode
# For Intel/AMD desktop/laptop systems (NOT Raspberry Pi)
# Uses dual-chromium architecture: menu Chromium (always-on) + game Chromium (spawned)
# Assumes standard USB gamepads (no GPIO)
#
# This script:
#   1. Installs required packages
#   2. Configures auto-login and Xorg
#   3. Creates runtime folder from git repo
#   4. Sets up dual-chromium kiosk with menu-launcher.sh
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
    unclutter \
    xdotool \
    git \
    rsync \
    mesa-utils \
    alsa-utils \
    pulseaudio \
    pulseaudio-utils \
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

# Use 'startx' without 'exec' to avoid login loop issues
STARTX_BLOCK='# Auto-start X on TTY1 (Debian x86 kiosk)
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # Wait for network before starting
    until ping -c1 8.8.8.8 >/dev/null 2>&1; do
        echo "Waiting for network..."
        sleep 2
    done
    startx -- -nocursor
fi

# DISPLAY for X sessions
export DISPLAY=:0'

if ! grep -qF "startx -- -nocursor" "$PROFILE" 2>/dev/null; then
    # Remove old exec startx blocks if present
    sed -i '/exec startx/d' "$PROFILE" 2>/dev/null || true
    echo "$STARTX_BLOCK" >> "$PROFILE"
fi

# ── 5. Xorg config (.xinitrc runs menu-launcher from runtime folder) ──────────
XINITRC="$HOME/.xinitrc"
cat > "$XINITRC" <<XEOF
#!/bin/bash
# Start audio system
pulseaudio --start 2>/dev/null || true

# Disable screen blanking and power management
xset s off
xset s noblank
xset -dpms

# Hide cursor
unclutter -idle 0.1 -root &

# Launch arcade from runtime folder (dual-chromium mode)
RUN_DIR="$RUN_DIR"
if [ -f "\$RUN_DIR/menu-launcher.sh" ]; then
    cd "\$RUN_DIR"
    exec bash menu-launcher.sh
else
    # Fallback if runtime folder not ready
    echo "ERROR: Runtime folder not found at \$RUN_DIR" > /tmp/xinitrc-error
    exec xterm
fi
XEOF
chmod +x "$XINITRC"
log ".xinitrc configured for dual-chromium mode."

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
chmod +x "$RUN_DIR/menu-launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/kill-to-menu.sh" 2>/dev/null || true
log "Runtime folder created."

# ── 7. Create x86 menu-launcher (dual-chromium) ─────────────────────────────
log "Creating x86-optimized menu-launcher..."
cat > "$RUN_DIR/menu-launcher.sh" <<LAUNCHER_EOF
#!/bin/bash
# menu-launcher.sh - x86 Debian dual-chromium launcher
# Menu Chromium (always-on) + Game Chromium (spawned by server.js)

LOG_FILE="\$HOME/arcade.log"
PID_FILE="/tmp/arcade-server.pid"
MENU_CHROMIUM_PID_FILE="/tmp/arcade-menu-chromium.pid"

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RUN_DIR="\$SCRIPT_DIR"
SOURCE_DIR="\${CSA_SOURCE_DIR:-\${RUN_DIR%-run}}"

# Find chromium
CHROMIUM_BIN=\$(which chromium 2>/dev/null || which chromium-browser 2>/dev/null || which google-chrome 2>/dev/null)
if [ -z "\$CHROMIUM_BIN" ]; then
    echo "[\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Chromium not found" >> "\$LOG_FILE"
    exit 1
fi

log() {
    echo "[\$(date +'%Y-%m-%d %H:%M:%S')] \$*" | tee -a "\$LOG_FILE"
}

log "=== Menu Launcher Starting (Dual-Chromium Mode) ==="

# Kill any existing processes
kill \$(cat \$PID_FILE 2>/dev/null) 2>/dev/null || true
kill \$(cat \$MENU_CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
sleep 1

# Sync from source if available
if [ -d "\$SOURCE_DIR/.git" ]; then
    log "Syncing from \$SOURCE_DIR to \$RUN_DIR"
    rsync -a --delete --exclude ".git" --exclude "arcade.log" "\$SOURCE_DIR"/ "\$RUN_DIR"/ >> "\$LOG_FILE" 2>&1
    log "Sync complete"
fi

# Start Node server
log "Starting Node server..."
cd "\$RUN_DIR"
node server.js >> "\$LOG_FILE" 2>&1 &
SERVER_PID=\$!
echo \$SERVER_PID > "\$PID_FILE"

# Wait for server
log "Waiting for server..."
for i in {1..30}; do
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        log "Server ready (server.js will spawn game Chromium when needed)"
        break
    fi
    sleep 1
done

# Common Chromium flags
CHROMIUM_FLAGS=(
    --user-data-dir=/tmp/chromium-arcade-menu
    --noerrdialogs
    --disable-infobars
    --no-first-run
    --disable-session-crashed-bubble
    --no-default-browser-check
    --disable-pinch
    --disable-extensions
    --disable-background-networking
    --disable-sync
    --disable-default-apps
    --disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy
    --ignore-gpu-blocklist
    --enable-gpu-rasterization
    --hide-scrollbars
    --suppress-message-center-popups
)

# Launch MENU Chromium (always running, kiosk mode, bottom layer)
log "Launching MENU Chromium (kiosk, always-on)..."
"\$CHROMIUM_BIN" \\
    --user-data-dir=/tmp/chromium-arcade-menu \\
    --kiosk \\
    --window-position=0,0 \\
    --window-size=1920,1080 \\
    --start-fullscreen \\
    "\${CHROMIUM_FLAGS[@]}" \\
    http://localhost:3000/ >> "\$LOG_FILE" 2>&1 &

MENU_PID=\$!
echo \$MENU_PID > "\$MENU_CHROMIUM_PID_FILE"
log "Menu Chromium started (PID: \$MENU_PID)"

# Wait for menu window to appear
sleep 3

# Focus the menu window
if command -v xdotool >/dev/null 2>&1; then
    for winclass in "chromium" "Chromium"; do
        WIN_ID=\$(xdotool search --onlyvisible --class "\$winclass" 2>/dev/null | head -1)
        if [ -n "\$WIN_ID" ]; then
            xdotool windowfocus "\$WIN_ID" 2>/dev/null || true
            xdotool windowactivate "\$WIN_ID" 2>/dev/null || true
            log "Menu window focused"
            break
        fi
    done
fi

# Monitor loop - just keep menu running, server handles game spawning
while true; do
    # Check if menu died (restart if so)
    if ! kill -0 "\$MENU_PID" 2>/dev/null; then
        log "WARNING: Menu Chromium died, restarting..."
        "\$CHROMIUM_BIN" \\
            --user-data-dir=/tmp/chromium-arcade-menu \\
            --kiosk \\
            --window-position=0,0 \\
            --window-size=1920,1080 \\
            --start-fullscreen \\
            "\${CHROMIUM_FLAGS[@]}" \\
            http://localhost:3000/ >> "\$LOG_FILE" 2>&1 &
        MENU_PID=\$!
        echo \$MENU_PID > "\$MENU_CHROMIUM_PID_FILE"
        sleep 3
    fi
    
    sleep 2
done

log "=== Menu Launcher exited ==="
kill \$SERVER_PID 2>/dev/null || true
rm -f "\$PID_FILE" "\$MENU_CHROMIUM_PID_FILE"
LAUNCHER_EOF

chmod +x "$RUN_DIR/menu-launcher.sh"
log "x86 menu-launcher (dual-chromium) created."

# ── 8. Git update service ─────────────────────────────────────────────────────
log "Configuring background git updates..."
sudo tee /etc/systemd/system/arcade-git-update.service > /dev/null <<EOF
[Unit]
Description=Arcade Git Update on Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$USER_NAME
WorkingDirectory=$REPO_DIR
Environment="CSA_SOURCE_DIR=$REPO_DIR"
Environment="RUN_DIR=$RUN_DIR"
ExecStart=/bin/bash $REPO_DIR/pullFromGit.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable arcade-git-update.service
log "Git update service configured."

# ── 9. USB controller stability setup ────────────────────────────────────────
log "Setting up USB controller stability tools..."

# Copy USB controller setup script to runtime
cp -f "$REPO_DIR/setup-usb-controllers.sh" "$RUN_DIR/" 2>/dev/null || true
chmod +x "$RUN_DIR/setup-usb-controllers.sh" 2>/dev/null || true

# Install udev rules template (configured when controllers plugged in)
log "Installing USB controller udev template..."
sudo cp -f "$REPO_DIR/install/usb-controllers.udev" /etc/udev/rules.d/99-arcade-controllers.rules 2>/dev/null || {
    # Create minimal template if file doesn't exist
    sudo tee /etc/udev/rules.d/99-arcade-controllers.rules > /dev/null <<'UDEV_EOF'
# USB Arcade Controller Persistent Naming
# Run /home/pi/CreationStationArcade-run/setup-usb-controllers.sh 
# after plugging in controllers to configure stable player assignments
#
# Each USB port will always map to the same player number:
#   arcade-p1, arcade-p2, arcade-p3, arcade-p4
#
# Example rule (auto-generated by setup script):
# SUBSYSTEM=="input", KERNEL=="js[0-9]*", ENV{ID_PATH}=="*usb-0:2*", SYMLINK+="input/arcade-p1"
UDEV_EOF
}

sudo udevadm control --reload-rules 2>/dev/null || true

log "USB controller tools installed."
log "After plugging in controllers, run: sudo bash ~/CreationStationArcade-run/setup-usb-controllers.sh"

# ── 10. Suppress boot messages (Debian x86 paths) ───────────────────────────
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
echo "After reboot, the arcade will auto-start in dual-chromium kiosk mode."
echo "Runtime folder: $RUN_DIR"
echo "Source folder:  $REPO_DIR"
echo ""
echo "Dual-chromium architecture:"
echo "  - Menu Chromium: always running (http://localhost:3000/)"
echo "  - Game Chromium: spawned by server.js when game selected"
echo "  - Kill button: returns to menu instantly"
echo ""
echo "USB Controller Setup (after plugging in controllers):"
echo "  sudo bash ~/CreationStationArcade-run/setup-usb-controllers.sh"
echo ""
echo "To manually test first:"
echo "  cd $RUN_DIR && bash menu-launcher.sh"

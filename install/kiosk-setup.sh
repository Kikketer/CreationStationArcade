#!/bin/bash
# kiosk-setup.sh — one-shot Pi 5 setup for Creation Station Arcade kiosk mode
# This script:
#   1. Installs required packages
#   2. Configures auto-login and Xorg (with Pi 5 GPU fix)
#   3. Creates runtime folder from git repo
#   4. Configures boot messages
# Usage: bash install/kiosk-setup.sh (run from repo root)

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="${REPO_DIR}-run"
LOG="$HOME/arcade-setup.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Creation Station Arcade Kiosk Setup ==="
log "Repo: $REPO_DIR"
log "Runtime: $RUN_DIR"

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
    xorg \
    unclutter \
    xdotool \
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
ExecStart=-/sbin/agetty --autologin pi --noclear %I \$TERM
EOF
sudo systemctl daemon-reload
log "Auto-login configured."

# ── 4. Pi 5 X11 config (fixes "Cannot run in framebuffer mode" error) ───────
log "Creating Pi 5 X11 configuration..."
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-pi-kiosk.conf > /dev/null <<'XEOF'
Section "Device"
    Identifier  "Card0"
    Driver      "modesetting"
    Option      "kmsdev" "/dev/dri/card1"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "Card0"
EndSection

Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
XEOF
sudo chmod 644 /etc/X11/xorg.conf.d/99-pi-kiosk.conf
log "Pi 5 X11 config created."

# ── 5. Auto-start Xorg on TTY1 ───────────────────────────────────────────────
log "Configuring Xorg to start on TTY1..."
PROFILE="$HOME/.bash_profile"

# Use 'startx' without 'exec' to avoid login loop issues
STARTX_BLOCK='# Auto-start X on TTY1 (Pi 5 kiosk)
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # Wait for network before starting
    until ping -c1 forthelearnofit.com >/dev/null 2>&1; do
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
log ".bash_profile configured."

# ── 6. Xorg config (.xinitrc runs launcher from runtime folder) ─────────────
XINITRC="$HOME/.xinitrc"
cat > "$XINITRC" <<XEOF
#!/bin/bash
# Disable screen blanking and power management
xset s off
xset s noblank
xset -dpms

# Hide cursor
unclutter -idle 0.1 -root &

# Launch arcade from runtime folder
RUN_DIR="$RUN_DIR"
if [ -f "\$RUN_DIR/launcher.sh" ]; then
    cd "\$RUN_DIR"
    exec bash launcher.sh
else
    # Fallback if runtime folder not ready
    echo "ERROR: Runtime folder not found at \$RUN_DIR" > /tmp/xinitrc-error
    exec xterm
fi
XEOF
chmod +x "$XINITRC"
log ".xinitrc configured."

# ── 7. Create runtime folder (sync from repo) ────────────────────────────────
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
chmod +x "$RUN_DIR/install/hdmi-audio-fix.sh" 2>/dev/null || true
log "Runtime folder created."

# ── 8. Git update service ─────────────────────────────────────────────────────
log "Configuring background git updates..."
# Create systemd service for git pull on boot
sudo tee /etc/systemd/system/arcade-git-update.service > /dev/null <<EOF
[Unit]
Description=Arcade Git Update on Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=pi
WorkingDirectory=$REPO_DIR
Environment="CSA_SOURCE_DIR=$REPO_DIR"
Environment="RUN_DIR=$RUN_DIR"
ExecStart=$REPO_DIR/pullFromGit.sh
ExecStartPost=/bin/bash -c 'if command -v rsync >/dev/null 2>&1; then rsync -a --delete --exclude ".git" --exclude "arcade.log" "$REPO_DIR"/ "$RUN_DIR"/; else cp -a "$REPO_DIR"/ "$RUN_DIR"/; fi'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable arcade-git-update.service
log "Git update service configured."

# ── 9. Suppress boot messages ─────────────────────────────────────────────────
log "Suppressing boot messages..."
CMDLINE="/boot/cmdline.txt"
if [ -f "$CMDLINE" ]; then
    # Remove any existing quiet/flags first (idempotent), then add fresh
    sudo sed -i 's/ quiet loglevel=3 vt.global_cursor_default=0//g' "$CMDLINE"
    sudo sed -i 's/ quiet//g' "$CMDLINE"
    sudo sed -i 's/$/ quiet loglevel=3 vt.global_cursor_default=0/' "$CMDLINE"
    log "Boot quiet flags configured."
else
    log "WARNING: $CMDLINE not found; skipping boot flag update."
fi

log "=== Setup complete. Reboot to activate. ==="
echo ""
echo "Run: sudo reboot"
echo ""
echo "After reboot, the arcade will auto-start."
echo "Runtime folder: $RUN_DIR"
echo "Source folder:  $REPO_DIR"

#!/bin/bash
# kiosk-setup.sh — one-shot Pi setup for Creation Station Arcade kiosk mode
# This script:
#   1. Installs required packages
#   2. Configures auto-login and Xorg
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
    openbox \
    unclutter \
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
chmod +x "$RUN_DIR/install/hdmi-audio-fix.sh" 2>/dev/null || true
log "Runtime folder created."

# ── 7. Openbox autostart — launch the arcade ─────────────────────────────────
OPENBOX_DIR="$HOME/.config/openbox"
mkdir -p "$OPENBOX_DIR"
cat > "$OPENBOX_DIR/autostart" <<OEOF
# Creation Station Arcade kiosk autostart
# Runtime folder: $RUN_DIR
$RUN_DIR/launcher.sh &
OEOF
log "Openbox autostart configured."

# ── 8. Suppress boot messages ─────────────────────────────────────────────────
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

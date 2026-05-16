#!/bin/bash
# kiosk-setup.sh — one-shot Pi setup for Creation Station Arcade kiosk mode
# Run once as the pi user after cloning the repo.
# Usage: bash install/kiosk-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$HOME/arcade-setup.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Creation Station Arcade Kiosk Setup ==="
log "Repo dir: $SCRIPT_DIR"

# ── 1. System packages ────────────────────────────────────────────────────────
log "Installing system packages..."
sudo apt-get update -y >> "$LOG" 2>&1
sudo apt-get install -y \
    chromium-browser \
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

# ── 4. Set launcher.sh as login shell ─────────────────────────────────────────
log "Configuring .bash_profile to launch arcade on login..."
PROFILE="$HOME/.bash_profile"
LAUNCHER_LINE="exec $SCRIPT_DIR/launcher.sh"
grep -qF "$LAUNCHER_LINE" "$PROFILE" 2>/dev/null || echo "$LAUNCHER_LINE" >> "$PROFILE"
log ".bash_profile updated."

# ── 5. DISPLAY env for kiosk ─────────────────────────────────────────────────
# launcher.sh needs DISPLAY if running without a desktop session manager.
# We inject it here so Chromium can find the X display.
DISPLAY_LINE="export DISPLAY=:0"
grep -qF "$DISPLAY_LINE" "$PROFILE" 2>/dev/null || \
    sed -i "1i $DISPLAY_LINE" "$PROFILE"

# ── 6. Xorg auto-start (openbox, no login manager) ───────────────────────────
log "Configuring Xorg to start on TTY1..."
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

# Add startx to .bash_profile if TTY1 and not already in a graphical session
STARTX_BLOCK='if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi'
grep -qF "exec startx" "$PROFILE" 2>/dev/null || echo "$STARTX_BLOCK" >> "$PROFILE"
log "Xorg startx configured."

# ── 7. Openbox autostart — launch the arcade ─────────────────────────────────
OPENBOX_DIR="$HOME/.config/openbox"
mkdir -p "$OPENBOX_DIR"
cat > "$OPENBOX_DIR/autostart" <<OEOF
# Creation Station Arcade kiosk autostart
$SCRIPT_DIR/launcher.sh &
OEOF
log "Openbox autostart configured."

# ── 8. Suppress boot messages ─────────────────────────────────────────────────
log "Suppressing boot messages..."
CMDLINE="/boot/cmdline.txt"
if [ -f "$CMDLINE" ]; then
    if ! grep -q "quiet" "$CMDLINE"; then
        sudo sed -i 's/$/ quiet loglevel=3 vt.global_cursor_default=0/' "$CMDLINE"
        log "Boot quiet flags added."
    else
        log "Boot quiet flags already present."
    fi
else
    log "WARNING: $CMDLINE not found; skipping boot flag update."
fi

log "=== Setup complete. Reboot to activate. ==="
echo ""
echo "Run: sudo reboot"

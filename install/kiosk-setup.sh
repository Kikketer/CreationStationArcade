#!/bin/bash
# kiosk-setup.sh — one-shot Pi 5 setup for Creation Station Arcade kiosk mode
# This script:
#   1. Installs required packages
#   2. Configures auto-login and Xorg (with Pi 5 GPU fix)
#   3. Creates runtime folder from git repo
#   4. Configures boot messages
# Usage: bash install/kiosk-setup.sh [--gpio-controllers] (run from repo root)
#
# Options:
#   --gpio-controllers  Enable GPIO virtual gamepads (RPi.GPIO + uhid)
#                       Without this flag, setup assumes standard USB controllers

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="${REPO_DIR}-run"
LOG="$HOME/arcade-setup.log"

# Parse arguments
GPIO_CONTROLLERS=false
for arg in "$@"; do
    case $arg in
        --gpio-controllers)
            GPIO_CONTROLLERS=true
            shift
            ;;
        --help|-h)
            echo "Usage: bash install/kiosk-setup.sh [--gpio-controllers]"
            echo ""
            echo "Options:"
            echo "  --gpio-controllers  Enable GPIO virtual gamepads"
            echo "                      (requires RPi.GPIO + uhid Python module)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Without --gpio-controllers, setup assumes standard USB gamepads."
            exit 0
            ;;
    esac
done

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Creation Station Arcade Kiosk Setup ==="
log "Repo: $REPO_DIR"
log "Runtime: $RUN_DIR"
log "GPIO Controllers: $GPIO_CONTROLLERS"

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

# ── 8. GPIO virtual gamepad setup (optional) ──────────────────────────────────
if [ "$GPIO_CONTROLLERS" = true ]; then
    log "Setting up GPIO virtual gamepads..."
    
    # Install Python dependencies
    log "Installing Python dependencies..."
    sudo apt-get install -y python3-pip python3-rpi.gpio >> "$LOG" 2>&1
    
    # Install uhid Python module
    log "Installing uhid Python module..."
    sudo pip3 install uhid --break-system-packages >> "$LOG" 2>&1 || {
        log "WARNING: Failed to install uhid module. GPIO gamepads may not work."
    }
    
    # Load and enable uhid kernel module
    log "Configuring uhid kernel module..."
    sudo modprobe uhid 2>/dev/null || log "WARNING: Could not load uhid module"
    echo "uhid" | sudo tee /etc/modules-load.d/uhid.conf > /dev/null
    
    # Copy GPIO gamepad files to runtime
    log "Copying GPIO gamepad files to runtime..."
    cp -f "$REPO_DIR/gpio-gamepad.py" "$RUN_DIR/" 2>/dev/null || true
    cp -f "$REPO_DIR/arcade.cfg" "$RUN_DIR/" 2>/dev/null || true
    
    # Install systemd service
    log "Installing gpio-gamepad systemd service..."
    sudo cp -f "$REPO_DIR/gpio-gamepad.service" /etc/systemd/system/
    sudo systemctl daemon-reload >> "$LOG" 2>&1
    sudo systemctl enable gpio-gamepad.service >> "$LOG" 2>&1
    sudo systemctl start gpio-gamepad.service >> "$LOG" 2>&1 || {
        log "WARNING: Could not start gpio-gamepad service (may need reboot)"
    }
    
    log "GPIO virtual gamepad setup complete."
    log "Verify with: ls /dev/input/js* after reboot"
else
    log "Skipping GPIO setup (--gpio-controllers not specified)"
    log "Assuming standard USB controllers will be used"
fi

# ── 9. USB controller stability setup (standard USB mode) ─────────────────────
if [ "$GPIO_CONTROLLERS" = false ]; then
    log "Setting up USB controller stability tools..."
    
    # Copy USB controller setup script to runtime
    cp -f "$REPO_DIR/setup-usb-controllers.sh" "$RUN_DIR/" 2>/dev/null || true
    chmod +x "$RUN_DIR/setup-usb-controllers.sh" 2>/dev/null || true
    
    # Install udev rules template (empty - rules created when controllers plugged in)
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
    log "After plugging in controllers, run: sudo bash /home/pi/CreationStationArcade-run/setup-usb-controllers.sh"
fi

# ── 10. Git update service ────────────────────────────────────────────────────
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
ExecStart=/bin/bash $REPO_DIR/pullFromGit.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable arcade-git-update.service
log "Git update service configured."

# ── 11. Suppress boot messages ────────────────────────────────────────────────
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
if [ "$GPIO_CONTROLLERS" = true ]; then
    echo ""
    echo "GPIO virtual gamepads enabled."
    echo "Verify gamepads: ls /dev/input/js*"
else
    echo ""
    echo "USB Controller Setup (after plugging in controllers):"
    echo "  sudo bash /home/pi/CreationStationArcade-run/setup-usb-controllers.sh"
fi

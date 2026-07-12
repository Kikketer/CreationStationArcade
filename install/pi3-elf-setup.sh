#!/bin/bash
# pi3-elf-setup.sh — one-shot Pi 3 setup for Creation Station Arcade single-game ELF kiosk
# This script:
#   1. Installs required packages
#   2. Configures auto-login on TTY1
#   3. Makes scripts and ELFs executable (runs directly from repo)
#   4. Writes ~/.bash_profile and ~/.profile to auto-launch the game on boot
#   5. Installs a systemd service for monitor_kill.py (reset button)
#   6. Suppresses boot messages
#
# Usage: bash install/pi3-elf-setup.sh --game=GameName (run from repo root)
#
# Options:
#   --game=GameName   ELF game to launch (filename without .elf, must exist in games/)
#                     Default: AndyPaddleTheRiver
#   --help, -h        Show this help

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$HOME/arcade-setup.log"
GAME_NAME="AndyPaddleTheRiver"

for arg in "$@"; do
    case $arg in
        --game=*)
            GAME_NAME="${arg#--game=}"
            shift
            ;;
        --help|-h)
            sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Pi 3 ELF Kiosk Setup ==="
log "Repo: $REPO_DIR"
log "Game: $GAME_NAME"

# ── 0. Check kernel compatibility ────────────────────────────────────────────
if ! grep -q "^Hardware" /proc/cpuinfo 2>/dev/null; then
    log "WARNING: 'Hardware' line not found in /proc/cpuinfo."
    log "The MakeCode Arcade ELF requires this line to run."
    log "Your kernel may be too new. Avoid running 'sudo apt upgrade' on this Pi."
    log "Continuing setup, but the ELF may fail to launch after reboot."
    echo ""
    echo "  To verify after reboot: grep Hardware /proc/cpuinfo"
    echo "  Expected:               Hardware : BCM2835"
    echo ""
fi

# ── 1. Verify git repo ────────────────────────────────────────────────────────
if [ ! -d "$REPO_DIR/.git" ]; then
    log "ERROR: $REPO_DIR is not a git repo. Run from the cloned repository."
    exit 2
fi

# ── 1. Verify game ELF exists ─────────────────────────────────────────────────
if [ ! -f "$REPO_DIR/games/${GAME_NAME}.elf" ]; then
    log "ERROR: games/${GAME_NAME}.elf not found in repo."
    log "Available games:"
    ls "$REPO_DIR/games/"*.elf 2>/dev/null | xargs -n1 basename | sed 's/\.elf//' | sed 's/^/  /' || true
    exit 2
fi

# ── 2. System packages ────────────────────────────────────────────────────────
log "Installing system packages (skipping apt update to preserve kernel version)..."
sudo apt-get install -y \
    python3-rpi.gpio \
    >> "$LOG" 2>&1
log "Packages installed."

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

# ── 3b. uinput permissions ────────────────────────────────────────────────────
log "Setting up uinput permissions..."
sudo modprobe uinput
# Persist uinput module load on boot
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf > /dev/null
echo 'KERNEL=="uinput", MODE="0660", GROUP="input"' | sudo tee /etc/udev/rules.d/99-uinput.rules > /dev/null
sudo usermod -aG input pi
sudo udevadm control --reload-rules
sudo udevadm trigger
# Allow pi to run usb-to-gpio.py as root without password
echo "pi ALL=(ALL) NOPASSWD: /usr/bin/python3 $REPO_DIR/usb-to-gpio.py *" | sudo tee /etc/sudoers.d/arcade-uinput > /dev/null
sudo chmod 440 /etc/sudoers.d/arcade-uinput
log "uinput permissions set."

# ── 4a. Create /sd/arcade.cfg (ELF reads input config from here) ─────────────
log "Creating /sd/arcade.cfg (keyboard scan code layout for USB gamepad)..."
sudo mkdir -p /sd
sudo cp -f "$REPO_DIR/sd-arcade.cfg" /sd/arcade.cfg
sudo chmod 644 /sd/arcade.cfg
log "/sd/arcade.cfg created."

# ── 4. Make scripts and ELFs executable ──────────────────────────────────────
log "Setting permissions..."
chmod +x "$REPO_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$REPO_DIR/simpleLaunch.sh" 2>/dev/null || true
chmod +x "$REPO_DIR/monitor_kill.py" 2>/dev/null || true
chmod +x "$REPO_DIR/usb-to-gpio.py" 2>/dev/null || true
find "$REPO_DIR/games" -name "*.elf" -exec chmod +x {} \; 2>/dev/null || true
log "Permissions set."

# ── 5. Auto-launch on TTY1 login ─────────────────────────────────────────────
log "Configuring auto-launch on TTY1 login..."

LAUNCH_BLOCK="# Auto-launch arcade game on TTY1
if [ \"\$(tty)\" = \"/dev/tty1\" ]; then
    export SINGLE_GAME_NAME=\"$GAME_NAME\"
    cd \"$REPO_DIR\"
    exec bash launcher.sh
fi"

for PROFILE in "$HOME/.bash_profile" "$HOME/.profile"; do
    if ! grep -qF "exec bash launcher.sh" "$PROFILE" 2>/dev/null; then
        echo "$LAUNCH_BLOCK" >> "$PROFILE"
        log "Launch block written to $PROFILE"
    else
        # Update the game name in case it changed
        sed -i "s/SINGLE_GAME_NAME=.*/SINGLE_GAME_NAME=\"$GAME_NAME\"/" "$PROFILE"
        log "Game name updated in $PROFILE"
    fi
done

# ── 6. Systemd service for monitor_kill.py ────────────────────────────────────
log "Installing monitor_kill systemd service..."
sudo tee /etc/systemd/system/arcade-monitor.service > /dev/null <<EOF
[Unit]
Description=Creation Station Arcade Reset Monitor
After=multi-user.target

[Service]
Type=simple
User=pi
WorkingDirectory=$REPO_DIR
Environment="SINGLE_GAME_NAME=$GAME_NAME"
ExecStart=/usr/bin/python3 $REPO_DIR/monitor_kill.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload >> "$LOG" 2>&1
sudo systemctl enable arcade-monitor.service >> "$LOG" 2>&1
sudo systemctl start arcade-monitor.service >> "$LOG" 2>&1 || {
    log "WARNING: Could not start arcade-monitor service (may need reboot)"
}
log "arcade-monitor service installed."

# ── 7. Suppress boot messages ─────────────────────────────────────────────────
log "Suppressing boot messages..."
# Bookworm/Trixie uses /boot/firmware/cmdline.txt; older images use /boot/cmdline.txt
if [ -f "/boot/firmware/cmdline.txt" ]; then
    CMDLINE="/boot/firmware/cmdline.txt"
else
    CMDLINE="/boot/cmdline.txt"
fi
if [ -f "$CMDLINE" ]; then
    sudo sed -i 's/ quiet loglevel=3 vt.global_cursor_default=0//g' "$CMDLINE"
    sudo sed -i 's/ quiet//g' "$CMDLINE"
    sudo sed -i 's/$/ quiet loglevel=3 vt.global_cursor_default=0/' "$CMDLINE"
    log "Boot quiet flags set."
else
    log "WARNING: $CMDLINE not found; skipping."
fi

log "=== Setup complete. Reboot to activate. ==="
echo ""
echo "Run: sudo reboot"
echo ""
echo "After reboot, the arcade will auto-launch: $GAME_NAME"
echo "Repo: $REPO_DIR"
echo ""
echo "To change the game, re-run:"
echo "  bash install/pi3-elf-setup.sh --game=YourGameName"
echo ""
echo "Available games:"
ls "$REPO_DIR/games/"*.elf 2>/dev/null | xargs -n1 basename | sed 's/\.elf//' | sed 's/^/  /' || true

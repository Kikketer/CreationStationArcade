#!/bin/bash
# debian-x86-setup.sh — one-shot Debian x86 setup for Creation Station Arcade kiosk mode
# For Intel/AMD desktop/laptop systems (NOT Raspberry Pi)
# Single-window architecture: one kiosk Chromium; games swap in via iframe
# Assumes standard USB gamepads (no GPIO)
#
# This script:
#   1. Installs required packages
#   2. Configures auto-login and Xorg
#   3. Creates runtime folder from git repo
#   4. Sets up single-window kiosk with menu-launcher.sh + Plymouth splash
# Usage: bash install/debian-x86-setup.sh (run from repo root)

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="${REPO_DIR}-run"
# The kiosk user is whoever invoked the script — via sudo too ($SUDO_USER).
# Running as root must never make root the kiosk user: autologin and all
# user files resolve to the real account instead.
USER_NAME="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
[ -n "$USER_HOME" ] || USER_HOME="$(eval echo "~$USER_NAME")"
LOG="$USER_HOME/arcade-setup.log"

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
    python3 \
    xserver-xorg \
    xinit \
    unclutter \
    openbox \
    xdotool \
    git \
    rsync \
    mesa-utils \
    alsa-utils \
    pulseaudio \
    pulseaudio-utils \
    feh \
    plymouth \
    plymouth-themes \
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
PROFILE="$USER_HOME/.bash_profile"

# Use 'startx' without 'exec' to avoid login loop issues
STARTX_BLOCK='# Auto-start X on TTY1 (Debian x86 kiosk)
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

# ── 5. Xorg config (.xinitrc runs menu-launcher from runtime folder) ──────────
XINITRC="$USER_HOME/.xinitrc"
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

# Minimal window manager: without one, Chromium can't honor
# fullscreen/kiosk state and window geometry gets ignored.
openbox &

# With no display manager nothing else quits Plymouth — release the
# framebuffer before X takes the VT (no-op when Plymouth isn't running).
plymouth quit 2>/dev/null || true

# Splash bridge: paint the boot logo on the root window so there's no black
# gap between Plymouth quitting and Chromium first paint.
RUN_DIR="$RUN_DIR"
feh --bg-scale "\$RUN_DIR/install/splash.png" 2>/dev/null || true

# Launch arcade from runtime folder (single-window kiosk)
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
chown "$USER_NAME:$USER_NAME" "$XINITRC" "$PROFILE" 2>/dev/null || true
log ".xinitrc configured for single-window mode."

# ── 6. Create runtime folder (sync from repo) ────────────────────────────────
log "Creating runtime folder at $RUN_DIR..."
mkdir -p "$RUN_DIR"

if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude "arcade.log" --exclude "__pycache__" --exclude "*.pyc" "$REPO_DIR"/ "$RUN_DIR"/
else
    cp -a "$REPO_DIR"/ "$RUN_DIR"/
fi

chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/pullFromGit.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/menu-launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/kill-to-menu.sh" 2>/dev/null || true
log "Runtime folder created."

# ── 7. Menu launcher ──────────────────────────────────────────────────────────
# The repo's menu-launcher.sh (single-window, user-agnostic paths) is synced
# into the runtime folder and used directly — a generated copy here would be
# overwritten by the boot-time rsync anyway.
chmod +x "$RUN_DIR/menu-launcher.sh"
log "Using repo menu-launcher.sh (single-window)."

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

# ── 9. Games folder + USB game update support ─────────────────────────────────
# All games live in ~/arcade-games — outside the repo and runtime folder, so
# they survive the boot-time git reset + rsync wipe and the repo stays
# machine-agnostic. stock-games/ seeds it; a udev rule starts
# arcade-usb-update@<dev>.service when a USB filesystem is inserted to
# install more games off the drive.
GAMES_DIR="$USER_HOME/arcade-games"

log "Creating games folder at $GAMES_DIR and seeding stock games..."
mkdir -p "$GAMES_DIR"
if [ -d "$REPO_DIR/stock-games" ]; then
    # -n: seed only what's missing — never clobber per-machine files
    # (an edited config.json, USB-installed games, archived stuff).
    cp -an "$REPO_DIR/stock-games/." "$GAMES_DIR/"
fi
chown -R "$USER_NAME:$USER_NAME" "$GAMES_DIR" 2>/dev/null || true
python3 "$REPO_DIR/install/arcade-regen-games.py" "$GAMES_DIR" >> "$LOG" 2>&1 || true

log "Installing USB game-update support..."
sudo cp "$REPO_DIR/install/arcade-usb-update.sh" /usr/local/sbin/arcade-usb-update.sh
sudo chmod 755 /usr/local/sbin/arcade-usb-update.sh
sudo cp "$REPO_DIR/install/arcade-regen-games.py" /usr/local/sbin/arcade-regen-games.py
sudo chmod 755 /usr/local/sbin/arcade-regen-games.py
sudo cp "$REPO_DIR/install/arcade-usb-update@.service" /etc/systemd/system/arcade-usb-update@.service
sudo chmod 644 /etc/systemd/system/arcade-usb-update@.service
sudo cp "$REPO_DIR/install/99-arcade-usb.rules" /etc/udev/rules.d/99-arcade-usb.rules
sudo chmod 644 /etc/udev/rules.d/99-arcade-usb.rules
sudo tee /etc/arcade-usb-update.conf > /dev/null <<EOF
GAMES_DIR="$GAMES_DIR"
ARCADE_USER="$USER_NAME"
EOF
sudo chmod 644 /etc/arcade-usb-update.conf
sudo udevadm control --reload-rules 2>/dev/null || true
sudo systemctl daemon-reload 2>/dev/null || true
log "USB game-update support installed (games install to $GAMES_DIR)."

# ── 10. USB controller stability setup ────────────────────────────────────────
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
# Run setup-usb-controllers.sh (in the runtime folder)
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
log "After plugging in controllers, run: sudo bash $RUN_DIR/setup-usb-controllers.sh"

# ── 11. Plymouth boot splash ──────────────────────────────────────────────
# Repo carries the 'arcade' theme under install/usr/share/plymouth/themes —
# a script theme that paints media/MadeArcadeBoot.png fullscreen. GRUB gets
# 'quiet splash' below, which is what makes Plymouth actually show.
log "Installing Plymouth boot splash..."
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    THEME_DIR="/usr/share/plymouth/themes/arcade"
    sudo mkdir -p "$THEME_DIR"
    sudo cp -a "$REPO_DIR/install/usr/share/plymouth/themes/arcade/." "$THEME_DIR/"
    sudo cp -f "$REPO_DIR/media/MadeArcadeBoot.png" "$THEME_DIR/MadeArcadeBoot.png"
    sudo plymouth-set-default-theme -R arcade >> "$LOG" 2>&1 \
        || log "WARNING: plymouth-set-default-theme failed"
    log "Plymouth theme 'arcade' installed."
else
    log "WARNING: plymouth-set-default-theme not found; skipping boot splash."
fi

# ── 12. Suppress boot messages (Debian x86 paths) ───────────────────────────
log "Suppressing boot messages..."
# Debian uses /etc/default/grub for kernel parameters
if [ -f /etc/default/grub ]; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash vt.global_cursor_default=0"/' /etc/default/grub 2>/dev/null || \
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash vt.global_cursor_default=0"/' /etc/default/grub 2>/dev/null || \
    sudo sed -i '$aGRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash vt.global_cursor_default=0"' /etc/default/grub 2>/dev/null || true
    sudo update-grub 2>/dev/null || log "WARNING: Could not update GRUB"
    log "Boot quiet flags configured."
else
    log "WARNING: /etc/default/grub not found; skipping boot flag update."
fi

# ── 13. Intel TearFree (X11-level vsync) ────────────────────────────────────
# openbox has no compositor, so Chromium tears against the display refresh.
# The modesetting driver's TearFree option fixes it GPU-side — cheap enough
# to be the default on the i3-8100/UHD-630 floor. Only on Intel boxes: the
# section pins the modesetting driver, which would fight NVIDIA/AMD setups.
if lspci 2>/dev/null | grep -Eiq 'vga.*intel|intel.*vga'; then
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/20-intel-tearfree.conf > /dev/null <<'EOF'
Section "Device"
    Identifier "Intel Graphics"
    Driver "modesetting"
    Option "TearFree" "true"
EndSection
EOF
    log "Intel TearFree enabled (Xorg vsync; /etc/X11/xorg.conf.d/20-intel-tearfree.conf)."
else
    log "No Intel GPU detected; skipping TearFree config."
fi

log "=== Setup complete. Reboot to activate. ==="
echo ""
echo "Run: sudo reboot"
echo ""
echo "After reboot, the arcade will auto-start in single-window kiosk mode."
echo "Runtime folder: $RUN_DIR"
echo "Source folder:  $REPO_DIR"
echo ""
echo "Single-window architecture:"
echo "  - One kiosk Chromium (http://localhost:3000/) serves menu + games"
echo "  - Games swap in via iframe; reset button routes back to the menu"
echo "  - Plymouth boot splash hides boot text"
echo ""
echo "USB Controller Setup (after plugging in controllers):"
echo "  sudo bash $RUN_DIR/setup-usb-controllers.sh"
echo ""
echo "To manually test first:"
echo "  cd $RUN_DIR && bash menu-launcher.sh"

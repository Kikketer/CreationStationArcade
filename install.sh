#!/usr/bin/env bash
# Creation Station Arcade unified installer.
#
# No parameters are required for normal use:
#   curl -fsSL https://raw.githubusercontent.com/Kikketer/CreationStationArcade/main/install.sh | bash
#
# The installer intentionally asks questions instead of making people remember
# branch names or command-line flags. Optional flags exist only for automation
# and previewing.

set -Eeuo pipefail

CSA_VERSION="0.1.0"
CSA_REPO_URL="https://github.com/Kikketer/CreationStationArcade.git"

ASSUME_YES=0
DRY_RUN=0
SUDO_KEEPALIVE_PID=""
NATIVE_TMPDIR=""

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_MAGENTA=""
    C_CYAN=""
fi

installer_log() {
    if [ -n "${INSTALL_LOG:-}" ]; then
        printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >> "$INSTALL_LOG" 2>/dev/null || true
    fi
}

info() { printf '%s\n' "$*"; }
dim() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
    printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
    installer_log "ERROR: $*"
    exit 1
}

banner() {
    printf '%s' "${C_CYAN}${C_BOLD}"
    cat <<'EOF'
   ____                _   _               ____  _        _   _
  / ___|_ __ ___  __ _| |_(_) ___  _ __   / ___|| |_ __ _| |_(_) ___  _ __
 | |   | '__/ _ \/ _` | __| |/ _ \| '_ \  \___ \| __/ _` | __| |/ _ \| '_ \
 | |___| | |  __/ (_| | |_| | (_) | | | |  ___) | || (_| | |_| | (_) | | | |
  \____|_|  \___|\__,_|\__|_|\___/|_| |_| |____/ \__\__,_|\__|_|\___/|_| |_|

                    A R C A D E   C A B I N E T   I N S T A L L E R
EOF
    printf '%s\n' "$C_RESET"
}

stage() {
    printf '\n%s== STAGE %s · %s %s\n' "$C_MAGENTA${C_BOLD}" "$1" "$2" "$C_RESET"
    printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s=' {1..62})" "$C_RESET"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

spinner_erase_line() {
    if [ -t 1 ]; then
        printf '\r\033[K'
    fi
}

run_step() {
    local label="$1"
    shift

    installer_log "STEP: $label :: $*"

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$label"
        printf '       %s%s%s\n' "$C_DIM" "$*" "$C_RESET"
        return 0
    fi

    printf '  %s%s%s\n' "$C_BOLD" "$label" "$C_RESET"
    printf '\n[%s] STEP: %s :: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$label" "$*" >> "$INSTALL_LOG"

    local start="$SECONDS"
    "$@" >> "$INSTALL_LOG" 2>&1 &
    local pid=$!

    if [ -t 1 ]; then
        local frames="|/-\\"
        local i=0
        while kill -0 "$pid" 2>/dev/null; do
            local frame="${frames:i%4:1}"
            printf '\r  %s %s %2ds' "$frame" "$label" "$((SECONDS - start))"
            sleep 0.12
            i=$((i + 1))
        done
    else
        dim "  running..."
    fi

    local status=0
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi

    spinner_erase_line
    if [ "$status" -eq 0 ]; then
        printf '  %s✓%s %s %sdone (%ds)%s\n' "$C_GREEN" "$C_RESET" "$label" "$C_DIM" "$((SECONDS - start))" "$C_RESET"
        installer_log "STEP OK: $label"
        return 0
    fi

    printf '  %s✗%s %s failed\n' "$C_RED" "$C_RESET" "$label" >&2
    printf '\n%sLast installer log lines:%s\n' "$C_YELLOW" "$C_RESET" >&2
    tail -n 24 "$INSTALL_LOG" 2>/dev/null | sed 's/^/  /' >&2 || true
    printf '\nFull log: %s\n' "$INSTALL_LOG" >&2
    installer_log "STEP FAILED ($status): $label"
    exit "$status"
}

have_tty_input() {
    [ -r /dev/tty ]
}

read_answer() {
    if ! have_tty_input; then
        die "This installer needs a terminal for its questions. Run it from an interactive shell."
    fi
    local answer=""
    IFS= read -r answer < /dev/tty || return 1
    printf '%s' "$answer"
}

ask_text() {
    local result_var="$1"
    local question="$2"
    local default_value="${3:-}"
    local answer=""

    while true; do
        if [ "$ASSUME_YES" = "1" ] && [ -n "$default_value" ]; then
            answer="$default_value"
        else
            printf '\n%s?%s %s\n' "$C_CYAN" "$C_RESET" "$question"
            if [ -n "$default_value" ]; then
                printf '  %s[%s]%s ' "$C_DIM" "$default_value" "$C_RESET"
            else
                printf '  '
            fi
            answer="$(read_answer)" || die "Input closed."
            [ -n "$answer" ] || answer="$default_value"
        fi

        if [ -n "$answer" ]; then
            printf -v "$result_var" '%s' "$answer"
            return 0
        fi
        warn "A value is required."
    done
}

ask_yes_no() {
    local question="$1"
    local default_answer="${2:-y}"
    local suffix="[Y/n]"
    [ "$default_answer" = "n" ] && suffix="[y/N]"

    if [ "$ASSUME_YES" = "1" ]; then
        [ "$default_answer" = "y" ]
        return
    fi

    local answer=""
    while true; do
        printf '\n%s?%s %s %s ' "$C_CYAN" "$C_RESET" "$question" "$suffix"
        answer="$(read_answer)" || die "Input closed."
        [ -n "$answer" ] || answer="$default_answer"
        case "$answer" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
            *) printf '%sPlease answer y or n.%s\n' "$C_YELLOW" "$C_RESET" ;;
        esac
    done
}

ask_choice() {
    local result_var="$1"
    local question="$2"
    local default_value="$3"
    shift 3

    local -a values=()
    local -a labels=()
    local spec=""
    local value=""
    local label=""
    local i=1

    for spec in "$@"; do
        value="${spec%%|*}"
        label="${spec#*|}"
        values+=("$value")
        labels+=("$label")
    done

    [ "${#values[@]}" -gt 0 ] || die "Internal error: choice list is empty."
    [ -n "$default_value" ] || default_value="${values[0]}"

    if [ "$ASSUME_YES" = "1" ]; then
        printf -v "$result_var" '%s' "$default_value"
        return 0
    fi

    printf '\n%s?%s %s\n' "$C_CYAN" "$C_RESET" "$question"
    for i in "${!values[@]}"; do
        local number=$((i + 1))
        local marker=" "
        [ "${values[$i]}" = "$default_value" ] && marker="*"
        printf '  %s%d)%s %s %s\n' "$C_BOLD" "$number" "$C_RESET" "${labels[$i]}" "$marker"
    done
    printf '  %s* recommended/default%s\n' "$C_DIM" "$C_RESET"

    local answer=""
    while true; do
        printf '  Choose [1-%s, default %s]: ' "${#values[@]}" "$default_value"
        answer="$(read_answer)" || die "Input closed."
        if [ -z "$answer" ]; then
            printf -v "$result_var" '%s' "$default_value"
            return 0
        fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#values[@]}" ]; then
            printf -v "$result_var" '%s' "${values[$((answer - 1))]}"
            return 0
        fi
        for value in "${values[@]}"; do
            if [ "$answer" = "$value" ]; then
                printf -v "$result_var" '%s' "$value"
                return 0
            fi
        done
        printf '%sChoose one of the numbered options.%s\n' "$C_YELLOW" "$C_RESET"
    done
}

classify_machine() {
    local model="$1"
    local arch="$2"
    local model_lc
    model_lc="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"

    case "$model_lc" in
        *"raspberry pi 5"*) printf 'pi5'; return ;;
        *"raspberry pi 4"*) printf 'pi4'; return ;;
        *"raspberry pi zero 2"*) printf 'zero2'; return ;;
        *"raspberry pi zero"*) printf 'zero'; return ;;
        *"raspberry pi 3"*) printf 'pi3'; return ;;
        *"raspberry pi"*) printf 'unknown-pi'; return ;;
    esac

    case "$arch" in
        amd64|x86_64) printf 'x86' ;;
        arm64|aarch64) printf 'other-arm64' ;;
        armhf|armv7l|armv6l) printf 'other-armhf' ;;
        *) printf 'unknown' ;;
    esac
}

machine_is_pi() {
    case "$1" in
        pi3|pi4|pi5|zero|zero2|unknown-pi) return 0 ;;
        *) return 1 ;;
    esac
}

flavor_branch() {
    case "$1" in
        elf-menu) printf 'main' ;;
        elf-single) printf 'pi3-elf-kiosk' ;;
        chromium-menu) printf 'chromium-kiosk' ;;
        chromium-single) printf 'single-game-kiosk' ;;
        native-menu) printf 'multi-native-arcade' ;;
        native-single) printf 'single-native-arcade' ;;
        *) return 1 ;;
    esac
}

flavor_label() {
    case "$1" in
        elf-menu) printf 'ELF menu arcade' ;;
        elf-single) printf 'Single-game ELF kiosk' ;;
        chromium-menu) printf 'Chromium menu arcade' ;;
        chromium-single) printf 'Chromium single-game kiosk' ;;
        native-menu) printf 'Native menu arcade' ;;
        native-single) printf 'Native single-game arcade' ;;
        *) return 1 ;;
    esac
}

flavor_checkout_name() {
    case "$1" in
        native-menu|native-single) printf 'CreationStationArcade' ;;
        *) printf 'CreationStationArcade-src' ;;
    esac
}

# shellcheck disable=SC2088 # the tilde is matched literally, not expanded
expand_user_path() {
    if [ "$1" = "~" ]; then
        printf '%s' "$HOME"
    elif [ "${1:0:2}" = "~/" ]; then
        printf '%s/%s' "$HOME" "${1:2}"
    else
        printf '%s' "$1"
    fi
}

sanitize_game_name() {
    printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
}

configure_autologin() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I linux
EOF
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo cp "$tmp" /etc/systemd/system/getty@tty1.service.d/autologin.conf
    sudo chmod 644 /etc/systemd/system/getty@tty1.service.d/autologin.conf
    sudo systemctl daemon-reload
    rm -f "$tmp"
}

write_elf_menu_autolaunch() {
    local runtime_dir="$1"
    local profile=""
    local begin='# >>> Creation Station Arcade launcher >>>'
    local end='# <<< Creation Station Arcade launcher <<<'

    for profile in "$USER_HOME/.bash_profile" "$USER_HOME/.profile"; do
        touch "$profile"
        if ! grep -qF "$begin" "$profile" 2>/dev/null; then
            cat >> "$profile" <<EOF

$begin
if [ "\$(tty)" = "/dev/tty1" ]; then
    cd "$runtime_dir" || exit 1
    exec bash "$runtime_dir/launcher.sh"
fi
$end
EOF
        fi
    done
}

configure_x86_single_game() {
    local runtime_dir="$1"
    cat > "$USER_HOME/.xinitrc" <<EOF
#!/bin/bash
# Start audio system
pulseaudio --start 2>/dev/null || true

# Disable screen blanking and power management
xset s off
xset s noblank
xset -dpms

# Hide cursor
unclutter -idle 0.1 -root &

# Minimal window manager: without one, Chromium can't honor fullscreen state.
openbox &

export SINGLE_GAME_NAME="$GAME_NAME"
if [ -f "$runtime_dir/single-game-launcher.sh" ]; then
    cd "$runtime_dir"
    exec bash single-game-launcher.sh
else
    echo "ERROR: Runtime folder not found at $runtime_dir" > /tmp/xinitrc-error
    exec xterm
fi
EOF
    chmod +x "$USER_HOME/.xinitrc"
}


count_usb_joysticks() {
    local count=0
    local js=""
    for js in /dev/input/js*; do
        [ -e "$js" ] && count=$((count + 1))
    done
    printf '%s' "$count"
}

prompt_controller_plugin() {
    [ "$CONTROL_MODE" = "usb" ] || return 0

    cat <<EOF

${C_YELLOW}${C_BOLD}CONTROLLER CHECK${C_RESET}
  Plug every USB controller or encoder into the physical USB port where it
  will stay. Those physical ports are what the cabinet uses to decide who is
  Player 1, Player 2, and so on.
EOF
    if ! ask_yes_no "Are the USB controllers plugged into their final ports now" "y"; then
        warn "Continuing, but controller setup may find no devices. You can run it again after plugging them in."
    fi

    local count
    count="$(count_usb_joysticks)"
    if [ "$count" -eq 0 ]; then
        warn "No /dev/input/js* controllers are currently visible. Keyboard-style encoders may not appear there."
    else
        info "  I can see $count USB joystick device(s)."
    fi
}

verify_usb_button_presses() {
    local count="$1"
    [ "$count" -gt 0 ] || return 1
    [ "$count" -le 4 ] || count=4

    python3 - "$count" <<'CSA_PY'
import glob
import os
import select
import struct
import sys
import time

wanted = int(sys.argv[1])
devices = {}
for path in sorted(glob.glob('/dev/input/js*')):
    try:
        devices[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
    except OSError:
        pass
if not devices:
    sys.exit(2)

assigned = set()
for player in range(1, wanted + 1):
    print(f"\n  PLAYER {player}: press the A button now (30 seconds)...", flush=True)
    deadline = time.time() + 30
    found = False
    while time.time() < deadline and not found:
        ready, _, _ = select.select(list(devices), [], [], 0.25)
        for fd in ready:
            try:
                data = os.read(fd, 8)
            except BlockingIOError:
                continue
            if len(data) != 8:
                continue
            _, value, event_type, number = struct.unpack('IhBB', data)
            if fd in assigned:
                continue
            if event_type == 1 and value == 1:
                assigned.add(fd)
                print(f"  Player {player} heard on {devices[fd]} (button {number}).", flush=True)
                found = True
                break
    if not found:
        print(f"  Player {player}: no button press heard; continuing anyway.", flush=True)

for fd in devices:
    os.close(fd)
CSA_PY
}

run_controller_setup() {
    [ "$CONTROL_MODE" = "usb" ] || return 0
    [ "$DRY_RUN" != "1" ] || return 0

    local count
    count="$(count_usb_joysticks)"
    if [ "$count" -gt 0 ] && ask_yes_no "Test the USB buttons now with guided Player 1/2/3/4 presses" "y"; then
        if ! verify_usb_button_presses "$count"; then
            warn "The button test could not read the controllers. You can still configure ports manually."
        fi
    fi

    local setup_script=""
    if [ "$ENGINE" = "chromium" ]; then
        setup_script="${REPO_DIR}-run/setup-usb-controllers.sh"
        if [ ! -f "$setup_script" ]; then
            setup_script="$REPO_DIR/setup-usb-controllers.sh"
        fi
    fi

    if [ -n "$setup_script" ] && [ -f "$setup_script" ]; then
        if ask_yes_no "Map those physical USB ports to stable player numbers now" "y"; then
            printf '\n%sFollow the controller setup prompts below.%s\n' "$C_BOLD" "$C_RESET"
            # shellcheck disable=SC2024 # Redirects intentionally attach the interactive helper to the terminal.
            if sudo bash "$setup_script" < /dev/tty > /dev/tty 2>&1; then
                info "  USB controller port mapping is complete."
            else
                warn "USB controller setup did not complete. Re-run: sudo bash $setup_script"
            fi
        fi
    elif [ "$count" -eq 0 ]; then
        warn "No USB joysticks were detected. If these are keyboard encoders, test them in the arcade after reboot."
    fi
}

install_base_tools() {
    sudo apt-get update -y
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git rsync curl tar file
}

install_openbox_package() {
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y openbox
}

install_pi_elf_support() {
    sudo apt-get update -y
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y python3-rpi.gpio fbset
}

run_native_installer() {
    local installer="$1"
    shift

    if [ "$MACHINE_CLASS" != "x86" ]; then
        sudo bash "$installer" "$@"
        return
    fi

    # Ubuntu/Debian x86 does not publish an amd64 python3-rpi.gpio package.
    # Patch the branch installer only while it runs, then restore the checkout
    # so future git pulls are not blocked by a dirty working tree.
    local backup
    backup="$(mktemp)"
    cp "$installer" "$backup"
    sed -i -e 's/ python3-rpi\.gpio//g' -e 's/,gpio//g' "$installer"

    set +e
    sudo bash "$installer" "$@"
    local status=$?
    set -e

    cp "$backup" "$installer"
    rm -f "$backup"
    return "$status"
}

prepare_checkout() {
    if [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" fetch origin "$BRANCH"
        git -C "$REPO_DIR" checkout "$BRANCH"
        git -C "$REPO_DIR" pull --ff-only origin "$BRANCH"
    else
        if [ -e "$REPO_DIR" ] && [ -n "$(find "$REPO_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
            printf 'ERROR: %s exists but is not a git checkout. Move it aside or choose another machine user.\n' "$REPO_DIR" >&2
            return 2
        fi
        git clone --branch "$BRANCH" "$CSA_REPO_URL" "$REPO_DIR"
    fi
}

extract_native_archives() {
    local archive=""
    local tmp=""
    local root=""
    local game_path=""
    local name=""
    local base=""
    local target=""
    local file_description=""

    : > "$NATIVE_NAMES_FILE"

    for archive in "$@"; do
        root=""
        game_path=""
        [ -f "$archive" ] || { echo "Archive not found: $archive" >&2; return 2; }
        tmp="$(mktemp -d)"
        if ! tar -xzf "$archive" -C "$tmp"; then
            echo "Could not extract $archive" >&2
            return 2
        fi

        if [ -f "$tmp/Game" ]; then
            root="$tmp"
        else
            game_path="$(find "$tmp" -mindepth 2 -maxdepth 3 -type f -name Game | head -n 1)"
            [ -n "$game_path" ] && root="$(dirname "$game_path")"
        fi

        if [ -z "$root" ] || [ ! -f "$root/Game" ] || [ ! -f "$root/libpxt.so" ]; then
            echo "$archive does not contain Game and libpxt.so together." >&2
            return 2
        fi

        if [ "${CSA_SKIP_ARCH_CHECK:-0}" != "1" ]; then
            file_description="$(file "$root/Game")"
            case "$MACHINE_ARCH" in
                arm64|aarch64)
                    printf '%s' "$file_description" | grep -Eiq 'aarch64|ARM aarch64' || {
                        echo "$archive is not an arm64 Game binary." >&2
                        return 2
                    }
                    ;;
                amd64|x86_64)
                    printf '%s' "$file_description" | grep -qi 'x86-64' || {
                        echo "$archive is not an x86-64 Game binary." >&2
                        return 2
                    }
                    ;;
            esac
        fi

        if [ -f "$root/name.txt" ]; then
            name="$(head -n 1 "$root/name.txt")"
        else
            base="$(basename "$archive")"
            base="${base%.tar.gz}"
            base="${base%.tgz}"
            base="${base%-arm64}"
            base="${base%-x86_64}"
            base="${base%-x86-64}"
            name="$base"
        fi
        name="$(sanitize_game_name "$name")"
        case "$name" in
            ''|.|..)
                echo "Could not derive a safe game name from $archive." >&2
                return 2
                ;;
        esac

        target="$REPO_DIR/games/$name"
        rm -rf "$target"
        mkdir -p "$target"
        cp -a "$root/." "$target/"
        chmod +x "$target/Game"
        printf '%s\n' "$name" >> "$NATIVE_NAMES_FILE"
        printf 'Installed native cartridge: %s\n' "$name"
    done
}

select_existing_game() {
    local games_dir="$1"
    local extension="$2"
    local preferred_default="$3"
    local path=""
    local name=""
    local default_value=""
    local -a specs=()

    GAME_NAMES=()
    while IFS= read -r path; do
        name="$(basename "$path")"
        name="${name%."$extension"}"
        GAME_NAMES+=("$name")
    done < <(find "$games_dir" -mindepth 1 -maxdepth 1 -type f -name "*.$extension" | sort)

    [ "${#GAME_NAMES[@]}" -gt 0 ] || die "No .$extension games were found in $games_dir."

    for name in "${GAME_NAMES[@]}"; do
        specs+=("$name|$name")
        [ "$name" = "$preferred_default" ] && default_value="$name"
    done
    [ -n "$default_value" ] || default_value="${GAME_NAMES[0]}"

    ask_choice GAME_NAME "Which cartridge should this cabinet boot?" "$default_value" "${specs[@]}"
}

prepare_native_games() {
    local source
    source="$(expand_user_path "$NATIVE_ARTIFACT_SOURCE")"
    local -a archives=()

    if [[ "$source" =~ ^https?:// ]]; then
        NATIVE_TMPDIR="$(mktemp -d)"
        local url_file="${source%%\?*}"
        url_file="$(basename "$url_file")"
        case "$url_file" in
            *.tar.gz|*.tgz) ;;
            *) url_file="native-game.tar.gz" ;;
        esac
        local download="$NATIVE_TMPDIR/$url_file"
        run_step "Downloading the native cartridge" curl -fL "$source" -o "$download"
        archives+=("$download")
    elif [ -f "$source" ]; then
        archives+=("$source")
    elif [ -d "$source" ]; then
        while IFS= read -r archive; do
            archives+=("$archive")
        done < <(find "$source" -mindepth 1 -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) | sort)
    else
        die "Native game source not found: $source"
    fi

    [ "${#archives[@]}" -gt 0 ] || die "No .tar.gz native game archives found in $source."

    NATIVE_NAMES_FILE="$(mktemp)"
    run_step "Unpacking the native cartridge bay" extract_native_archives "${archives[@]}"

    NATIVE_GAME_NAMES=()
    while IFS= read -r name; do
        [ -n "$name" ] && NATIVE_GAME_NAMES+=("$name")
    done < "$NATIVE_NAMES_FILE"
    [ "${#NATIVE_GAME_NAMES[@]}" -gt 0 ] || die "No native games were installed from the supplied archive(s)."

    if [ "$FLAVOR" = "native-menu" ]; then
        if [ ! -x "$REPO_DIR/games/Menu/Game" ]; then
            die "A native menu cabinet needs a compiled menu archive that installs as games/Menu. Rebuild/copy that archive and run the installer again."
        fi
    else
        if [ "${#NATIVE_GAME_NAMES[@]}" -eq 1 ]; then
            GAME_NAME="${NATIVE_GAME_NAMES[0]}"
        else
            local -a specs=()
            local name=""
            for name in "${NATIVE_GAME_NAMES[@]}"; do
                specs+=("$name|$name")
            done
            ask_choice GAME_NAME "Which native game should boot first?" "${NATIVE_GAME_NAMES[0]}" "${specs[@]}"
        fi
    fi
}

detect_platform() {
    local os_release="${CSA_OS_RELEASE:-/etc/os-release}"
    local cpuinfo="${CSA_CPUINFO:-/proc/cpuinfo}"
    local model_file="${CSA_DEVICE_TREE_MODEL:-/proc/device-tree/model}"

    OS_PRETTY="unknown Linux"
    OS_ID="unknown"
    OS_ID_LIKE=""
    if [ -f "$os_release" ]; then
        OS_PRETTY="$(grep -m1 '^PRETTY_NAME=' "$os_release" | cut -d= -f2- | tr -d '"' || true)"
        OS_ID="$(grep -m1 '^ID=' "$os_release" | cut -d= -f2- | tr -d '"' || true)"
        OS_ID_LIKE="$(grep -m1 '^ID_LIKE=' "$os_release" | cut -d= -f2- | tr -d '"' || true)"
        [ -n "$OS_PRETTY" ] || OS_PRETTY="unknown Linux"
    fi

    MACHINE_ARCH="${CSA_ARCH:-}"
    if [ -z "$MACHINE_ARCH" ]; then
        MACHINE_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    fi

    MACHINE_MODEL=""
    if [ -f "$model_file" ]; then
        MACHINE_MODEL="$(tr -d '\0' < "$model_file" 2>/dev/null || true)"
    fi
    if [ -z "$MACHINE_MODEL" ] && [ -f "$cpuinfo" ]; then
        MACHINE_MODEL="$(grep -m1 '^Model' "$cpuinfo" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || true)"
    fi
    if [ -z "$MACHINE_MODEL" ]; then
        case "$MACHINE_ARCH" in
            amd64|x86_64) MACHINE_MODEL="x86-64 PC" ;;
            *) MACHINE_MODEL="Unknown machine" ;;
        esac
    fi

    HARDWARE_LINE=missing
    if [ -f "$cpuinfo" ] && grep -q '^Hardware' "$cpuinfo" 2>/dev/null; then
        HARDWARE_LINE=present
    fi

    MACHINE_CLASS="$(classify_machine "$MACHINE_MODEL" "$MACHINE_ARCH")"
}

choose_machine_manually() {
    ask_choice MACHINE_CLASS \
        "I may have misread the cabinet. What computer is inside?" \
        "x86" \
        "x86|Regular x86-64 PC (Debian/Ubuntu)" \
        "pi5|Raspberry Pi 5" \
        "pi4|Raspberry Pi 4" \
        "zero2|Raspberry Pi Zero 2 W" \
        "pi3|Raspberry Pi 3" \
        "zero|Original Raspberry Pi Zero" \
        "other-arm64|Another 64-bit ARM board"
}

select_engine() {
    case "$MACHINE_CLASS" in
        x86)
            ask_choice ENGINE \
                "What kind of game engine should this cabinet use?" \
                "chromium" \
                "chromium|Chromium — full MakeCode simulator, best compatibility (recommended)" \
                "native|Native SDL — no browser, useful on weaker hardware, but games run slower"
            ;;
        pi5)
            if [ "$MACHINE_ARCH" = "arm64" ] || [ "$MACHINE_ARCH" = "aarch64" ]; then
                ask_choice ENGINE \
                    "What kind of game engine should this cabinet use?" \
                    "chromium" \
                    "chromium|Chromium — full MakeCode simulator, best compatibility (recommended)" \
                    "native|Native SDL — no browser, useful on weaker hardware, but games run slower"
            else
                ENGINE="chromium"
                warn "Pi 5 native binaries need a 64-bit OS; Chromium is the supported fit for this install."
            fi
            ;;
        pi4|zero2|pi3|zero)
            if [ "$MACHINE_ARCH" = "armhf" ] || [ "$MACHINE_ARCH" = "armv7l" ] || [ "$MACHINE_ARCH" = "armv6l" ]; then
                case "$MACHINE_CLASS" in
                    pi3|zero|zero2)
                        ENGINE="elf"
                        info "  This Pi is running a 32-bit OS, so the lightweight ELF path is the best fit."
                        ;;
                    *)
                        die "A 32-bit Pi 4 installation is not a supported arcade flavor. Use a 64-bit OS or a Pi 3/Zero."
                        ;;
                esac
            elif [ "$MACHINE_ARCH" = "arm64" ] || [ "$MACHINE_ARCH" = "aarch64" ]; then
                if [ "$MACHINE_CLASS" = "zero" ]; then
                    die "The original Pi Zero cannot run the 64-bit native runtime. Use a 32-bit OS for ELF."
                fi
                ENGINE="native"
                info "  This 64-bit Pi is below the recommended Chromium floor, so Native is the safest fit."
            else
                die "Unsupported Pi architecture: $MACHINE_ARCH"
            fi
            ;;
        other-arm64)
            ENGINE="native"
            warn "This is not a Raspberry Pi. Native mode may work, but it is the experimental path."
            ;;
        unknown-pi|other-armhf|unknown)
            die "This hardware is not in the supported installer matrix yet."
            ;;
        *)
            die "Unknown machine type: $MACHINE_CLASS"
            ;;
    esac
}

select_mode() {
    if [ "$ENGINE" = "elf" ]; then
        if [ "$MACHINE_CLASS" = "pi3" ]; then
            ask_choice CABINET_MODE \
                "Is this cabinet a jukebox or a one-hit wonder?" \
                "menu" \
                "menu|A menu of games" \
                "single|One dedicated game"
        else
            CABINET_MODE="single"
            info "  ELF on this board supports the dedicated single-game cabinet."
        fi
    else
        ask_choice CABINET_MODE \
            "Is this cabinet a jukebox or a one-hit wonder?" \
            "menu" \
            "menu|A menu of games" \
            "single|One dedicated game"
    fi
}

resolve_flavor() {
    FLAVOR="$ENGINE-$CABINET_MODE"
    BRANCH="$(flavor_branch "$FLAVOR")" || die "No installer branch is known for $FLAVOR."
    FLAVOR_LABEL="$(flavor_label "$FLAVOR")"
    REPO_DIR="$USER_HOME/$(flavor_checkout_name "$FLAVOR")"
}

select_controls() {
    if [ "$MACHINE_CLASS" = "x86" ]; then
        CONTROL_MODE="usb"
        info "  x86 cabinets use USB gamepads or a USB encoder; there are no GPIO pins to wire."
    elif machine_is_pi "$MACHINE_CLASS"; then
        if [ "$FLAVOR" = "elf-menu" ]; then
            CONTROL_MODE="flexible"
            info "  The ELF menu can use USB or GPIO controls; the game/menu configuration decides the exact mapping."
        else
            ask_choice CONTROL_MODE \
                "How will players control the cabinet?" \
                "usb" \
                "usb|USB gamepads or a USB zero-delay encoder" \
                "gpio|Arcade buttons wired directly to the Pi GPIO pins"
        fi
    else
        CONTROL_MODE="usb"
    fi
}

validate_native_source() {
    local source
    source="$(expand_user_path "$NATIVE_ARTIFACT_SOURCE")"
    if [[ "$source" =~ ^https?:// ]]; then
        return 0
    fi
    if [ -f "$source" ]; then
        case "$source" in
            *.tar.gz|*.tgz) return 0 ;;
            *) return 1 ;;
        esac
    fi
    if [ -d "$source" ]; then
        find "$source" -mindepth 1 -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) | grep -q .
        return
    fi
    return 1
}

collect_native_requirements() {
    cat <<EOF

${C_YELLOW}Native cabinets need compiled cartridges.${C_RESET}
Build each MakeCode game with the PNG to Desktop compiler:
  https://www.makecode.games/compilers/desktop
For a menu cabinet, include the compiled menu project too; it must install as Menu.
EOF
    while true; do
        ask_text NATIVE_ARTIFACT_SOURCE \
            "Enter a .tar.gz path, a folder containing .tar.gz files, or an http(s) URL" \
            "${CSA_NATIVE_SOURCE:-$HOME/Downloads}"
        if validate_native_source; then
            return 0
        fi
        if [ "$ASSUME_YES" = "1" ]; then
            die "CSA_NATIVE_SOURCE does not point to a .tar.gz file, a folder containing .tar.gz files, or an http(s) URL."
        fi
        warn "That is not a .tar.gz file, a folder containing .tar.gz files, or an http(s) URL."
    done
}

print_plan() {
    cat <<EOF

${C_BOLD}${C_CYAN}================= CABINET BUILD SHEET =================${C_RESET}
  Machine        : $MACHINE_MODEL
  Operating system: $OS_PRETTY ($MACHINE_ARCH)
  Arcade flavor  : $FLAVOR_LABEL
  Cabinet mode   : $CABINET_MODE
  Controls       : $CONTROL_MODE
  Install user   : $USER_NAME
  Checkout       : $REPO_DIR
  Branch used    : $BRANCH ${C_DIM}(users should not need to remember this)${C_RESET}
EOF
    if [ "$ENGINE" = "native" ]; then
        printf '  Native games   : %s\n' "$NATIVE_ARTIFACT_SOURCE"
    fi
    if [ "$BOOT_SPLASH" = "yes" ]; then
        printf '  Cabinet polish : boot splash enabled\n'
    fi
    if [ "$HDMI_FIX" = "yes" ]; then
        printf '  Cabinet polish : HDMI audio fix enabled\n'
    fi
    printf '%s=======================================================%s\n' "$C_CYAN" "$C_RESET"
}

start_sudo_keepalive() {
    [ "$DRY_RUN" = "1" ] && return 0
    if [ "$(id -u)" -ne 0 ]; then
        (
            while true; do
                sudo -n true 2>/dev/null || exit 0
                sleep 45
            done
        ) &
        SUDO_KEEPALIVE_PID=$!
    fi
}

stop_sudo_keepalive() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

cleanup_installer() {
    stop_sudo_keepalive
    if [ -n "$NATIVE_TMPDIR" ] && [ -d "$NATIVE_TMPDIR" ]; then
        rm -rf "$NATIVE_TMPDIR"
    fi
}

preflight() {
    [ "$(uname -s)" = "Linux" ] || die "This installer only supports Linux arcade cabinets."

    case " $OS_ID $OS_ID_LIKE " in
        *debian*|*ubuntu*|*raspbian*) ;;
        *) die "Only Debian/Ubuntu-family systems are supported by the flavor installers. Detected: $OS_PRETTY" ;;
    esac

    if [ "$(id -u)" -eq 0 ]; then
        die "Do not run this installer as root or with sudo. Run it as the arcade user; it will ask for sudo only when needed."
    fi

    command_exists sudo || die "sudo is required but is not installed."
    command_exists apt-get || die "apt-get is required but was not found."

    if [ "$DRY_RUN" != "1" ]; then
        info ""
        info "The installer needs administrator access for packages and boot configuration."
        info "You may be asked for this user's sudo password once."
        sudo -v || die "Could not validate sudo access."
        start_sudo_keepalive
    fi

    local missing=0
    for cmd in git rsync curl tar file; do
        command_exists "$cmd" || missing=1
    done
    if [ "$missing" = "1" ]; then
        run_step "Stocking the toolbox" install_base_tools
    else
        printf '  %s✓%s Toolbox already stocked\n' "$C_GREEN" "$C_RESET"
    fi
}

select_game_after_checkout() {
    case "$FLAVOR" in
        elf-single)
            select_existing_game "$REPO_DIR/games" "elf" "AndyPaddleTheRiver"
            ;;
        chromium-single)
            select_existing_game "$REPO_DIR/games" "js" "AndyPaddleTheRiver"
            ;;
        native-menu|native-single)
            prepare_native_games
            ;;
    esac
}

run_pi_extras() {
    if ! machine_is_pi "$MACHINE_CLASS"; then
        return 0
    fi

    if [ "$BOOT_SPLASH" = "yes" ]; then
        if [ -f "$REPO_DIR/install/splash-setup.sh" ]; then
            run_step "Painting the boot marquee" sudo bash "$REPO_DIR/install/splash-setup.sh"
        else
            warn "This flavor does not carry the boot-splash installer; skipping it."
        fi
    fi

    if [ "$HDMI_FIX" = "yes" ]; then
        if [ -f "$REPO_DIR/install/hdmi-audio-fix.sh" ]; then
            run_step "Tuning the HDMI speakers" sudo bash "$REPO_DIR/install/hdmi-audio-fix.sh"
        else
            warn "This flavor does not carry the HDMI audio fix; skipping it."
        fi
    fi
}

install_elf_menu() {
    run_step "Installing Pi framebuffer helpers" install_pi_elf_support
    run_step "Copying the cabinet brain" bash "$REPO_DIR/setup.sh"
    local runtime_dir="${REPO_DIR%-src}"
    run_step "Teaching the cabinet to wake itself" configure_autologin
    run_step "Wiring the power-on marquee" write_elf_menu_autolaunch "$runtime_dir"
}

install_elf_single() {
    run_step "Installing Pi framebuffer helpers" install_pi_elf_support
    # pi3-elf-setup.sh currently copies into /sd before creating it in some
    # branch revisions. Creating it here keeps the branch installer compatible.
    run_step "Opening the cartridge door" sudo mkdir -p /sd
    local -a args=(bash "$REPO_DIR/install/pi3-elf-setup.sh" "--game=$GAME_NAME")
    if [ "$CONTROL_MODE" = "gpio" ]; then
        args+=(--input-mode=gpio)
    fi
    run_step "Installing the ELF arcade" "${args[@]}"
}

install_chromium() {
    if [ "$MACHINE_CLASS" = "x86" ]; then
        run_step "Installing the Chromium arcade" bash "$REPO_DIR/install/debian-x86-setup.sh"
        if [ "$FLAVOR" = "chromium-single" ]; then
            run_step "Adding the missing window-frame bolts" install_openbox_package
            run_step "Switching the cabinet to one cartridge" configure_x86_single_game "${REPO_DIR}-run"
        fi
    else
        local -a args=(bash "$REPO_DIR/install/kiosk-setup.sh")
        if [ "$CONTROL_MODE" = "gpio" ]; then
            args+=(--gpio-controllers)
        fi
        if [ "$FLAVOR" = "chromium-single" ]; then
            args+=(--single-game "--game=$GAME_NAME")
        fi
        run_step "Installing the Chromium arcade" "${args[@]}"
    fi
}

install_native() {
    local installer=""
    local -a args=()
    if [ "$FLAVOR" = "native-menu" ]; then
        installer="$REPO_DIR/install/multi-native-arcade-setup.sh"
    else
        installer="$REPO_DIR/install/single-native-arcade-setup.sh"
        args+=("--game=$GAME_NAME")
    fi
    if [ "$CONTROL_MODE" = "gpio" ]; then
        args+=(--gpio)
    fi
    run_step "Installing the native arcade" run_native_installer "$installer" "${args[@]}"
}

install_selected_flavor() {
    case "$FLAVOR" in
        elf-menu) install_elf_menu ;;
        elf-single) install_elf_single ;;
        chromium-menu|chromium-single) install_chromium ;;
        native-menu|native-single) install_native ;;
        *) die "Unknown flavor: $FLAVOR" ;;
    esac
}

usage() {
    cat <<EOF
Creation Station Arcade unified installer

Normal use (no flags to remember):
  curl -fsSL https://raw.githubusercontent.com/Kikketer/CreationStationArcade/main/install.sh | bash

Optional flags:
  --dry-run   Show the build plan without changing the machine
  --yes       Accept defaults for prompts (for automation)
  --help      Show this help
  --version   Show installer version
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --yes|-y) ASSUME_YES=1 ;;
            --help|-h) usage; exit 0 ;;
            --version) printf '%s\n' "$CSA_VERSION"; exit 0 ;;
            *) die "Unknown option: $1. Normally no options are needed." ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    trap cleanup_installer EXIT

    USER_NAME="$(id -un)"
    USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
    [ -n "$USER_HOME" ] || USER_HOME="$HOME"
    INSTALL_LOG="$USER_HOME/creation-station-installer.log"
    touch "$INSTALL_LOG" 2>/dev/null || INSTALL_LOG="/tmp/creation-station-installer.log"
    installer_log "=== installer $CSA_VERSION started ==="

    banner
    dim "Answer a few questions. The installer handles the branch plumbing behind the curtain."

    printf '%s%sIMPORTANT: DEDICATED MACHINE REQUIRED%s\n' "$C_RED" "$C_BOLD" "$C_RESET"
    cat <<'EOF'
  This installer is intended for an empty machine or a fresh OS install that
  will become a dedicated arcade cabinet. It changes boot behavior, autologin,
  system packages, device rules, and startup services. Do not use it on a
  machine you rely on for everyday work or personal files.
EOF
    if [ "$ASSUME_YES" != "1" ]; then
        if ! ask_yes_no "I understand this machine will be dedicated to the arcade" "n"; then
            info "Cancelled before making any changes."
            exit 0
        fi
    fi

    stage "1/6" "POWER ON"
    detect_platform
    printf '  Cabinet report\n'
    printf '    Machine : %s\n' "$MACHINE_MODEL"
    printf '    OS      : %s (%s)\n' "$OS_PRETTY" "$MACHINE_ARCH"
    printf '    User    : %s\n' "$USER_NAME"
    if machine_is_pi "$MACHINE_CLASS"; then
        printf '    ELF key : Hardware line is %s\n' "$HARDWARE_LINE"
    fi

    if machine_is_pi "$MACHINE_CLASS" || [ "$MACHINE_CLASS" = "x86" ]; then
        if ! ask_yes_no "Does that cabinet report look right" "y"; then
            choose_machine_manually
        fi
    else
        warn "I could not confidently identify this machine."
        choose_machine_manually
    fi

    stage "2/6" "CHOOSE YOUR CABINET"
    select_engine
    if [ "$ENGINE" = "elf" ] && [ "$HARDWARE_LINE" != "present" ]; then
        warn "ELF games require the legacy 'Hardware' line in /proc/cpuinfo, and this machine does not report it."
        warn "This usually means the kernel is too new. The game may boot to nothing."
        if ! ask_yes_no "Continue with ELF anyway" "n"; then
            die "ELF installation cancelled. Use a Pi image/kernel that still reports Hardware: BCM2835."
        fi
    fi
    select_mode
    resolve_flavor
    select_controls

    if { machine_is_pi "$MACHINE_CLASS" && [ "$ENGINE" != "native" ] && [ "$USER_NAME" != "pi" ]; }; then
        die "The current Pi branch installers are hard-coded for the user 'pi'. Create/use the 'pi' account for this flavor, or choose a Native flavor on a 64-bit OS."
    fi
    if [ "$FLAVOR" = "chromium-single" ] && [ "$USER_NAME" != "pi" ]; then
        die "The single-game Chromium branch still has hard-coded /home/pi runtime paths. Create/use a 'pi' arcade user, or choose the Chromium menu flavor instead."
    fi

    BOOT_SPLASH=no
    HDMI_FIX=no
    if machine_is_pi "$MACHINE_CLASS"; then
        if [ "$ENGINE" = "elf" ]; then
            if ask_yes_no "Add the arcade boot splash so the cabinet hides boring boot text" "y"; then
                BOOT_SPLASH=yes
            fi
        fi
        if ask_yes_no "Install the HDMI audio fix now" "n"; then
            HDMI_FIX=yes
        fi
    fi

    if [ "$ENGINE" = "native" ]; then
        stage "3/6" "LOAD THE CARTRIDGES"
        collect_native_requirements
    else
        stage "3/6" "LOAD THE CARTRIDGES"
        info "  Stock games come with the selected flavor; more can be loaded later."
    fi

    stage "4/6" "INSERT COIN"
    print_plan
    if ! ask_yes_no "Ready to build this cabinet" "y"; then
        info "No changes were made. The cabinet stays in attract mode."
        exit 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        warn "Dry run ends before checkout or system changes."
        exit 0
    fi

    preflight

    stage "5/6" "DOWNLOADING THE BLUEPRINT"
    run_step "Downloading the cabinet blueprint" prepare_checkout

    select_game_after_checkout

    printf '\n%sFinal cartridge check%s\n' "$C_BOLD" "$C_RESET"
    printf '  Flavor : %s\n' "$FLAVOR_LABEL"
    [ -n "${GAME_NAME:-}" ] && printf '  Game   : %s\n' "$GAME_NAME"
    printf '  Branch : %s\n' "$BRANCH"
    if ! ask_yes_no "Begin system installation now" "y"; then
        die "Stopped before system installation. The source checkout may exist, but system configuration was not changed."
    fi

    prompt_controller_plugin

    stage "6/6" "BUILDING THE CABINET"
    install_selected_flavor
    run_pi_extras
    run_controller_setup

    cat <<EOF

${C_GREEN}${C_BOLD}================== INSTALLATION COMPLETE ==================${C_RESET}
  The cabinet is assembled and ready for its first boot.
  Log file: $INSTALL_LOG
  Checkout: $REPO_DIR

EOF

    if ask_yes_no "Reboot into the arcade now" "n"; then
        info "Rebooting. See you at the attract screen."
        sudo reboot
    else
        info "Reboot when ready: sudo reboot"
    fi
}

if [ "${CSA_INSTALLER_LIBRARY:-0}" != "1" ]; then
    main "$@"
fi

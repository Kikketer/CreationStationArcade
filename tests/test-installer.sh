#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CSA_INSTALLER_LIBRARY=1
# shellcheck disable=SC1091,SC2034
source "$ROOT/install.sh"

TESTS_RUN=0
TESTS_FAILED=0

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$1" >&2
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$message"
    else
        printf '  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
        fail "$message"
    fi
}

assert_file_exists() {
    if [ -e "$1" ]; then
        pass "$2"
    else
        printf '  missing: %s\n' "$1" >&2
        fail "$2"
    fi
}

write_debian_os_release() {
    cat > "$1" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
ID=debian
ID_LIKE=debian
EOF
}

write_meminfo() {
    cat > "$1" <<EOF
MemTotal:        $2 kB
EOF
}

test_classify_machine() {
    assert_eq "pi5" "$(classify_machine 'Raspberry Pi 5 Model B' arm64)" "classifies Raspberry Pi 5"
    assert_eq "pi3" "$(classify_machine 'Raspberry Pi 3 Model B Plus' armhf)" "classifies Raspberry Pi 3"
    assert_eq "zero2" "$(classify_machine 'Raspberry Pi Zero 2 W' arm64)" "classifies Pi Zero 2 W before original Zero"
    assert_eq "x86" "$(classify_machine 'x86-64 PC' amd64)" "classifies x86 PCs"
}

test_flavor_map() {
    assert_eq "chromium-kiosk" "$(flavor_branch chromium-menu)" "maps Chromium menu branch"
    assert_eq "single-game-kiosk" "$(flavor_branch chromium-single)" "maps Chromium single-game branch"
    assert_eq "multi-native-arcade" "$(flavor_branch native-menu)" "maps native menu branch"
    assert_eq "single-native-arcade" "$(flavor_branch native-single)" "maps native single-game branch"
    if flavor_branch elf-menu >/dev/null 2>&1; then
        fail "does not map deprecated ELF flavors"
    else
        pass "does not map deprecated ELF flavors"
    fi
}

test_detect_x86() {
    local dir="$TMP/detect-x86"
    mkdir -p "$dir"
    write_debian_os_release "$dir/os-release"
    write_meminfo "$dir/meminfo" 3900000
    : > "$dir/cpuinfo"

    CSA_OS_RELEASE="$dir/os-release" \
    CSA_CPUINFO="$dir/cpuinfo" \
    CSA_DEVICE_TREE_MODEL="$dir/no-model" \
    CSA_MEMINFO="$dir/meminfo" \
    CSA_ARCH=amd64 \
        detect_platform

    assert_eq "x86" "$MACHINE_CLASS" "detects x86 fixture"
    assert_eq "amd64" "$MACHINE_ARCH" "detects x86 architecture fixture"
    assert_eq "3900000" "$TOTAL_MEMORY_KB" "detects total memory"
}

test_detect_pi3() {
    local dir="$TMP/detect-pi3"
    mkdir -p "$dir"
    write_debian_os_release "$dir/os-release"
    write_meminfo "$dir/meminfo" 1000000
    cat > "$dir/cpuinfo" <<'EOF'
Hardware	: BCM2835
Model		: Raspberry Pi 3 Model B Plus Rev 1.3
EOF

    CSA_OS_RELEASE="$dir/os-release" \
    CSA_CPUINFO="$dir/cpuinfo" \
    CSA_DEVICE_TREE_MODEL="$dir/no-model" \
    CSA_MEMINFO="$dir/meminfo" \
    CSA_ARCH=armhf \
        detect_platform

    assert_eq "pi3" "$MACHINE_CLASS" "detects Pi 3 fixture"
    assert_eq "1000000" "$TOTAL_MEMORY_KB" "detects Pi memory fixture"
}

test_default_engine_choices() {
    ASSUME_YES=1

    MACHINE_CLASS=x86
    MACHINE_ARCH=amd64
    TOTAL_MEMORY_KB=3900000
    select_engine
    assert_eq "chromium" "$ENGINE" "x86 with 4 GB defaults to Chromium"

    MACHINE_CLASS=x86
    MACHINE_ARCH=amd64
    TOTAL_MEMORY_KB=2000000
    select_engine
    assert_eq "native" "$ENGINE" "x86 below 4 GB defaults to Native Application"

    MACHINE_CLASS=pi5
    MACHINE_ARCH=arm64
    TOTAL_MEMORY_KB=3900000
    select_engine
    assert_eq "chromium" "$ENGINE" "Pi 5 with 4 GB defaults to Chromium"

    MACHINE_CLASS=pi4
    MACHINE_ARCH=arm64
    TOTAL_MEMORY_KB=3900000
    select_engine
    assert_eq "chromium" "$ENGINE" "64-bit Pi 4 with 4 GB defaults to Chromium"

    MACHINE_CLASS=pi4
    MACHINE_ARCH=arm64
    TOTAL_MEMORY_KB=2000000
    select_engine
    assert_eq "native" "$ENGINE" "64-bit Pi 4 below 4 GB defaults to Native Application"

    MACHINE_CLASS=pi3
    MACHINE_ARCH=arm64
    TOTAL_MEMORY_KB=1000000
    select_engine
    assert_eq "native" "$ENGINE" "64-bit Pi 3 uses Native Application"

    if (MACHINE_CLASS=pi3; MACHINE_ARCH=armhf; TOTAL_MEMORY_KB=1000000; select_engine) >/dev/null 2>&1; then
        fail "32-bit Pi 3 legacy ELF path is rejected"
    else
        pass "32-bit Pi 3 legacy ELF path is rejected"
    fi

    ASSUME_YES=0
}

test_flavor_resolution() {
    USER_HOME="$TMP/home"
    mkdir -p "$USER_HOME"

    ENGINE=chromium
    CABINET_MODE=single
    resolve_flavor
    assert_eq "chromium-single" "$FLAVOR" "resolves Chromium single flavor"
    assert_eq "single-game-kiosk" "$BRANCH" "Chromium single resolves to its branch"

    ENGINE=native
    CABINET_MODE=menu
    resolve_flavor
    assert_eq "CreationStationArcade" "$(basename "$REPO_DIR")" "native flavors checkout directly as runtime"
}

test_native_source_validation() {
    local dir="$TMP/native-source"
    mkdir -p "$dir/archives"
    : > "$dir/game.tar.gz"
    : > "$dir/not-a-game.txt"
    : > "$dir/archives/game.tar.gz"

    NATIVE_ARTIFACT_SOURCE="$dir/game.tar.gz"
    validate_native_source
    pass "accepts a native .tar.gz file"

    NATIVE_ARTIFACT_SOURCE="$dir/archives"
    validate_native_source
    pass "accepts a folder containing native archives"

    NATIVE_ARTIFACT_SOURCE="https://example.invalid/game.tar.gz"
    validate_native_source
    pass "accepts a native archive URL"

    NATIVE_ARTIFACT_SOURCE="$dir/not-a-game.txt"
    if validate_native_source; then
        fail "rejects a non-archive file"
    else
        pass "rejects a non-archive file"
    fi
}

test_extract_native_archive() {
    local dir="$TMP/native-extract"
    local payload="$dir/payload"
    local repo="$dir/repo"
    mkdir -p "$payload" "$repo/games"
    printf '#!/bin/sh\n' > "$payload/Game"
    printf 'fake library\n' > "$payload/libpxt.so"
    printf 'TestGame\n' > "$payload/name.txt"
    chmod +x "$payload/Game"
    tar -czf "$dir/TestGame-arm64.tar.gz" -C "$payload" Game libpxt.so name.txt

    REPO_DIR="$repo"
    MACHINE_ARCH=arm64
    NATIVE_NAMES_FILE="$dir/names.txt"
    CSA_SKIP_ARCH_CHECK=1 extract_native_archives "$dir/TestGame-arm64.tar.gz"

    assert_file_exists "$repo/games/TestGame/Game" "extracts native Game into games/<name>"
    assert_file_exists "$repo/games/TestGame/libpxt.so" "keeps libpxt.so beside Game"
    assert_eq "TestGame" "$(cat "$NATIVE_NAMES_FILE")" "records extracted native game name"
}

test_x86_single_game_xinitrc() {
    local home="$TMP/xinit-home"
    mkdir -p "$home"
    USER_HOME="$home"
    GAME_NAME="ExampleGame"
    configure_x86_single_game "/runtime/path"

    if grep -q 'SINGLE_GAME_NAME="ExampleGame"' "$home/.xinitrc" && grep -q 'single-game-launcher.sh' "$home/.xinitrc"; then
        pass "writes x86 single-game xinitrc"
    else
        fail "writes x86 single-game xinitrc"
    fi
}

test_native_x86_patch_is_restored() {
    local dir="$TMP/native-installer-patch"
    mkdir -p "$dir"
    local installer="$dir/installer.sh"
    local original="$dir/original.sh"
    export OUTFILE="$dir/ran"

    cat > "$installer" <<'EOF'
#!/usr/bin/env bash
# package list includes python3-rpi.gpio on Pi branches
printf 'ran' > "$OUTFILE"
EOF
    chmod +x "$installer"
    cp "$installer" "$original"

    sudo() {
        [ "$1" = "bash" ] && shift
        bash "$@"
    }
    MACHINE_CLASS=x86
    run_native_installer "$installer" --game=Example
    unset -f sudo

    assert_eq "ran" "$(cat "$OUTFILE")" "native installer adapter runs the branch installer"
    if cmp -s "$installer" "$original"; then
        pass "native x86 package patch is restored after installation"
    else
        fail "native x86 package patch is restored after installation"
    fi
}

test_dry_run_cli() {
    local dir="$TMP/cli-fixture"
    mkdir -p "$dir"
    write_debian_os_release "$dir/os-release"
    write_meminfo "$dir/meminfo" 3900000
    : > "$dir/cpuinfo"

    local output=""
    output="$(CSA_INSTALLER_LIBRARY=0 \
        CSA_OS_RELEASE="$dir/os-release" \
        CSA_CPUINFO="$dir/cpuinfo" \
        CSA_DEVICE_TREE_MODEL="$dir/no-model" \
        CSA_MEMINFO="$dir/meminfo" \
        CSA_ARCH=amd64 \
        "$ROOT/install.sh" --yes --dry-run 2>&1)"

    case "$output" in
        *"Chromium menu arcade"*"chromium-kiosk"*"Dry run ends"*)
            pass "dry-run CLI prints Chromium x86 plan without installing"
            ;;
        *)
            printf '%s\n' "$output" >&2
            fail "dry-run CLI prints Chromium x86 plan without installing"
            ;;
    esac
}

test_classify_machine
test_flavor_map
test_detect_x86
test_detect_pi3
test_default_engine_choices
test_flavor_resolution
test_native_source_validation
test_extract_native_archive
test_x86_single_game_xinitrc
test_native_x86_patch_is_restored
test_dry_run_cli

printf '\n%d tests run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]

#!/bin/bash
# Builds games/Menu from the source in menu/ using the MakeCodeGamesIngest
# toolchain. Requires pnpm deps installed there and the
# makecode-native-build docker image (arm64 bookworm toolchain).
#
# Usage: menu/build-menu.sh [arch]   (arch defaults to arm64)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
INGEST="${MAKECODE_INGEST_DIR:-$REPO/../MakeCodeGamesIngest}"
ARCH="${1:-arm64}"

if [ ! -d "$INGEST" ]; then
    echo "MakeCodeGamesIngest checkout not found at $INGEST" >&2
    echo "Set MAKECODE_INGEST_DIR to its location." >&2
    exit 1
fi

cd "$INGEST"
pnpm exec tsx scripts/build-project.ts "$HERE" "$REPO/games/Menu" --arch "$ARCH"
echo "Menu built -> $REPO/games/Menu"

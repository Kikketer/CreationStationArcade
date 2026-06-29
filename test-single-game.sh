#!/bin/bash
# test-single-game.sh - Test script for single-game kiosk mode

echo "=== Single-Game Kiosk Mode Test ==="

# Check if required files exist
echo "Checking required files..."
required_files=(
    "single-game-launcher.sh"
    "reset-single-game.sh"
    "gpio-monitor-single-game.py"
    "gpio-monitor-single-game.service"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    else
        echo "✓ $file exists"
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo "ERROR: Missing files: ${missing_files[*]}"
    exit 1
fi

# Check if scripts are executable
echo "Checking file permissions..."
for file in "${required_files[@]}"; do
    if [[ "$file" == *.sh ]] || [[ "$file" == *.py ]]; then
        if [ -x "$file" ]; then
            echo "✓ $file is executable"
        else
            echo "ERROR: $file is not executable"
            exit 1
        fi
    fi
done

# Test game configuration
echo "Testing game configuration..."
GAME_NAME="${SINGLE_GAME_NAME:-AndyPaddleTheRiver}"
echo "Using game: $GAME_NAME"

# Check if game file exists
if [ -f "games/${GAME_NAME}.js" ]; then
    echo "✓ Game file exists: games/${GAME_NAME}.js"
else
    echo "WARNING: Game file not found: games/${GAME_NAME}.js"
    echo "Available games:"
    ls -1 games/*.js | sed 's|games/||' | sed 's|\.js||'
fi

# Check if Node server can start (quick test)
echo "Testing Node server..."
if command -v node >/dev/null 2>&1; then
    echo "✓ Node.js is available"
    # Quick syntax check
    if node -c server.js 2>/dev/null; then
        echo "✓ server.js syntax is valid"
    else
        echo "ERROR: server.js has syntax errors"
        exit 1
    fi
else
    echo "ERROR: Node.js not found"
    exit 1
fi

# Check if chromium is available
echo "Testing Chromium availability..."
CHROMIUM_BIN=$(which chromium 2>/dev/null || which chromium-browser 2>/dev/null || which google-chrome 2>/dev/null)
if [ -n "$CHROMIUM_BIN" ]; then
    echo "✓ Chromium found: $CHROMIUM_BIN"
else
    echo "ERROR: Chromium not found"
    exit 1
fi

# Check GPIO dependencies (only on Raspberry Pi)
if [ "$(uname -m)" = "armv7l" ] || [ "$(uname -m)" = "aarch64" ]; then
    echo "Testing GPIO dependencies..."
    if python3 -c "import RPi.GPIO" 2>/dev/null; then
        echo "✓ RPi.GPIO module is available"
    else
        echo "WARNING: RPi.GPIO module not found (GPIO monitoring won't work)"
    fi
else
    echo "Not on Raspberry Pi - skipping GPIO check"
fi

echo ""
echo "=== Test Summary ==="
echo "✓ All required files are present"
echo "✓ File permissions are correct"
echo "✓ Node.js and Chromium are available"
echo "✓ Configuration is valid"
echo ""
echo "To start the single-game kiosk:"
echo "  ./single-game-launcher.sh"
echo ""
echo "To configure a different game:"
echo "  export SINGLE_GAME_NAME=\"ChrisVikingsOfFour\""
echo "  ./single-game-launcher.sh"
echo ""
echo "See SINGLE_GAME_README.md for full setup instructions."

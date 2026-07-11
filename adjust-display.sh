#!/bin/bash
# adjust-display.sh — Live CSS injection via Chromium remote debug port
# Adjust padding, margins and scale of the game display without restarting.
# Run over SSH while the game is showing.
#
# Usage:
#   ./adjust-display.sh [options]
#
# Options:
#   --top=N       Top inset in px (default: 0)
#   --bottom=N    Bottom inset in px (default: 0)
#   --left=N      Left inset in px (default: 0)
#   --right=N     Right inset in px (default: 0)
#   --scale=N     Scale factor 0.1–2.0 (default: 1.0)
#   --reset       Reset all adjustments back to defaults
#   --show        Show current injected values (reads from /tmp/arcade-display-adjust)
#
# Examples:
#   ./adjust-display.sh --scale=0.9 --top=20 --bottom=20
#   ./adjust-display.sh --left=40 --right=40
#   ./adjust-display.sh --reset

DEBUG_PORT=9222
STATE_FILE="/tmp/arcade-display-adjust"

TOP=0
BOTTOM=0
LEFT=0
RIGHT=0
SCALE=1.0
RESET=false
SHOW=false

for arg in "$@"; do
    case $arg in
        --top=*)    TOP="${arg#--top=}" ;;
        --bottom=*) BOTTOM="${arg#--bottom=}" ;;
        --left=*)   LEFT="${arg#--left=}" ;;
        --right=*)  RIGHT="${arg#--right=}" ;;
        --scale=*)  SCALE="${arg#--scale=}" ;;
        --reset)    RESET=true ;;
        --show)     SHOW=true ;;
        --help|-h)
            sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

if [ "$SHOW" = true ]; then
    if [ -f "$STATE_FILE" ]; then
        echo "Current display adjustments:"
        cat "$STATE_FILE"
    else
        echo "No adjustments applied (defaults in use)"
    fi
    exit 0
fi

if [ "$RESET" = true ]; then
    TOP=0; BOTTOM=0; LEFT=0; RIGHT=0; SCALE=1.0
fi

# Check remote debug port is available
if ! curl -s "http://localhost:$DEBUG_PORT/json" >/dev/null 2>&1; then
    echo "ERROR: Chromium remote debug port $DEBUG_PORT not reachable."
    echo "Is Chromium running? Check: pgrep -a chromium"
    exit 1
fi

# Find the play page tab
PAGE_ID=$(curl -s "http://localhost:$DEBUG_PORT/json" | \
    python3 -c "
import sys, json
tabs = json.load(sys.stdin)
for t in tabs:
    if 'play' in t.get('url','') or 'localhost:3000' in t.get('url',''):
        print(t['id'])
        break
" 2>/dev/null)

if [ -z "$PAGE_ID" ]; then
    echo "ERROR: Could not find the arcade play page tab."
    echo "Available tabs:"
    curl -s "http://localhost:$DEBUG_PORT/json" | python3 -c "
import sys, json
for t in json.load(sys.stdin):
    print(f\"  {t.get('id','')}  {t.get('url','')}\")" 2>/dev/null
    exit 1
fi

echo "Found page tab: $PAGE_ID"

# Build the CSS to inject
CSS="
#sim-frame {
    top: ${TOP}px !important;
    bottom: ${BOTTOM}px !important;
    left: ${LEFT}px !important;
    right: ${RIGHT}px !important;
    width: calc(100% - ${LEFT}px - ${RIGHT}px) !important;
    height: calc(100% - ${TOP}px - ${BOTTOM}px) !important;
    transform: scale(${SCALE}) !important;
    transform-origin: center center !important;
}
"

# Escape for JSON
CSS_ESCAPED=$(echo "$CSS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Build the JS to inject — removes old injected style then adds new one
JS="(function() {
    var old = document.getElementById('__arcade_adjust__');
    if (old) old.remove();
    var s = document.createElement('style');
    s.id = '__arcade_adjust__';
    s.textContent = $CSS_ESCAPED;
    document.head.appendChild(s);
    return 'OK: top=${TOP} bottom=${BOTTOM} left=${LEFT} right=${RIGHT} scale=${SCALE}';
})()"

JS_ESCAPED=$(echo "$JS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Send via WebSocket using python3
RESULT=$(python3 - <<PYEOF
import json, websocket, time

ws_url = "ws://localhost:$DEBUG_PORT/devtools/page/$PAGE_ID"
ws = websocket.create_connection(ws_url, timeout=5)

msg = json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": $JS_ESCAPED}})
ws.send(msg)

resp = json.loads(ws.recv())
ws.close()

result = resp.get("result", {}).get("result", {}).get("value", "no result")
print(result)
PYEOF
)

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to connect via WebSocket. Is websocket-client installed?"
    echo "Try: pip3 install websocket-client"
    exit 1
fi

echo "$RESULT"

# Save state
cat > "$STATE_FILE" <<EOF
top=$TOP
bottom=$BOTTOM
left=$LEFT
right=$RIGHT
scale=$SCALE
EOF

echo "Saved to $STATE_FILE. Run with --show to see current values, --reset to clear."

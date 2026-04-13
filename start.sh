#!/usr/bin/env bash
# ============================================================
# Claw Code: 一键启动
# 用法: ./start.sh [provider]
# 例如: ./start.sh deepseek
# ============================================================

set -euo pipefail

CDP_PORT=18892
PROVIDER="${1:-deepseek}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Map provider ---
case "$PROVIDER" in
    deepseek) DOMAIN="chat.deepseek.com" ;;
    chatgpt)  DOMAIN="chatgpt.com" ;;
    gemini)   DOMAIN="gemini.google.com" ;;
    qwen)     DOMAIN="tongyi.aliyun.com" ;;
    kimi)     DOMAIN="kimi.moonshot.cn" ;;
    *)        err "Unknown: $PROVIDER (use: deepseek chatgpt gemini qwen kimi)"; exit 1 ;;
esac

# --- Detect platform ---
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true

HAS_DISPLAY=false
[ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] && HAS_DISPLAY=true

echo ""
echo "============================================================"
if $IS_WSL; then
    echo " Platform: WSL | Provider: ${PROVIDER}"
elif $HAS_DISPLAY; then
    echo " Platform: Linux Desktop | Provider: ${PROVIDER}"
else
    echo " Platform: Linux Headless | Provider: ${PROVIDER}"
fi
echo "============================================================"
echo ""

# ============================================================
# Headless: no browser, manual only
# ============================================================
if ! $IS_WSL && ! $HAS_DISPLAY; then
    echo "No browser available. Input cookies manually:"
    echo "  ./scripts/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
    exit 0
fi

# ============================================================
# Step 1: Start Chrome
# ============================================================
info "Step 1/4: Starting Chrome..."

if $IS_WSL; then
    WIN_IP=$(ip route show default 2>/dev/null | awk '{print $3}')
    info "Windows IP: ${WIN_IP}"

    # Kill old Chrome
    powershell.exe -NoProfile -Command "Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
    sleep 2

    # Firewall + portproxy (already proven to work)
    info "Setting firewall + port forwarding..."
    powershell.exe -NoProfile -Command "
      # Firewall
      Remove-NetFirewallRule -DisplayName 'Claw Chrome CDP' -ErrorAction SilentlyContinue
      New-NetFirewallRule -DisplayName 'Claw Chrome CDP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort ${CDP_PORT} -ErrorAction SilentlyContinue
      # Port forwarding: 0.0.0.0:${CDP_PORT} -> 127.0.0.1:${CDP_PORT}
      netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=${CDP_PORT} 2>\$null
      netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=${CDP_PORT} connectaddress=127.0.0.1 connectport=${CDP_PORT}
    " >/dev/null 2>&1 || warn "Firewall/portproxy failed (run WSL as admin?)"

    # Launch Chrome
    info "Launching Chrome..."
    powershell.exe -NoProfile -Command "
      \$paths = @(
        \"\$env:LOCALAPPDATA\\Google\\Chrome\\Application\\chrome.exe\",
        'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
        'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe'
      )
      \$chrome = \$paths | Where-Object { Test-Path \$_ } | Select-Object -First 1
      if (-not \$chrome) { Write-Error 'Chrome not found'; exit 1 }
      \$prof = \"\$env:USERPROFILE\\.claw\\chrome-profile\"
      Start-Process \$chrome -ArgumentList '--remote-debugging-port=${CDP_PORT}','--remote-debugging-address=0.0.0.0',\"--user-data-dir=\$prof\",'--no-first-run','--no-default-browser-check'
    " 2>/dev/null || { err "Chrome launch failed"; exit 1; }
    sleep 4

else
    # Linux Desktop
    CHROME=""
    for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
        command -v "$cmd" &>/dev/null && CHROME="$cmd" && break
    done
    [ -z "$CHROME" ] && { err "Chrome not found. Install: sudo apt install chromium-browser"; exit 1; }

    pkill -f "chrome.*remote-debugging" 2>/dev/null || true
    sleep 1
    mkdir -p "$HOME/.claw/chrome-profile"
    "$CHROME" --remote-debugging-port=${CDP_PORT} --user-data-dir="$HOME/.claw/chrome-profile" --no-first-run &
    sleep 3
fi

# ============================================================
# Step 2: Connect to Chrome CDP
# ============================================================
info "Step 2/4: Connecting to Chrome..."

CDP_URL=""

# Function: try a URL with short timeout
try_cdp() {
    curl -sf --connect-timeout 2 "$1/json/version" >/dev/null 2>&1
}

# Desktop: just localhost
if ! $IS_WSL; then
    if try_cdp "http://localhost:${CDP_PORT}"; then
        CDP_URL="http://localhost:${CDP_PORT}"
    fi
fi

# WSL: try multiple methods
if $IS_WSL; then
    # Method 1: socat bridge (proven to work in user's environment)
    # Kill old socat
    kill $(lsof -t -i :${CDP_PORT} 2>/dev/null) 2>/dev/null || true
    sleep 1

    # Install socat if needed
    if ! command -v socat &>/dev/null; then
        info "Installing socat..."
        sudo apt-get update -qq && sudo apt-get install -y -qq socat >/dev/null 2>&1
    fi

    info "Starting socat bridge (localhost:${CDP_PORT} -> ${WIN_IP}:${CDP_PORT})..."
    socat TCP-LISTEN:${CDP_PORT},fork,reuseaddr TCP:${WIN_IP}:${CDP_PORT} &
    SOCAT_PID=$!
    sleep 2

    if try_cdp "http://localhost:${CDP_PORT}"; then
        CDP_URL="http://localhost:${CDP_PORT}"
        ok "Connected via socat bridge"
    else
        kill $SOCAT_PID 2>/dev/null || true

        # Method 2: direct to Windows IP
        if try_cdp "http://${WIN_IP}:${CDP_PORT}"; then
            CDP_URL="http://${WIN_IP}:${CDP_PORT}"
            ok "Connected directly to ${WIN_IP}"
        fi
    fi
fi

if [ -z "$CDP_URL" ]; then
    err "Cannot connect to Chrome CDP"
    echo ""
    echo "Manual fallback:"
    echo "  1. On Windows run:"
    echo "     start chrome --remote-debugging-port=${CDP_PORT} --remote-debugging-address=0.0.0.0"
    echo "  2. Then: ./scripts/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
    exit 1
fi

BROWSER=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys;print(json.load(sys.stdin).get('Browser','?'))" 2>/dev/null || echo "?")
ok "Chrome: ${BROWSER}"

# ============================================================
# Step 3: Ensure provider page is open
# ============================================================
info "Step 3/4: Checking ${DOMAIN}..."

HAS_PAGE=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''): print('yes'); break
" 2>/dev/null || echo "")

if [ "$HAS_PAGE" != "yes" ]; then
    info "Opening ${DOMAIN}..."
    if $IS_WSL; then
        powershell.exe -NoProfile -Command "Start-Process 'https://${DOMAIN}'" 2>/dev/null || true
    else
        xdg-open "https://${DOMAIN}" 2>/dev/null || true
    fi
    echo ""
    echo -e "${YELLOW}Log in to ${DOMAIN} in Chrome, then press Enter...${NC}"
    read -r
fi

# ============================================================
# Step 4: Capture cookies
# ============================================================
info "Step 4/4: Capturing cookies..."

CDP_HOST=$(echo "$CDP_URL" | sed 's|http://||' | cut -d/ -f1)
USER_AGENT=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys;print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")

PAGE_WS=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys,re
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''):
        ws=t.get('webSocketDebuggerUrl','')
        print(re.sub(r'ws://[^/]+','ws://${CDP_HOST}',ws))
        break
" 2>/dev/null || echo "")

[ -z "$PAGE_WS" ] && { err "${DOMAIN} page not found"; exit 1; }

python3 -c "import websockets" 2>/dev/null || pip3 install websockets -q 2>/dev/null || true

COOKIES_RAW=$(python3 -c "
import asyncio, json
import websockets

async def main():
    async with websockets.connect('${PAGE_WS}') as ws:
        await ws.send(json.dumps({
            'id': 1,
            'method': 'Network.getCookies',
            'params': {'urls': ['https://${DOMAIN}']}
        }))
        resp = json.loads(await ws.recv())
        cookies = resp.get('result', {}).get('cookies', [])
        mapped = [{
            'name': c['name'], 'value': c['value'],
            'domain': c.get('domain', '${DOMAIN}'),
            'path': c.get('path', '/'),
            'http_only': c.get('httpOnly', False),
            'secure': c.get('secure', True)
        } for c in cookies]
        print(json.dumps(mapped))

asyncio.run(main())
" 2>/dev/null || echo "[]")

if [ "$COOKIES_RAW" = "[]" ] || [ -z "$COOKIES_RAW" ]; then
    err "Cookie extraction failed"
    echo "Manual: ./scripts/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
    exit 1
fi

# Save
CONFIG_DIR="${CLAW_CONFIG_HOME:-$HOME/.claw}"
CRED_FILE="$CONFIG_DIR/web-credentials.json"
mkdir -p "$CONFIG_DIR"

TIMESTAMP=$(date +%s)
UA_JSON="null"
[ -n "$USER_AGENT" ] && UA_JSON="\"$USER_AGENT\""

python3 -c "
import json, os
path = '$CRED_FILE'
store = {'credentials': {}}
if os.path.exists(path):
    with open(path) as f:
        store = json.load(f)
store.setdefault('credentials', {})
store['credentials']['$PROVIDER'] = {
    'provider': '$PROVIDER',
    'cookies': json.loads(open('/dev/stdin').read()),
    'bearer_token': None,
    'user_agent': $UA_JSON,
    'captured_at': $TIMESTAMP
}
with open(path, 'w') as f:
    json.dump(store, f, indent=2)
" <<< "$COOKIES_RAW"

NUM=$(echo "$COOKIES_RAW" | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} DONE!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "  Provider: ${PROVIDER} (${DOMAIN})"
echo "  Cookies:  ${NUM} captured"
echo "  Saved:    ${CRED_FILE}"
echo ""
echo "  Use: cd rust && ./target/release/rusty-claude-cli --model ${PROVIDER}/deepseek-chat"
echo ""

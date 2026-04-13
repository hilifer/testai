#!/usr/bin/env bash
# ============================================================
# Claw Code: 一键启动
# 用法: ./start.sh [provider]
# 例如: ./start.sh deepseek
# ============================================================

set -euo pipefail

CDP_PORT=18892
PROXY_PORT=18893
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

    # Firewall
    info "Setting firewall..."
    powershell.exe -NoProfile -Command "
      Remove-NetFirewallRule -DisplayName 'Claw Chrome CDP' -ErrorAction SilentlyContinue
      New-NetFirewallRule -DisplayName 'Claw Chrome CDP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort ${CDP_PORT},${PROXY_PORT} -ErrorAction SilentlyContinue
    " >/dev/null 2>&1 || warn "Firewall failed (need admin?)"

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

    # Verify Chrome running on Windows
    info "Verifying Chrome on Windows..."
    CHROME_OK=false
    for i in 1 2 3 4 5; do
        if powershell.exe -NoProfile -Command "(Invoke-WebRequest -Uri 'http://localhost:${CDP_PORT}/json/version' -UseBasicParsing -TimeoutSec 3).StatusCode" >/dev/null 2>&1; then
            CHROME_OK=true
            break
        fi
        sleep 2
    done
    if ! $CHROME_OK; then
        err "Chrome CDP not responding on Windows"
        exit 1
    fi
    ok "Chrome running on Windows"

    # Start HTTP proxy on Windows (PowerShell HttpListener)
    # This is the ONLY method proven to work for WSL -> Windows CDP
    info "Starting HTTP proxy (${PROXY_PORT} -> ${CDP_PORT})..."

    # Kill old proxy
    powershell.exe -NoProfile -Command "
      Get-Process powershell -ErrorAction SilentlyContinue |
        Where-Object { \$_.CommandLine -match 'CdpProxy' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    " 2>/dev/null || true

    # Start proxy in background
    powershell.exe -NoProfile -Command "
      Start-Process powershell -WindowStyle Minimized -ArgumentList '-NoProfile','-Command',\"
        # CdpProxy
        \\\$l = [System.Net.HttpListener]::new()
        \\\$l.Prefixes.Add('http://+:${PROXY_PORT}/')
        \\\$l.Start()
        while (\\\$true) {
          \\\$ctx = \\\$l.GetContext()
          \\\$path = \\\$ctx.Request.RawUrl
          try {
            \\\$r = Invoke-WebRequest -Uri ('http://localhost:${CDP_PORT}' + \\\$path) -UseBasicParsing -TimeoutSec 10
            \\\$ctx.Response.StatusCode = \\\$r.StatusCode
            \\\$ctx.Response.ContentType = \\\$r.Headers['Content-Type']
            \\\$b = [System.Text.Encoding]::UTF8.GetBytes(\\\$r.Content)
            \\\$ctx.Response.OutputStream.Write(\\\$b, 0, \\\$b.Length)
          } catch {
            \\\$ctx.Response.StatusCode = 502
          }
          \\\$ctx.Response.Close()
        }
      \"
    " 2>/dev/null || true
    sleep 3

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

if $IS_WSL; then
    # WSL: connect via HTTP proxy on PROXY_PORT
    if curl -sf --connect-timeout 5 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1; then
        CDP_URL="http://${WIN_IP}:${PROXY_PORT}"
        ok "Connected via HTTP proxy (${WIN_IP}:${PROXY_PORT})"
    else
        # Retry
        info "Waiting for proxy..."
        sleep 3
        if curl -sf --connect-timeout 5 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1; then
            CDP_URL="http://${WIN_IP}:${PROXY_PORT}"
            ok "Connected via HTTP proxy"
        fi
    fi
else
    # Desktop: localhost directly
    if curl -sf --connect-timeout 3 "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        CDP_URL="http://localhost:${CDP_PORT}"
        ok "Connected via localhost"
    fi
fi

if [ -z "$CDP_URL" ]; then
    err "Cannot connect to Chrome CDP from WSL"
    echo ""
    echo "Manual fallback:"
    echo "  ./scripts/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
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
# Step 4: Capture cookies via CDP WebSocket
# ============================================================
info "Step 4/4: Capturing cookies..."

# For WebSocket, we need to connect to the actual Chrome WS endpoint
# The HTTP proxy only handles HTTP, not WebSocket
# So we use socat for the WS connection
if $IS_WSL; then
    # Get the WebSocket URL from the HTTP proxy
    WS_INFO=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''):
        print(t.get('webSocketDebuggerUrl',''))
        break
" 2>/dev/null || echo "")

    if [ -z "$WS_INFO" ]; then
        err "${DOMAIN} page not found"
        exit 1
    fi

    # WS URL points to localhost:18892 but we need to reach it from WSL
    # Use socat to bridge WebSocket traffic
    kill $(lsof -t -i :${CDP_PORT} 2>/dev/null) 2>/dev/null || true
    sleep 1

    if ! command -v socat &>/dev/null; then
        info "Installing socat..."
        sudo apt-get update -qq && sudo apt-get install -y -qq socat >/dev/null 2>&1
    fi

    socat TCP-LISTEN:${CDP_PORT},fork,reuseaddr TCP:${WIN_IP}:${PROXY_PORT} &
    SOCAT_PID=$!
    sleep 1

    # Rewrite WS URL to go through socat
    PAGE_WS=$(echo "$WS_INFO" | sed "s|ws://localhost:${CDP_PORT}|ws://localhost:${CDP_PORT}|" | sed "s|ws://127.0.0.1:${CDP_PORT}|ws://localhost:${CDP_PORT}|")
    CDP_HOST="localhost:${CDP_PORT}"
else
    CDP_HOST=$(echo "$CDP_URL" | sed 's|http://||' | cut -d/ -f1)
    PAGE_WS=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys,re
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''):
        ws=t.get('webSocketDebuggerUrl','')
        print(re.sub(r'ws://[^/]+','ws://${CDP_HOST}',ws))
        break
" 2>/dev/null || echo "")
fi

[ -z "${PAGE_WS:-}" ] && { err "${DOMAIN} page not found"; exit 1; }
info "WebSocket: ${PAGE_WS}"

# Install websockets
python3 -c "import websockets" 2>/dev/null || pip3 install websockets -q 2>/dev/null || true

COOKIES_RAW=$(python3 -c "
import asyncio, json, websockets

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

USER_AGENT=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys;print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")
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

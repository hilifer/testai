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

    # Check if Chrome CDP + proxy are already running
    ALREADY_RUNNING=false
    if curl -sf --connect-timeout 2 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1; then
        ALREADY_RUNNING=true
        ok "Chrome + proxy already running, skipping restart"
    fi

    if ! $ALREADY_RUNNING; then
        # Kill old Chrome
        info "Killing old Chrome..."
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
        # Run directly in background (no Start-Process nesting)
        info "Starting HTTP proxy (${PROXY_PORT} -> ${CDP_PORT})..."

        powershell.exe -NoProfile -Command "
          \$l = [System.Net.HttpListener]::new()
          \$l.Prefixes.Add('http://+:${PROXY_PORT}/')
          \$l.Start()
          while (\$true) {
            \$ctx = \$l.GetContext()
            \$path = \$ctx.Request.RawUrl
            try {
              \$r = Invoke-WebRequest -Uri ('http://localhost:${CDP_PORT}' + \$path) -UseBasicParsing -TimeoutSec 10
              \$ctx.Response.StatusCode = \$r.StatusCode
              \$ctx.Response.ContentType = \$r.Headers['Content-Type']
              \$b = [System.Text.Encoding]::UTF8.GetBytes(\$r.Content)
              \$ctx.Response.OutputStream.Write(\$b, 0, \$b.Length)
            } catch {
              \$ctx.Response.StatusCode = 502
            }
            \$ctx.Response.Close()
          }
        " >/dev/null 2>&1 &
        PROXY_PID=$!

        # Wait for proxy to be ready
        info "Waiting for proxy to start..."
        PROXY_OK=false
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if curl -sf --connect-timeout 2 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1; then
                ok "HTTP proxy ready"
                PROXY_OK=true
                break
            fi
            sleep 2
        done
        if ! $PROXY_OK; then
            err "HTTP proxy failed to start"
            exit 1
        fi
    fi

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
# Step 4: Capture cookies via CDP
# ============================================================
info "Step 4/4: Capturing cookies..."

if $IS_WSL; then
    # In WSL, WebSocket doesn't work through HTTP proxy.
    # Use CDP HTTP endpoint to get cookies instead.
    # Step 1: Find the target page ID
    PAGE_ID=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''):
        print(t.get('id',''))
        break
" 2>/dev/null || echo "")

    if [ -z "$PAGE_ID" ]; then
        err "${DOMAIN} page not found"
        exit 1
    fi
    info "Page ID: ${PAGE_ID}"

    # Step 2: Use CDP HTTP API to get cookies
    # Activate the page first, then get cookies via /json/protocol
    # Since HTTP CDP is limited, we use a Python script that connects
    # WebSocket through the HTTP proxy by tunneling

    # Actually, the simplest approach: use PowerShell on Windows to
    # extract cookies and pass them back to WSL
    info "Extracting cookies via Windows PowerShell..."

    COOKIES_RAW=$(powershell.exe -NoProfile -Command "
      \$uri = 'ws://localhost:${CDP_PORT}/devtools/page/${PAGE_ID}'
      \$ws = [System.Net.WebSockets.ClientWebSocket]::new()
      \$ct = [System.Threading.CancellationToken]::None
      \$ws.ConnectAsync(\$uri, \$ct).Wait()

      # Send Network.getCookies
      \$msg = '{\"id\":1,\"method\":\"Network.getCookies\",\"params\":{\"urls\":[\"https://${DOMAIN}\"]}}'
      \$bytes = [System.Text.Encoding]::UTF8.GetBytes(\$msg)
      \$seg = [System.ArraySegment[byte]]::new(\$bytes)
      \$ws.SendAsync(\$seg, [System.Net.WebSockets.WebSocketMessageType]::Text, \$true, \$ct).Wait()

      # Receive response
      \$buf = [byte[]]::new(1048576)
      \$result = ''
      do {
        \$seg = [System.ArraySegment[byte]]::new(\$buf)
        \$recv = \$ws.ReceiveAsync(\$seg, \$ct).Result
        \$result += [System.Text.Encoding]::UTF8.GetString(\$buf, 0, \$recv.Count)
      } while (-not \$recv.EndOfMessage)

      \$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, '', \$ct).Wait()

      # Parse and output just the cookies array
      \$json = \$result | ConvertFrom-Json
      \$cookies = \$json.result.cookies | ForEach-Object {
        @{
          name = \$_.name
          value = \$_.value
          domain = \$_.domain
          path = \$_.path
          http_only = \$_.httpOnly
          secure = \$_.secure
        }
      }
      \$cookies | ConvertTo-Json -Compress
    " 2>/dev/null | tr -d '\r')

else
    # Desktop: direct WebSocket connection
    CDP_HOST=$(echo "$CDP_URL" | sed 's|http://||' | cut -d/ -f1)
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
fi

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
echo -e "${GREEN} Credentials saved!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "  Provider: ${PROVIDER} (${DOMAIN})"
echo "  Cookies:  ${NUM} captured"
echo "  Saved:    ${CRED_FILE}"
echo ""

# ============================================================
# Step 5: Start web-bridge gateway + CLI
# ============================================================
info "Step 5: Starting web-bridge gateway..."

GATEWAY_BIN="${PROJECT_DIR}/rust/target/release/web-bridge"
CLI_BIN="${PROJECT_DIR}/rust/target/release/claw"

# Build if not compiled yet
if [ ! -f "$GATEWAY_BIN" ] || [ ! -f "$CLI_BIN" ]; then
    info "Compiling (first time only)..."
    cd "${PROJECT_DIR}/rust"
    cargo build --release -p web-bridge -p rusty-claude-cli 2>&1 | tail -3
    cd "$PROJECT_DIR"
fi

# Kill old gateway
kill $(lsof -t -i :18899 2>/dev/null) 2>/dev/null || true
sleep 1

# Start gateway in background
"$GATEWAY_BIN" &
GATEWAY_PID=$!
sleep 2

# Verify gateway
if curl -sf --connect-timeout 2 "http://localhost:18899/health" >/dev/null 2>&1; then
    ok "Gateway running on localhost:18899 (PID: ${GATEWAY_PID})"
else
    err "Gateway failed to start"
    exit 1
fi

# Start CLI
echo ""
info "Launching claw CLI..."
echo ""
"$CLI_BIN" --model "${PROVIDER}/deepseek-chat"

# Cleanup on exit
kill $GATEWAY_PID 2>/dev/null || true

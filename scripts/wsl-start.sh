#!/usr/bin/env bash
# ============================================================
# WSL 一键启动: Chrome调试 + 桥接 + 凭证捕获
#
# 用法: ./scripts/wsl-start.sh [provider]
# 例如: ./scripts/wsl-start.sh deepseek
# ============================================================

set -euo pipefail

CDP_PORT=18892
PROVIDER="${1:-deepseek}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================
# Step 1: Get Windows IP
# ============================================================
info "Step 1/5: Detecting Windows IP..."

WIN_IP=$(ip route show default 2>/dev/null | awk '{print $3}')
if [ -z "$WIN_IP" ]; then
    WIN_IP=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
fi
if [ -z "$WIN_IP" ]; then
    err "Cannot detect Windows IP"
    exit 1
fi
ok "Windows IP: ${WIN_IP}"

# ============================================================
# Step 2: Kill old Chrome on Windows, launch debug Chrome
# ============================================================
info "Step 2/5: Starting Chrome on Windows with CDP..."

# Kill old Chrome
info "  Killing old Chrome..."
powershell.exe -NoProfile -Command "Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
sleep 2

# Setup firewall (ignore errors if not admin)
info "  Setting firewall rule..."
powershell.exe -NoProfile -Command "
  Remove-NetFirewallRule -DisplayName 'Claw Chrome CDP' -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName 'Claw Chrome CDP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort ${CDP_PORT} -ErrorAction SilentlyContinue
" >/dev/null 2>&1 || warn "Firewall rule failed (need admin?)"

# Launch Chrome with debug port
PROFILE_WIN='$env:USERPROFILE\.claw\chrome-profile'
info "  Launching Chrome..."
powershell.exe -NoProfile -Command "
  \$chromePaths = @(
    \"\$env:LOCALAPPDATA\\Google\\Chrome\\Application\\chrome.exe\",
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe'
  )
  \$chrome = \$chromePaths | Where-Object { Test-Path \$_ } | Select-Object -First 1
  if (-not \$chrome) { Write-Error 'Chrome not found'; exit 1 }
  \$profileDir = \"\$env:USERPROFILE\\.claw\\chrome-profile\"
  Start-Process \$chrome -ArgumentList '--remote-debugging-port=${CDP_PORT}','--remote-debugging-address=0.0.0.0',\"--user-data-dir=\$profileDir\",'--no-first-run','--no-default-browser-check'
" 2>/dev/null || { err "Failed to launch Chrome"; exit 1; }

# Wait for Chrome to start
sleep 3

# Verify Chrome is running on Windows
CHROME_OK=false
for i in 1 2 3; do
    # Check via Windows localhost
    if powershell.exe -NoProfile -Command "(Invoke-WebRequest -Uri 'http://localhost:${CDP_PORT}/json/version' -UseBasicParsing -TimeoutSec 3).StatusCode" >/dev/null 2>&1; then
        CHROME_OK=true
        break
    fi
    sleep 2
done

if $CHROME_OK; then
    ok "Chrome CDP running on Windows"
else
    err "Chrome failed to start with CDP. Make sure Chrome is installed."
    exit 1
fi

# ============================================================
# Step 3: Start TCP relay (PowerShell on Windows side)
# ============================================================
info "Step 3/5: Starting TCP relay for WSL..."

# Kill old relay
powershell.exe -NoProfile -Command "Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowTitle -match 'Claw-CDP' } | Stop-Process -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
sleep 1

# Start PowerShell relay in background on Windows
# Listens on 0.0.0.0:CDP_PORT and forwards to 127.0.0.1:CDP_PORT
powershell.exe -NoProfile -Command "
  Start-Process powershell -WindowStyle Minimized -ArgumentList '-NoProfile','-Command','
    while(\$true){
      try{
        \$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,${CDP_PORT});
        \$l.Start();
        while(\$true){
          \$c=\$l.AcceptTcpClient();
          \$t=[System.Net.Sockets.TcpClient]::new(\"127.0.0.1\",${CDP_PORT});
          \$cs=\$c.GetStream(); \$ts=\$t.GetStream();
          [System.Threading.Tasks.Task]::Run([Action]{\$cs.CopyTo(\$ts)}).ContinueWith([Action[System.Threading.Tasks.Task]]{\$t.Close()});
          [System.Threading.Tasks.Task]::Run([Action]{\$ts.CopyTo(\$cs)}).ContinueWith([Action[System.Threading.Tasks.Task]]{\$c.Close()})
        }
      }catch{ Start-Sleep 2 }
    }
  '
" 2>/dev/null || true

sleep 2

# ============================================================
# Step 4: Verify WSL can reach Chrome
# ============================================================
info "Step 4/5: Verifying WSL -> Windows connection..."

# Clean up any old socat
kill $(lsof -t -i :${CDP_PORT} 2>/dev/null) 2>/dev/null || true
sleep 1

CDP_URL=""

# Try 1: direct to Windows IP (if relay or 0.0.0.0 works)
if curl -sf --connect-timeout 3 "http://${WIN_IP}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    CDP_URL="http://${WIN_IP}:${CDP_PORT}"
    ok "Direct connection: ${CDP_URL}"
fi

# Try 2: socat bridge as fallback
if [ -z "$CDP_URL" ]; then
    info "  Direct failed, starting socat bridge..."

    # Install socat if needed
    if ! command -v socat &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq socat >/dev/null 2>&1
    fi

    socat TCP-LISTEN:${CDP_PORT},fork,reuseaddr TCP:${WIN_IP}:${CDP_PORT} &
    SOCAT_PID=$!
    sleep 1

    if curl -sf --connect-timeout 3 "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        CDP_URL="http://localhost:${CDP_PORT}"
        ok "Connected via socat bridge: ${CDP_URL}"
    else
        kill $SOCAT_PID 2>/dev/null || true
        err "Cannot reach Chrome from WSL"
        echo ""
        echo "Try manual cookie input instead:"
        echo "  ./scripts/web-login-wsl.sh ${PROVIDER} --cookies \"your_cookies\""
        exit 1
    fi
fi

BROWSER=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Browser','unknown'))" 2>/dev/null || echo "unknown")
ok "Chrome: ${BROWSER}"

# ============================================================
# Step 5: Capture credentials
# ============================================================
echo ""
info "Step 5/5: Capturing ${PROVIDER} credentials..."

# Map provider to domain
case "$PROVIDER" in
    deepseek) DOMAIN="chat.deepseek.com" ;;
    chatgpt)  DOMAIN="chatgpt.com" ;;
    gemini)   DOMAIN="gemini.google.com" ;;
    qwen)     DOMAIN="tongyi.aliyun.com" ;;
    kimi)     DOMAIN="kimi.moonshot.cn" ;;
    *)        err "Unknown provider: $PROVIDER (use: deepseek, chatgpt, gemini, qwen, kimi)"; exit 1 ;;
esac

# Check if the provider page is open
TARGETS=$(curl -sf "${CDP_URL}/json")
HAS_PAGE=$(echo "$TARGETS" | python3 -c "
import json, sys
targets = json.load(sys.stdin)
for t in targets:
    if '${DOMAIN}' in t.get('url', ''):
        print('yes')
        break
" 2>/dev/null || echo "")

if [ "$HAS_PAGE" != "yes" ]; then
    warn "${DOMAIN} not open in Chrome yet"
    info "Opening ${DOMAIN}..."
    # Open the page via Windows
    powershell.exe -NoProfile -Command "Start-Process 'https://${DOMAIN}'" 2>/dev/null || true
    echo ""
    echo -e "${YELLOW}Please log in to ${DOMAIN} in Chrome, then press Enter here...${NC}"
    read -r
fi

# Extract host:port from CDP_URL
CDP_HOST=$(echo "$CDP_URL" | sed 's|http://||' | cut -d/ -f1)

# Get user agent
USER_AGENT=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")

# Find the page and get WebSocket URL
TARGETS=$(curl -sf "${CDP_URL}/json")
PAGE_WS=$(echo "$TARGETS" | python3 -c "
import json, sys, re
targets = json.load(sys.stdin)
for t in targets:
    url = t.get('url', '')
    if '${DOMAIN}' in url:
        ws = t.get('webSocketDebuggerUrl', '')
        # Replace host with our reachable host
        ws = re.sub(r'ws://[^/]+', 'ws://${CDP_HOST}', ws)
        print(ws)
        break
" 2>/dev/null || echo "")

if [ -z "$PAGE_WS" ]; then
    err "Cannot find ${DOMAIN} page in Chrome"
    echo "Please open and log in to https://${DOMAIN} then run again"
    exit 1
fi

info "Found ${DOMAIN} page, extracting cookies..."

# Install websockets if needed
python3 -c "import websockets" 2>/dev/null || pip3 install websockets -q 2>/dev/null || true

# Get cookies via CDP WebSocket
COOKIES_RAW=$(python3 -c "
import asyncio, json
try:
    import websockets
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'websockets', '-q'])
    import websockets

async def get_cookies():
    async with websockets.connect('${PAGE_WS}') as ws:
        await ws.send(json.dumps({
            'id': 1,
            'method': 'Network.getCookies',
            'params': {'urls': ['https://${DOMAIN}']}
        }))
        resp = json.loads(await ws.recv())
        cookies = resp.get('result', {}).get('cookies', [])
        mapped = []
        for c in cookies:
            mapped.append({
                'name': c['name'],
                'value': c['value'],
                'domain': c.get('domain', '${DOMAIN}'),
                'path': c.get('path', '/'),
                'expires': c.get('expires', None),
                'http_only': c.get('httpOnly', False),
                'secure': c.get('secure', True),
            })
        print(json.dumps(mapped))

asyncio.run(get_cookies())
" 2>/dev/null || echo "[]")

if [ "$COOKIES_RAW" = "[]" ] || [ -z "$COOKIES_RAW" ]; then
    err "Auto cookie extraction failed"
    echo ""
    echo "Please input cookies manually:"
    echo "  1. In Chrome, press F12 -> Network tab"
    echo "  2. Send a message on ${DOMAIN}"
    echo "  3. Click any request, copy the Cookie header"
    echo "  4. Run: ./scripts/web-login-wsl.sh ${PROVIDER} --cookies \"paste_here\""
    exit 1
fi

# Save credentials
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
    'cookies': json.loads('''$COOKIES_RAW'''),
    'bearer_token': None,
    'user_agent': $UA_JSON,
    'captured_at': $TIMESTAMP
}
with open(path, 'w') as f:
    json.dump(store, f, indent=2)
"

NUM_COOKIES=$(echo "$COOKIES_RAW" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} ALL DONE!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Provider:    $PROVIDER"
echo "  Domain:      $DOMAIN"
echo "  Cookies:     $NUM_COOKIES captured"
echo "  Saved to:    $CRED_FILE"
echo ""
echo "  Now use:"
echo "    cd ${PROJECT_DIR}/rust"
echo "    ./target/release/rusty-claude-cli --model ${PROVIDER}/deepseek-chat"
echo ""
echo -e "${GREEN}============================================================${NC}"

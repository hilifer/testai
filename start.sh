#!/usr/bin/env bash
# ============================================================
# Claw Code: 一键启动 (自动识别平台)
#
# 用法: ./start.sh [provider]
# 例如: ./start.sh deepseek
#       ./start.sh chatgpt
#
# 自动识别:
#   - Windows WSL2  → 通过 powershell.exe 控制 Windows Chrome
#   - Ubuntu 桌面   → 直接启动本地 Chrome
#   - 无桌面 Linux  → 提示手动输入 cookies
# ============================================================

set -euo pipefail

CDP_PORT=18892
RELAY_PORT=18893
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
# Detect platform
# ============================================================
PLATFORM="linux"

if grep -qi microsoft /proc/version 2>/dev/null; then
    PLATFORM="wsl"
elif [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    PLATFORM="desktop"
else
    PLATFORM="headless"
fi

echo ""
echo "============================================================"
echo " Claw Code: One-Click Start"
echo " Platform: ${PLATFORM}"
echo " Provider: ${PROVIDER}"
echo "============================================================"
echo ""

# ============================================================
# Map provider to domain
# ============================================================
case "$PROVIDER" in
    deepseek) DOMAIN="chat.deepseek.com" ;;
    chatgpt)  DOMAIN="chatgpt.com" ;;
    gemini)   DOMAIN="gemini.google.com" ;;
    qwen)     DOMAIN="tongyi.aliyun.com" ;;
    kimi)     DOMAIN="kimi.moonshot.cn" ;;
    *)        err "Unknown provider: $PROVIDER"; echo "Available: deepseek, chatgpt, gemini, qwen, kimi"; exit 1 ;;
esac

# ============================================================
# Platform-specific: Start Chrome
# ============================================================
start_chrome_wsl() {
    local win_ip=$(ip route show default 2>/dev/null | awk '{print $3}')
    if [ -z "$win_ip" ]; then
        win_ip=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    fi
    echo "$win_ip" > /tmp/claw-win-ip

    info "Windows IP: ${win_ip}"

    # Kill old Chrome
    info "Killing old Chrome..."
    powershell.exe -NoProfile -Command "Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
    sleep 2

    # Firewall
    info "Setting firewall rule..."
    powershell.exe -NoProfile -Command "
      Remove-NetFirewallRule -DisplayName 'Claw Chrome CDP' -ErrorAction SilentlyContinue
      New-NetFirewallRule -DisplayName 'Claw Chrome CDP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort ${CDP_PORT} -ErrorAction SilentlyContinue
    " >/dev/null 2>&1 || warn "Firewall failed (need admin?)"

    # Launch Chrome
    info "Launching Chrome on Windows..."
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

    sleep 3

    # Start TCP relay on RELAY_PORT -> CDP_PORT
    # (Cannot use same port as Chrome, it would conflict)
    info "Starting TCP relay (port ${RELAY_PORT} -> ${CDP_PORT})..."
    powershell.exe -NoProfile -Command "
      Start-Process powershell -WindowStyle Minimized -ArgumentList '-NoProfile','-Command','
        while(\$true){
          try{
            \$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,${RELAY_PORT});
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
}

start_chrome_desktop() {
    # Find Chrome/Chromium
    local chrome=""
    for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
        if command -v "$cmd" &>/dev/null; then
            chrome="$cmd"
            break
        fi
    done

    if [ -z "$chrome" ]; then
        err "Chrome/Chromium not found. Install: sudo apt install chromium-browser"
        exit 1
    fi

    # Kill old Chrome
    info "Killing old Chrome..."
    pkill -f "chrome.*remote-debugging" 2>/dev/null || true
    sleep 1

    # Launch
    local profile="$HOME/.claw/chrome-profile"
    mkdir -p "$profile"
    info "Launching Chrome..."
    "$chrome" \
        --remote-debugging-port=${CDP_PORT} \
        --user-data-dir="$profile" \
        --no-first-run \
        --no-default-browser-check &
    sleep 3
}

start_chrome_headless() {
    warn "No display detected (headless server)"
    echo ""
    echo "On this machine you need to provide cookies manually:"
    echo "  1. Log in to https://${DOMAIN} on another device"
    echo "  2. Open F12 DevTools -> Network -> copy Cookie header"
    echo "  3. Run:"
    echo "     $SCRIPT_DIR/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
    echo ""
    echo "  Or with bearer token:"
    echo "     $SCRIPT_DIR/web-login.sh ${PROVIDER} --token \"your_token\""
    exit 0
}

# ============================================================
# Step 1: Start Chrome based on platform
# ============================================================
info "Step 1/4: Starting Chrome..."
case "$PLATFORM" in
    wsl)      start_chrome_wsl ;;
    desktop)  start_chrome_desktop ;;
    headless) start_chrome_headless ;;
esac

# ============================================================
# Step 2: Find a working CDP connection
# ============================================================
info "Step 2/4: Connecting to Chrome CDP..."

CDP_URL=""
local_win_ip=$(cat /tmp/claw-win-ip 2>/dev/null || ip route show default 2>/dev/null | awk '{print $3}')

# Try 1: localhost on CDP_PORT (desktop, or lucky WSL)
if curl -sf --connect-timeout 3 "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    CDP_URL="http://localhost:${CDP_PORT}"
    ok "Connected via localhost:${CDP_PORT}"
fi

# Try 2: Windows IP on RELAY_PORT (WSL relay)
if [ -z "$CDP_URL" ] && [ "$PLATFORM" = "wsl" ] && [ -n "$local_win_ip" ]; then
    if curl -sf --connect-timeout 3 "http://${local_win_ip}:${RELAY_PORT}/json/version" >/dev/null 2>&1; then
        CDP_URL="http://${local_win_ip}:${RELAY_PORT}"
        ok "Connected via relay ${local_win_ip}:${RELAY_PORT}"
    fi
fi

# Try 3: Windows IP on CDP_PORT direct
if [ -z "$CDP_URL" ] && [ "$PLATFORM" = "wsl" ] && [ -n "$local_win_ip" ]; then
    if curl -sf --connect-timeout 3 "http://${local_win_ip}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        CDP_URL="http://${local_win_ip}:${CDP_PORT}"
        ok "Connected via ${local_win_ip}:${CDP_PORT}"
    fi
fi

# Try 4: socat bridge from WSL to Windows relay port
if [ -z "$CDP_URL" ] && [ "$PLATFORM" = "wsl" ] && [ -n "$local_win_ip" ]; then
    info "Starting socat bridge..."
    if ! command -v socat &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq socat >/dev/null 2>&1
    fi
    # Clean up old socat
    kill $(lsof -t -i :${CDP_PORT} 2>/dev/null) 2>/dev/null || true
    sleep 1
    # Bridge: local CDP_PORT -> Windows RELAY_PORT -> Chrome CDP_PORT
    socat TCP-LISTEN:${CDP_PORT},fork,reuseaddr TCP:${local_win_ip}:${RELAY_PORT} &
    sleep 2
    if curl -sf --connect-timeout 3 "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        CDP_URL="http://localhost:${CDP_PORT}"
        ok "Connected via socat bridge"
    fi
fi

if [ -z "$CDP_URL" ]; then
    err "Cannot connect to Chrome CDP"
    echo ""
    echo "Fallback - input cookies manually:"
    echo "  $SCRIPT_DIR/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
    exit 1
fi

BROWSER=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Browser','unknown'))" 2>/dev/null || echo "unknown")
ok "Connected: ${BROWSER} at ${CDP_URL}"

# ============================================================
# Step 3: Ensure provider page is open & user is logged in
# ============================================================
info "Step 3/4: Checking ${DOMAIN}..."

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
    info "Opening ${DOMAIN}..."
    case "$PLATFORM" in
        wsl)     powershell.exe -NoProfile -Command "Start-Process 'https://${DOMAIN}'" 2>/dev/null || true ;;
        desktop) xdg-open "https://${DOMAIN}" 2>/dev/null || true ;;
    esac
    echo ""
    echo -e "${YELLOW}Please log in to ${DOMAIN} in Chrome, then press Enter...${NC}"
    read -r
fi

# ============================================================
# Step 4: Capture credentials
# ============================================================
info "Step 4/4: Capturing cookies..."

CDP_HOST=$(echo "$CDP_URL" | sed 's|http://||' | cut -d/ -f1)

USER_AGENT=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")

TARGETS=$(curl -sf "${CDP_URL}/json")
PAGE_WS=$(echo "$TARGETS" | python3 -c "
import json, sys, re
targets = json.load(sys.stdin)
for t in targets:
    if '${DOMAIN}' in t.get('url', ''):
        ws = t.get('webSocketDebuggerUrl', '')
        ws = re.sub(r'ws://[^/]+', 'ws://${CDP_HOST}', ws)
        print(ws)
        break
" 2>/dev/null || echo "")

if [ -z "$PAGE_WS" ]; then
    err "${DOMAIN} page not found. Open and log in first."
    exit 1
fi

# Install websockets
python3 -c "import websockets" 2>/dev/null || pip3 install websockets -q 2>/dev/null || true

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
    err "Cookie extraction failed"
    echo "Manual fallback:"
    echo "  $SCRIPT_DIR/web-login.sh ${PROVIDER} --cookies \"your_cookies\""
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
    'cookies': json.loads('''$COOKIES_RAW'''),
    'bearer_token': None,
    'user_agent': $UA_JSON,
    'captured_at': $TIMESTAMP
}
with open(path, 'w') as f:
    json.dump(store, f, indent=2)
"

NUM=$(echo "$COOKIES_RAW" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} DONE! ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Platform:    ${PLATFORM}"
echo "  Provider:    ${PROVIDER} (${DOMAIN})"
echo "  Cookies:     ${NUM} captured"
echo "  Saved to:    ${CRED_FILE}"
echo ""
echo "  Use:"
echo "    cd ${PROJECT_DIR}/rust"
echo "    ./target/release/rusty-claude-cli --model ${PROVIDER}/deepseek-chat"
echo ""

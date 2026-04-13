#!/usr/bin/env bash
# ============================================================
# Claw Code: 一键启动（全自动）
#
# 用法: ./start.sh [provider] [model]
# 例如: ./start.sh deepseek
#       ./start.sh chatgpt gpt-4o
#
# 全自动处理:
#   - 平台检测 (WSL / Ubuntu Desktop / Headless)
#   - WSL: 启动 Windows Chrome + HTTP 代理 + 凭证捕获
#   - 安装 Node.js / pnpm（如果没有）
#   - 配置代理（WSL 网络问题）
#   - 构建 openclaw-zero-token 网关
#   - 凭证自动注入到 openclaw 配置
#   - 启动网关 + claw CLI
# ============================================================

set -euo pipefail

PROVIDER="${1:-deepseek}"
MODEL="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="${HERE}/openclaw-zero-token"
CDP_PORT=18892
PROXY_PORT=18893
GATEWAY_PORT=3001

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Default model per provider ---
if [ -z "$MODEL" ]; then
    case "$PROVIDER" in
        deepseek) MODEL="deepseek-chat" ;;
        chatgpt)  MODEL="gpt-4o" ;;
        gemini)   MODEL="gemini-pro" ;;
        qwen)     MODEL="qwen-max" ;;
        kimi)     MODEL="kimi-chat" ;;
        grok)     MODEL="grok-3" ;;
        *)        err "Unknown: $PROVIDER (use: deepseek chatgpt gemini qwen kimi grok)"; exit 1 ;;
    esac
fi

# --- Provider domain map ---
case "$PROVIDER" in
    deepseek) DOMAIN="chat.deepseek.com" ;;
    chatgpt)  DOMAIN="chatgpt.com" ;;
    gemini)   DOMAIN="gemini.google.com" ;;
    qwen)     DOMAIN="tongyi.aliyun.com" ;;
    kimi)     DOMAIN="kimi.moonshot.cn" ;;
    grok)     DOMAIN="grok.com" ;;
esac

# --- Detect platform ---
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true
HAS_DISPLAY=false
{ [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } && HAS_DISPLAY=true
WIN_IP=""
$IS_WSL && WIN_IP=$(ip route show default 2>/dev/null | awk '{print $3}')

echo ""
echo "============================================================"
echo " Claw Code + OpenClaw Zero Token"
echo " Platform: $($IS_WSL && echo "WSL (Windows IP: ${WIN_IP})" || ($HAS_DISPLAY && echo "Linux Desktop" || echo "Headless"))"
echo " Provider: ${PROVIDER} | Model: ${MODEL}"
echo "============================================================"
echo ""

# --- Cleanup on exit ---
cleanup() {
    [ -n "${PROXY_PID:-}" ] && kill "$PROXY_PID" 2>/dev/null || true
    cd "${OPENCLAW_DIR}" 2>/dev/null && bash ./server.sh stop 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================
# Step 1: WSL Chrome + HTTP 代理（已验证方案）
# ============================================================
if $IS_WSL; then
    info "Step 1/6: Setting up WSL-Windows bridge..."

    # Check if proxy already running
    if curl -sf --connect-timeout 2 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1; then
        ok "Chrome + proxy already running"
    else
        # Kill old Chrome
        info "Starting Chrome on Windows..."
        powershell.exe -NoProfile -Command "Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
        sleep 2

        # Firewall
        powershell.exe -NoProfile -Command "
          Remove-NetFirewallRule -DisplayName 'Claw Chrome CDP' -ErrorAction SilentlyContinue
          New-NetFirewallRule -DisplayName 'Claw Chrome CDP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort ${CDP_PORT},${PROXY_PORT} -ErrorAction SilentlyContinue
        " >/dev/null 2>&1 || true

        # Launch Chrome
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

        # Verify Chrome on Windows
        CHROME_OK=false
        for i in 1 2 3 4 5; do
            if powershell.exe -NoProfile -Command "(Invoke-WebRequest -Uri 'http://localhost:${CDP_PORT}/json/version' -UseBasicParsing -TimeoutSec 3).StatusCode" >/dev/null 2>&1; then
                CHROME_OK=true; break
            fi
            sleep 2
        done
        $CHROME_OK || { err "Chrome CDP not responding"; exit 1; }
        ok "Chrome running on Windows"

        # Start HTTP proxy (PowerShell HttpListener - proven working)
        info "Starting HTTP proxy..."
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
            } catch { \$ctx.Response.StatusCode = 502 }
            \$ctx.Response.Close()
          }
        " >/dev/null 2>&1 &
        PROXY_PID=$!

        # Wait for proxy
        for i in 1 2 3 4 5 6 7 8 9 10; do
            curl -sf --connect-timeout 2 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1 && break
            sleep 2
        done
        curl -sf --connect-timeout 2 "http://${WIN_IP}:${PROXY_PORT}/json/version" >/dev/null 2>&1 || { err "HTTP proxy failed"; exit 1; }
        ok "HTTP proxy ready"
    fi

    CDP_URL="http://${WIN_IP}:${PROXY_PORT}"

elif $HAS_DISPLAY; then
    info "Step 1/6: Starting Chrome..."
    CHROME=""
    for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
        command -v "$cmd" &>/dev/null && CHROME="$cmd" && break
    done
    [ -z "$CHROME" ] && { err "Chrome not found: sudo apt install chromium-browser"; exit 1; }
    pkill -f "chrome.*remote-debugging" 2>/dev/null || true
    sleep 1
    mkdir -p "$HOME/.claw/chrome-profile"
    "$CHROME" --remote-debugging-port=${CDP_PORT} --user-data-dir="$HOME/.claw/chrome-profile" --no-first-run &
    sleep 3
    CDP_URL="http://localhost:${CDP_PORT}"
else
    info "Step 1/6: Headless mode - skipping Chrome"
    CDP_URL=""
fi

# ============================================================
# Step 2: Capture credentials
# ============================================================
CRED_FILE="${CLAW_CONFIG_HOME:-$HOME/.claw}/web-credentials.json"

if [ -n "$CDP_URL" ]; then
    info "Step 2/6: Capturing ${PROVIDER} credentials..."

    # Check if page is open
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
        echo -e "${YELLOW}Log in to ${DOMAIN} in Chrome, then press Enter...${NC}"
        read -r
    fi

    # Get page ID
    PAGE_ID=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''):
        print(t.get('id','')); break
" 2>/dev/null || echo "")

    if [ -n "$PAGE_ID" ]; then
        info "Extracting cookies..."
        if $IS_WSL; then
            COOKIES_RAW=$(powershell.exe -NoProfile -Command "
              \$ws = [System.Net.WebSockets.ClientWebSocket]::new()
              \$ct = [System.Threading.CancellationToken]::None
              \$ws.ConnectAsync('ws://localhost:${CDP_PORT}/devtools/page/${PAGE_ID}', \$ct).Wait()
              \$msg = '{\"id\":1,\"method\":\"Network.getCookies\",\"params\":{\"urls\":[\"https://${DOMAIN}\"]}}'
              \$bytes = [System.Text.Encoding]::UTF8.GetBytes(\$msg)
              \$ws.SendAsync([System.ArraySegment[byte]]::new(\$bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, \$true, \$ct).Wait()
              \$buf = [byte[]]::new(1048576)
              \$result = ''
              do {
                \$seg = [System.ArraySegment[byte]]::new(\$buf)
                \$recv = \$ws.ReceiveAsync(\$seg, \$ct).Result
                \$result += [System.Text.Encoding]::UTF8.GetString(\$buf, 0, \$recv.Count)
              } while (-not \$recv.EndOfMessage)
              \$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, '', \$ct).Wait()
              \$json = \$result | ConvertFrom-Json
              \$json.result.cookies | ForEach-Object {
                @{ name=\$_.name; value=\$_.value; domain=\$_.domain; path=\$_.path; http_only=\$_.httpOnly; secure=\$_.secure }
              } | ConvertTo-Json -Compress
            " 2>/dev/null | tr -d '\r')
        else
            python3 -c "import websockets" 2>/dev/null || pip3 install websockets -q 2>/dev/null || true
            CDP_HOST=$(echo "$CDP_URL" | sed 's|http://||')
            PAGE_WS=$(curl -sf "${CDP_URL}/json" | python3 -c "
import json,sys,re
for t in json.load(sys.stdin):
    if '${DOMAIN}' in t.get('url',''):
        print(re.sub(r'ws://[^/]+','ws://${CDP_HOST}',t.get('webSocketDebuggerUrl',''))); break
" 2>/dev/null || echo "")
            COOKIES_RAW=$(python3 -c "
import asyncio,json,websockets
async def m():
    async with websockets.connect('${PAGE_WS}') as ws:
        await ws.send(json.dumps({'id':1,'method':'Network.getCookies','params':{'urls':['https://${DOMAIN}']}}))
        r=json.loads(await ws.recv())
        print(json.dumps([{'name':c['name'],'value':c['value'],'domain':c.get('domain',''),'path':c.get('path','/'),'http_only':c.get('httpOnly',False),'secure':c.get('secure',True)} for c in r.get('result',{}).get('cookies',[])]))
asyncio.run(m())
" 2>/dev/null || echo "[]")
        fi

        if [ -n "$COOKIES_RAW" ] && [ "$COOKIES_RAW" != "[]" ]; then
            mkdir -p "$(dirname "$CRED_FILE")"
            USER_AGENT=$(curl -sf "${CDP_URL}/json/version" | python3 -c "import json,sys;print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")
            python3 -c "
import json,os
path='${CRED_FILE}'
store={'credentials':{}}
if os.path.exists(path):
    with open(path) as f: store=json.load(f)
store.setdefault('credentials',{})
store['credentials']['${PROVIDER}']={
    'provider':'${PROVIDER}',
    'cookies':json.loads(open('/dev/stdin').read()),
    'bearer_token':None,
    'user_agent':'${USER_AGENT}' or None,
    'captured_at':$(date +%s)
}
with open(path,'w') as f: json.dump(store,f,indent=2)
" <<< "$COOKIES_RAW"
            NUM=$(echo "$COOKIES_RAW" | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
            ok "Captured ${NUM} cookies for ${PROVIDER}"
        else
            warn "Cookie capture failed, will try existing credentials"
        fi
    fi
else
    info "Step 2/6: Skipping (headless mode)"
fi

# ============================================================
# Step 3: Setup proxy for npm/cargo (WSL network fix)
# ============================================================
info "Step 3/6: Checking network..."

if $IS_WSL; then
    # Test if npm registry is reachable
    if ! curl -sf --connect-timeout 5 "https://registry.npmjs.org" >/dev/null 2>&1; then
        # Try Windows proxy
        for port in 7890 10809 1080; do
            if curl -sf --connect-timeout 3 --proxy "http://${WIN_IP}:${port}" "https://registry.npmjs.org" >/dev/null 2>&1; then
                export http_proxy="http://${WIN_IP}:${port}"
                export https_proxy="$http_proxy"
                ok "Using proxy ${WIN_IP}:${port}"
                break
            fi
        done
    fi
fi
ok "Network ready"

# ============================================================
# Step 4: Install Node.js + build openclaw-zero-token
# ============================================================
info "Step 4/6: Preparing openclaw-zero-token..."

# Submodule check
if [ ! -f "${OPENCLAW_DIR}/package.json" ]; then
    git submodule update --init --recursive 2>/dev/null || { err "Submodule init failed"; exit 1; }
fi

# Node.js
if ! command -v node &>/dev/null; then
    info "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_22.x 2>/dev/null | sudo -E bash - 2>/dev/null
    sudo apt-get install -y nodejs 2>/dev/null || {
        # Fallback: use nvm
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh 2>/dev/null | bash 2>/dev/null
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install 22 2>/dev/null
    }
fi
ok "Node.js: $(node --version 2>/dev/null || echo 'not found')"

# pnpm
if ! command -v pnpm &>/dev/null; then
    npm install -g pnpm 2>/dev/null || true
fi

# Build
cd "${OPENCLAW_DIR}"
if [ ! -d "node_modules" ]; then
    info "Installing dependencies..."
    pnpm install 2>&1 | tail -3
fi
if [ ! -d "dist" ]; then
    info "Building..."
    pnpm build 2>&1 | tail -3
fi
ok "openclaw-zero-token ready"
cd "${HERE}"

# ============================================================
# Step 5: Inject credentials into openclaw config + start gateway
# ============================================================
info "Step 5/6: Starting gateway..."

STATE_DIR="${OPENCLAW_DIR}/.openclaw-upstream-state"
OPENCLAW_CONFIG="${STATE_DIR}/openclaw.json"
mkdir -p "$STATE_DIR"

# Ensure openclaw.json exists (copy from example if needed)
if [ ! -f "$OPENCLAW_CONFIG" ] && [ -f "${OPENCLAW_DIR}/.openclaw-state.example/openclaw.json" ]; then
    cp "${OPENCLAW_DIR}/.openclaw-state.example/openclaw.json" "$OPENCLAW_CONFIG"
fi

# Convert captured cookies to auth-profiles.json (NOT openclaw.json)
# openclaw-zero-token stores web credentials in auth-profiles.json
# with type=token and the cookie/bearer data JSON-serialized in the token field
if [ -f "$CRED_FILE" ]; then
    AGENT_DIR="${HOME}/.openclaw/agents/default/agent"
    mkdir -p "$AGENT_DIR"
    AUTH_PROFILES="${AGENT_DIR}/auth-profiles.json"

    python3 -c "
import json, os

claw = json.load(open('${CRED_FILE}'))
creds = claw.get('credentials', {})

# Load existing auth-profiles or create new
profiles_path = '${AUTH_PROFILES}'
store = {'version': 1, 'profiles': {}}
if os.path.exists(profiles_path):
    with open(profiles_path) as f:
        store = json.load(f)

for provider, data in creds.items():
    cookies = data.get('cookies', [])
    cookie_str = '; '.join(f\"{c['name']}={c['value']}\" for c in cookies)
    bearer = data.get('bearer_token', '') or ''
    ua = data.get('user_agent', '') or ''

    profile_id = f'{provider}-web:default'
    # Format matches what onboard-web-auth.ts produces
    token_data = json.dumps({'cookie': cookie_str, 'bearer': bearer, 'userAgent': ua})
    store['profiles'][profile_id] = {
        'type': 'token',
        'provider': f'{provider}-web',
        'token': token_data
    }

with open(profiles_path, 'w') as f:
    json.dump(store, f, indent=2)
print(f'Injected {len(creds)} provider(s) into auth-profiles.json')
" 2>/dev/null || warn "Credential injection failed"
fi

# Start gateway (if not already running)
if curl -sf --connect-timeout 2 "http://localhost:${GATEWAY_PORT}/v1/models" >/dev/null 2>&1; then
    ok "Gateway already running"
else
    cd "${OPENCLAW_DIR}"
    bash ./server.sh start 2>&1 | tail -5 || true
    cd "${HERE}"

    # Wait up to 90 seconds for gateway (first start can be slow)
    GATEWAY_OK=false
    info "Waiting for gateway (may take up to 90s on first start)..."
    for i in $(seq 1 30); do
        if curl -sf --connect-timeout 2 "http://localhost:${GATEWAY_PORT}/v1/models" >/dev/null 2>&1; then
            GATEWAY_OK=true; break
        fi
        sleep 3
    done
    if $GATEWAY_OK; then
        ok "Gateway running on :${GATEWAY_PORT}"
    else
        warn "Gateway health check failed, but it may still be starting."
        warn "Check log: tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log"
        warn "Continuing anyway..."
    fi
fi

# ============================================================
# Step 6: Start claw CLI
# ============================================================
info "Step 6/6: Starting claw..."

CLI_BIN="${HERE}/rust/target/release/claw"
if [ ! -f "$CLI_BIN" ]; then
    info "Compiling claw CLI..."
    cd "${HERE}/rust"
    cargo build --release -p rusty-claude-cli 2>&1 | tail -3
    cd "${HERE}"
fi

export OPENAI_BASE_URL="http://localhost:${GATEWAY_PORT}/v1"
export OPENAI_API_KEY="local"

CLAW_MODEL="openai/${PROVIDER}-web/${MODEL}"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Ready!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "  Gateway: http://localhost:${GATEWAY_PORT}"
echo "  Model:   ${CLAW_MODEL}"
echo ""

"$CLI_BIN" --model "${CLAW_MODEL}"

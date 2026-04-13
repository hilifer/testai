#!/usr/bin/env bash
# ============================================================
# Claw Code + OpenClaw Zero Token: 一键启动
#
# 用法: ./start.sh [provider] [model]
# 例如: ./start.sh deepseek
#       ./start.sh chatgpt
#       ./start.sh deepseek deepseek-reasoner
#
# 自动完成:
#   1. 检测平台 (WSL / Ubuntu / Headless)
#   2. 安装 Node.js (如果没有)
#   3. 构建 openclaw-zero-token 网关
#   4. 启动网关 (端口 3001)
#   5. 启动 claw CLI 连接网关
# ============================================================

set -euo pipefail

PROVIDER="${1:-deepseek}"
MODEL="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="${SCRIPT_DIR}/openclaw-zero-token"
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
        *)        MODEL="default" ;;
    esac
fi

# Map to openclaw model format: provider-web/model
OPENCLAW_MODEL="${PROVIDER}-web/${MODEL}"
# For claw CLI: use openai compat format
CLAW_MODEL="openai/${OPENCLAW_MODEL}"

# --- Detect platform ---
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true

echo ""
echo "============================================================"
echo " Claw Code + OpenClaw Zero Token"
echo " Platform: $($IS_WSL && echo "WSL" || echo "Linux")"
echo " Provider: ${PROVIDER} | Model: ${MODEL}"
echo "============================================================"
echo ""

# ============================================================
# Step 1: Check openclaw-zero-token submodule
# ============================================================
info "Step 1/5: Checking openclaw-zero-token..."

if [ ! -f "${OPENCLAW_DIR}/package.json" ]; then
    info "Initializing submodule..."
    git submodule update --init --recursive 2>/dev/null || {
        err "openclaw-zero-token submodule not found"
        echo "Run: git submodule update --init --recursive"
        exit 1
    }
fi
ok "openclaw-zero-token found"

# ============================================================
# Step 2: Install Node.js + pnpm if needed
# ============================================================
info "Step 2/5: Checking Node.js..."

if ! command -v node &>/dev/null; then
    info "Installing Node.js..."
    if command -v apt-get &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>/dev/null
        sudo apt-get install -y nodejs 2>/dev/null
    else
        curl -fsSL https://fnm.vercel.app/install | bash 2>/dev/null
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env)" 2>/dev/null
        fnm install 22 2>/dev/null
    fi
fi

NODE_VER=$(node --version 2>/dev/null || echo "none")
ok "Node.js: ${NODE_VER}"

if ! command -v pnpm &>/dev/null; then
    info "Installing pnpm..."
    npm install -g pnpm 2>/dev/null || corepack enable 2>/dev/null
fi
ok "pnpm: $(pnpm --version 2>/dev/null || echo 'installed')"

# ============================================================
# Step 3: Build openclaw-zero-token
# ============================================================
info "Step 3/5: Building openclaw-zero-token..."

cd "${OPENCLAW_DIR}"

if [ ! -d "node_modules" ]; then
    info "Installing dependencies (first time, may take a few minutes)..."
    pnpm install 2>&1 | tail -3
fi

if [ ! -d "dist" ]; then
    info "Building..."
    pnpm build 2>&1 | tail -3
fi

ok "openclaw-zero-token built"
cd "${SCRIPT_DIR}"

# ============================================================
# Step 4: Configure credentials + start gateway
# ============================================================
info "Step 4/5: Starting openclaw gateway..."

# Check if gateway already running
if curl -sf --connect-timeout 2 "http://localhost:${GATEWAY_PORT}/v1/models" >/dev/null 2>&1; then
    ok "Gateway already running on port ${GATEWAY_PORT}"
else
    # Need to configure provider credentials
    STATE_DIR="${OPENCLAW_DIR}/.openclaw-upstream-state"
    CONFIG_FILE="${STATE_DIR}/openclaw.json"

    if [ ! -f "$CONFIG_FILE" ]; then
        info "First time setup: need to configure ${PROVIDER} credentials"
        echo ""

        if $IS_WSL; then
            echo "=== WSL: Browser Login ==="
            echo ""
            echo "Option A: Run the onboarding wizard"
            echo "  cd ${OPENCLAW_DIR}"
            echo "  ./start-chrome-debug.sh   # Terminal 1: opens Chrome"
            echo "  ./onboard.sh webauth      # Terminal 2: captures credentials"
            echo ""
            echo "Option B: Manual cookie input"
            echo "  1. Open https://chat.deepseek.com in your browser"
            echo "  2. Press F12 -> Network -> send a message"
            echo "  3. Copy the Cookie and Authorization headers"
            echo ""
        else
            echo "Running onboarding wizard..."
            cd "${OPENCLAW_DIR}"
            bash ./start-chrome-debug.sh &
            sleep 3
            echo "Log in to your AI provider in the Chrome window, then run:"
            echo "  cd ${OPENCLAW_DIR} && ./onboard.sh webauth"
            echo ""
            echo "After onboarding, re-run: ./start.sh ${PROVIDER}"
            exit 0
        fi

        # Try to use existing claw credentials if available
        CLAW_CREDS="${CLAW_CONFIG_HOME:-$HOME/.claw}/web-credentials.json"
        if [ -f "$CLAW_CREDS" ]; then
            info "Found existing credentials at ${CLAW_CREDS}"
            info "Converting to openclaw format..."

            mkdir -p "$STATE_DIR"

            # Convert claw credentials to openclaw config
            python3 -c "
import json, os

claw = json.load(open('${CLAW_CREDS}'))
creds = claw.get('credentials', {})

config = {
    'auth': {'profiles': {}},
    'models': {'providers': {}},
    'gateway': {
        'port': ${GATEWAY_PORT},
        'auth': {'mode': 'none'}
    }
}

for provider, data in creds.items():
    cookies = data.get('cookies', [])
    cookie_str = '; '.join(f\"{c['name']}={c['value']}\" for c in cookies)
    bearer = data.get('bearer_token', '')
    ua = data.get('user_agent', '')

    profile_key = f'{provider}-web:default'
    config['auth']['profiles'][profile_key] = {
        'provider': f'{provider}-web',
        'mode': 'cookie',
        'cookies': cookie_str,
        'bearerToken': bearer or '',
        'userAgent': ua or ''
    }

with open('${CONFIG_FILE}', 'w') as f:
    json.dump(config, f, indent=2)

print(f'Converted {len(creds)} provider(s)')
" || warn "Credential conversion failed, may need manual onboarding"
        fi

        if [ ! -f "$CONFIG_FILE" ]; then
            warn "No credentials configured"
            echo "Please run the onboarding wizard first:"
            echo "  cd ${OPENCLAW_DIR}"
            echo "  ./onboard.sh webauth"
            echo ""
            echo "Then re-run: ./start.sh ${PROVIDER}"
            exit 1
        fi
    fi

    # Start gateway
    info "Starting gateway on port ${GATEWAY_PORT}..."
    cd "${OPENCLAW_DIR}"
    bash ./server.sh start 2>&1 | tail -5 || bash ./server.sh restart 2>&1 | tail -5
    cd "${SCRIPT_DIR}"

    # Wait for gateway
    GATEWAY_OK=false
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if curl -sf --connect-timeout 2 "http://localhost:${GATEWAY_PORT}/v1/models" >/dev/null 2>&1; then
            GATEWAY_OK=true
            break
        fi
        sleep 2
    done

    if $GATEWAY_OK; then
        ok "Gateway running on port ${GATEWAY_PORT}"
    else
        err "Gateway failed to start"
        echo "Try manually: cd ${OPENCLAW_DIR} && ./server.sh start"
        exit 1
    fi
fi

# ============================================================
# Step 5: Start claw CLI
# ============================================================
info "Step 5/5: Starting claw CLI..."

CLI_BIN="${SCRIPT_DIR}/rust/target/release/claw"

if [ ! -f "$CLI_BIN" ]; then
    info "Compiling claw CLI (first time)..."
    cd "${SCRIPT_DIR}/rust"
    cargo build --release -p rusty-claude-cli 2>&1 | tail -3
    cd "${SCRIPT_DIR}"
fi

# Configure claw to use openclaw gateway
export OPENAI_BASE_URL="http://localhost:${GATEWAY_PORT}/v1"
export OPENAI_API_KEY="local"

# Cleanup on exit
cleanup() {
    cd "${OPENCLAW_DIR}" && bash ./server.sh stop 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Ready!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "  Gateway:  http://localhost:${GATEWAY_PORT}"
echo "  Model:    ${CLAW_MODEL}"
echo ""

"$CLI_BIN" --model "${CLAW_MODEL}"

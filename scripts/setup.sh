#!/usr/bin/env bash
# ============================================================
# Claw Code + Web-Bridge: 一键安装脚本 (WSL / Ubuntu)
# ============================================================
# 用法: ./scripts/setup.sh
#
# 自动检测环境 (WSL / 原生 Ubuntu)，安装依赖，配置代理，编译项目。
# ============================================================

set -euo pipefail

# --- 颜色输出 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- 检测环境 ---
detect_environment() {
    info "检测运行环境..."

    IS_WSL=false
    WIN_HOST_IP=""

    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
        # 获取 Windows 宿主机 IP (WSL2 通过 resolv.conf 获取)
        WIN_HOST_IP=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' || true)
        ok "检测到 WSL 环境"
        info "Windows 宿主机 IP: ${WIN_HOST_IP:-未知}"
    else
        ok "检测到原生 Linux 环境"
    fi

    echo ""
}

# --- 配置代理 (仅 WSL) ---
setup_proxy() {
    if ! $IS_WSL; then
        return
    fi

    info "检查网络连接..."

    # 测试直连
    if curl -sf --connect-timeout 5 https://crates.io >/dev/null 2>&1; then
        ok "网络直连正常，无需代理"
        return
    fi

    warn "直连失败，尝试通过 Windows 代理连接..."

    # 常见代理端口: 7890 (Clash), 10809 (v2ray), 1080 (SS)
    PROXY_PORTS=(7890 10809 1080 10808 8080)

    for port in "${PROXY_PORTS[@]}"; do
        proxy_url="http://${WIN_HOST_IP}:${port}"
        if curl -sf --connect-timeout 3 --proxy "$proxy_url" https://crates.io >/dev/null 2>&1; then
            ok "代理可用: ${proxy_url}"
            export http_proxy="$proxy_url"
            export https_proxy="$proxy_url"
            export HTTP_PROXY="$proxy_url"
            export HTTPS_PROXY="$proxy_url"
            export no_proxy="localhost,127.0.0.1"

            # 写入 shell 配置以便后续使用
            PROXY_CONFIG="
# Claw Code WSL Proxy
export http_proxy=\"$proxy_url\"
export https_proxy=\"$proxy_url\"
export no_proxy=\"localhost,127.0.0.1\"
"
            if ! grep -q "Claw Code WSL Proxy" ~/.bashrc 2>/dev/null; then
                echo "$PROXY_CONFIG" >> ~/.bashrc
                info "代理配置已写入 ~/.bashrc"
            fi
            return
        fi
    done

    warn "未找到可用代理。如果编译时下载超时，请手动设置:"
    warn "  export http_proxy=http://${WIN_HOST_IP}:你的代理端口"
    warn "  export https_proxy=\$http_proxy"
    echo ""
}

# --- 安装系统依赖 ---
install_system_deps() {
    info "安装系统依赖..."

    if ! command -v apt-get &>/dev/null; then
        err "仅支持 apt 包管理器 (Ubuntu/Debian)"
        exit 1
    fi

    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential pkg-config libssl-dev curl git python3 >/dev/null 2>&1
    ok "系统依赖已安装"
}

# --- 安装 Rust ---
install_rust() {
    if command -v rustc &>/dev/null; then
        local ver=$(rustc --version | awk '{print $2}')
        ok "Rust 已安装: ${ver}"
        return
    fi

    info "安装 Rust 工具链..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
    ok "Rust 安装完成: $(rustc --version | awk '{print $2}')"
}

# --- 配置 Cargo 国内镜像 ---
setup_cargo_mirror() {
    info "检查 Cargo 下载速度..."

    # 测试 crates.io 速度
    if curl -sf --connect-timeout 5 --max-time 10 https://index.crates.io >/dev/null 2>&1; then
        ok "crates.io 连接正常"
        return
    fi

    warn "crates.io 连接慢，配置国内镜像..."

    mkdir -p ~/.cargo
    cat > ~/.cargo/config.toml << 'TOML'
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
TOML

    ok "已配置中科大镜像"
}

# --- 编译项目 ---
build_project() {
    info "编译项目 (首次编译需要几分钟)..."

    cd "$(dirname "$0")/.."

    # 确保在项目根目录
    if [ ! -f "rust/Cargo.toml" ]; then
        err "未找到 rust/Cargo.toml，请在项目根目录运行"
        exit 1
    fi

    cd rust
    cargo build --release -p web-bridge 2>&1 | tail -5
    ok "web-bridge 编译完成"

    # 编译主 CLI（可能因为缺少某些依赖而失败，不阻塞）
    if cargo build --release -p rusty-claude-cli 2>&1 | tail -5; then
        ok "CLI 编译完成"
    else
        warn "CLI 编译失败（可能缺少依赖），web-bridge 仍可独立使用"
    fi

    cd ..
}

# --- 运行测试 ---
run_tests() {
    info "运行测试..."

    cd "$(dirname "$0")/../rust"
    cargo test -p web-bridge 2>&1 | tail -20

    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -eq 0 ]; then
        ok "所有测试通过"
    else
        err "部分测试失败，请检查上方输出"
    fi

    cd ..
}

# --- 生成 WSL 专用的 Chrome 启动脚本 ---
generate_wsl_chrome_script() {
    if ! $IS_WSL; then
        return
    fi

    info "生成 WSL 专用 Chrome 启动脚本..."

    cat > scripts/web-chrome-wsl.bat << 'BAT'
@echo off
REM ============================================================
REM 在 Windows 上启动 Chrome 调试模式（供 WSL 中的 claw-code 使用）
REM 双击运行此文件，或在 CMD 中运行
REM ============================================================

set CDP_PORT=18892
set CHROME_DIR=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe
set PROFILE_DIR=%USERPROFILE%\.claw\chrome-profile

REM 查找 Chrome
if exist "%CHROME_DIR%" goto found
set CHROME_DIR=C:\Program Files\Google\Chrome\Application\chrome.exe
if exist "%CHROME_DIR%" goto found
set CHROME_DIR=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe
if exist "%CHROME_DIR%" goto found

echo [ERROR] Chrome not found! Please install Google Chrome.
echo Download: https://www.google.com/chrome/
pause
exit /b 1

:found
echo ============================================================
echo  Claw Code: Chrome Debug Mode
echo  CDP Port: %CDP_PORT%
echo  Profile:  %PROFILE_DIR%
echo ============================================================
echo.
echo Chrome is starting in debug mode.
echo After logging in to AI websites, go to WSL and run:
echo   ./scripts/web-login-wsl.sh deepseek
echo.
echo Keep this window open!
echo ============================================================

"%CHROME_DIR%" --remote-debugging-port=%CDP_PORT% --user-data-dir="%PROFILE_DIR%" --no-first-run --no-default-browser-check
BAT

    # 生成 WSL 专用的凭证捕获脚本
    cat > scripts/web-login-wsl.sh << 'BASH'
#!/usr/bin/env bash
# ============================================================
# WSL 专用: 从 Windows Chrome 捕获凭证
# 用法: ./scripts/web-login-wsl.sh <provider> [--cookies "..."] [--token "..."]
# ============================================================

set -euo pipefail

# 获取 Windows 宿主机 IP
WIN_HOST=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
CDP_PORT=18892

if [ -z "$WIN_HOST" ]; then
    echo "[ERROR] 无法获取 Windows IP，请确保在 WSL2 中运行"
    exit 1
fi

PROVIDER="${1:-}"
shift || true

if [ -z "$PROVIDER" ]; then
    echo "用法: $0 <provider> [--cookies \"...\"] [--token \"...\"]"
    echo ""
    echo "提供商: deepseek, chatgpt, gemini, qwen, kimi"
    echo ""
    echo "步骤:"
    echo "  1. 在 Windows 上双击 scripts/web-chrome-wsl.bat"
    echo "  2. 在打开的 Chrome 中登录 AI 网站"
    echo "  3. 在 WSL 中运行此脚本捕获凭证"
    echo ""
    echo "示例:"
    echo "  $0 deepseek"
    echo "  $0 deepseek --cookies \"session=abc; token=xyz\""
    echo "  $0 deepseek --token \"eyJhbGciOi...\""
    exit 1
fi

# 解析参数
COOKIES=""
TOKEN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --cookies) COOKIES="$2"; shift 2 ;;
        --token)   TOKEN="$2"; shift 2 ;;
        *)         echo "未知参数: $1"; exit 1 ;;
    esac
done

# 手动输入 cookies/token 模式
if [ -n "$COOKIES" ] || [ -n "$TOKEN" ]; then
    # 直接调用原始脚本
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    bash "$SCRIPT_DIR/web-login.sh" "$PROVIDER" \
        ${COOKIES:+--cookies "$COOKIES"} \
        ${TOKEN:+--token "$TOKEN"}
    exit $?
fi

# 自动捕获模式: 连接 Windows Chrome CDP
echo "[INFO] 连接 Windows Chrome (${WIN_HOST}:${CDP_PORT})..."

if ! curl -sf --connect-timeout 3 "http://${WIN_HOST}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    echo ""
    echo "[ERROR] 无法连接到 Windows Chrome 调试端口"
    echo ""
    echo "请按以下步骤操作:"
    echo "  1. 在 Windows 上双击: scripts/web-chrome-wsl.bat"
    echo "  2. 在打开的 Chrome 中登录 AI 网站"
    echo "  3. 确保 Windows 防火墙允许端口 ${CDP_PORT}"
    echo ""
    echo "防火墙设置 (在 Windows PowerShell 管理员模式运行):"
    echo "  netsh advfirewall firewall add rule name=\"Chrome CDP\" dir=in action=allow protocol=TCP localport=${CDP_PORT}"
    echo ""
    echo "或者手动输入 cookies:"
    echo "  $0 $PROVIDER --cookies \"your_cookies_here\""
    exit 1
fi

echo "[OK] Chrome 已连接"

# 映射 provider 到域名
case "$PROVIDER" in
    deepseek) DOMAIN="chat.deepseek.com" ;;
    chatgpt)  DOMAIN="chatgpt.com" ;;
    gemini)   DOMAIN="gemini.google.com" ;;
    qwen)     DOMAIN="tongyi.aliyun.com" ;;
    kimi)     DOMAIN="kimi.moonshot.cn" ;;
    *)        echo "[ERROR] 未知 provider: $PROVIDER"; exit 1 ;;
esac

CONFIG_DIR="${CLAW_CONFIG_HOME:-$HOME/.claw}"
CRED_FILE="$CONFIG_DIR/web-credentials.json"
mkdir -p "$CONFIG_DIR"

# 获取 User-Agent
USER_AGENT=$(curl -sf "http://${WIN_HOST}:${CDP_PORT}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")

# 获取页面列表
TARGETS=$(curl -sf "http://${WIN_HOST}:${CDP_PORT}/json")

PAGE_WS=$(echo "$TARGETS" | python3 -c "
import json, sys
targets = json.load(sys.stdin)
for t in targets:
    url = t.get('url', '')
    if '${DOMAIN}' in url:
        # WSL 需要把 ws://localhost 替换为 ws://WIN_HOST
        ws = t.get('webSocketDebuggerUrl', '')
        ws = ws.replace('localhost', '${WIN_HOST}').replace('127.0.0.1', '${WIN_HOST}')
        print(ws)
        break
" 2>/dev/null || echo "")

if [ -z "$PAGE_WS" ]; then
    echo ""
    echo "[ERROR] 在 Chrome 中未找到 ${DOMAIN} 的页面"
    echo ""
    echo "请在 Windows Chrome 中打开并登录:"
    echo "  https://${DOMAIN}"
    echo ""
    echo "然后重新运行: $0 $PROVIDER"
    echo ""
    echo "或手动输入 cookies:"
    echo "  $0 $PROVIDER --cookies \"your_cookies\""
    exit 1
fi

echo "[INFO] 找到 ${DOMAIN} 页面，正在提取 cookies..."

# 通过 CDP WebSocket 获取 cookies
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
    echo "[WARN] 自动提取失败，请手动输入 cookies"
    echo "  $0 $PROVIDER --cookies \"your_cookies\""
    exit 1
fi

TIMESTAMP=$(date +%s)
TOKEN_JSON="null"
UA_JSON="null"
[ -n "$USER_AGENT" ] && UA_JSON="\"$USER_AGENT\""

CRED_JSON="{\"provider\":\"$PROVIDER\",\"cookies\":$COOKIES_RAW,\"bearer_token\":$TOKEN_JSON,\"user_agent\":$UA_JSON,\"captured_at\":$TIMESTAMP}"

# 合并到凭证文件
python3 -c "
import json, os
path = '$CRED_FILE'
store = {'credentials': {}}
if os.path.exists(path):
    with open(path) as f:
        store = json.load(f)
store.setdefault('credentials', {})
store['credentials']['$PROVIDER'] = json.loads('$CRED_JSON')
with open(path, 'w') as f:
    json.dump(store, f, indent=2)
"

NUM_COOKIES=$(echo "$COOKIES_RAW" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")

echo ""
echo "============================================================"
echo " 凭证捕获成功!"
echo " Provider:  $PROVIDER"
echo " Domain:    $DOMAIN"
echo " Cookies:   $NUM_COOKIES 个"
echo " 保存到:    $CRED_FILE"
echo "============================================================"
echo ""
echo "现在可以使用:"
echo "  claw --model $PROVIDER/deepseek-chat"
BASH

    chmod +x scripts/web-login-wsl.sh
    ok "WSL 专用脚本已生成"
    info "  Windows Chrome: scripts/web-chrome-wsl.bat"
    info "  WSL 凭证捕获:  scripts/web-login-wsl.sh"
}

# --- 打印使用说明 ---
print_usage() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN} 安装完成!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""

    if $IS_WSL; then
        echo "=== WSL 使用步骤 ==="
        echo ""
        echo "第 1 步: 在 Windows 上启动 Chrome 调试模式"
        echo "  方法 A: 双击 scripts/web-chrome-wsl.bat"
        echo "  方法 B: 在 Windows CMD 中运行:"
        echo "    chrome.exe --remote-debugging-port=18892 --user-data-dir=\"%USERPROFILE%\\.claw\\chrome-profile\""
        echo ""
        echo "第 2 步: 在 Chrome 中登录 AI 网站"
        echo "  - DeepSeek: https://chat.deepseek.com"
        echo "  - ChatGPT:  https://chatgpt.com"
        echo "  - Gemini:   https://gemini.google.com"
        echo ""
        echo "第 3 步: (可选) Windows 防火墙放行 CDP 端口"
        echo "  在 PowerShell (管理员) 中运行:"
        echo "  netsh advfirewall firewall add rule name=\"Chrome CDP\" dir=in action=allow protocol=TCP localport=18892"
        echo ""
        echo "第 4 步: 在 WSL 中捕获凭证"
        echo "  ./scripts/web-login-wsl.sh deepseek"
        echo "  # 或手动输入:"
        echo "  ./scripts/web-login-wsl.sh deepseek --cookies \"session=abc; token=xyz\""
        echo ""
        echo "第 5 步: 使用 claw"
        echo "  cd rust && ./target/release/rusty-claude-cli --model deepseek/deepseek-chat"
    else
        echo "=== Ubuntu 桌面使用步骤 ==="
        echo ""
        echo "第 1 步: 启动 Chrome 调试模式"
        echo "  ./scripts/web-chrome.sh"
        echo ""
        echo "第 2 步: 在 Chrome 中登录 AI 网站"
        echo ""
        echo "第 3 步: 捕获凭证"
        echo "  ./scripts/web-login.sh deepseek"
        echo ""
        echo "第 4 步: 使用 claw"
        echo "  cd rust && ./target/release/rusty-claude-cli --model deepseek/deepseek-chat"
    fi

    echo ""
    echo "=== 测试 ==="
    echo "  ./scripts/test.sh              # 全部测试"
    echo "  ./scripts/test.sh --web-bridge # 仅 web-bridge 测试"
    echo ""
    echo "=== 支持的模型 ==="
    echo "  deepseek/deepseek-chat     DeepSeek V3"
    echo "  deepseek/deepseek-reasoner DeepSeek R1"
    echo "  chatgpt/gpt-4o             GPT-4o"
    echo "  chatgpt/o3                 o3"
    echo "  gemini/gemini-pro          Gemini Pro"
    echo "  qwen/qwen-max             Qwen Max"
    echo "  kimi/kimi-chat            Kimi Chat"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
echo ""
echo "============================================================"
echo " Claw Code + Web-Bridge 安装脚本"
echo "============================================================"
echo ""

detect_environment
setup_proxy
install_system_deps
install_rust
setup_cargo_mirror
build_project
run_tests
generate_wsl_chrome_script
print_usage

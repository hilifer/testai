#!/usr/bin/env bash
# ============================================================
# WSL 专用: 从 Windows Chrome 捕获凭证
# 用法: ./scripts/web-login-wsl.sh <provider> [--cookies "..."] [--token "..."]
#
# WSL 和 Windows 不共享 localhost，此脚本自动获取 Windows IP
# 并通过 CDP 协议跨网络连接 Windows Chrome。
# ============================================================

set -euo pipefail

# 获取 Windows 宿主机 IP（优先用网关，resolv.conf 可能被代理软件改掉）
WIN_HOST=$(ip route show default 2>/dev/null | awk '{print $3}')
if [ -z "$WIN_HOST" ]; then
    WIN_HOST=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
fi
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

# 手动输入模式: 直接写入凭证文件
if [ -n "$COOKIES" ] || [ -n "$TOKEN" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    # 修复可能的 Windows 换行符
    sed -i 's/\r$//' "$SCRIPT_DIR/web-login.sh" 2>/dev/null || true
    bash "$SCRIPT_DIR/web-login.sh" "$PROVIDER" \
        ${COOKIES:+--cookies "$COOKIES"} \
        ${TOKEN:+--token "$TOKEN"}
    exit $?
fi

# --- 自动捕获模式: 连接 Windows Chrome CDP ---

echo "[INFO] 连接 Windows Chrome (${WIN_HOST}:${CDP_PORT})..."

if ! curl -sf --connect-timeout 3 "http://${WIN_HOST}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    echo ""
    echo "[ERROR] 无法连接到 Windows Chrome 调试端口"
    echo ""
    echo "请按以下步骤操作:"
    echo ""
    echo "  1. 在 Windows 上双击: scripts\\web-chrome-wsl.bat"
    echo ""
    echo "  2. 确保 Windows 防火墙放行端口 ${CDP_PORT}:"
    echo "     (PowerShell 管理员运行)"
    echo "     netsh advfirewall firewall add rule name=\"Chrome CDP\" dir=in action=allow protocol=TCP localport=${CDP_PORT}"
    echo ""
    echo "  3. 在打开的 Chrome 中登录 AI 网站"
    echo ""
    echo "  4. 重新运行: $0 $PROVIDER"
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

# 查找匹配的页面，并替换 WebSocket URL 中的 localhost 为 Windows IP
PAGE_WS=$(echo "$TARGETS" | python3 -c "
import json, sys
targets = json.load(sys.stdin)
for t in targets:
    url = t.get('url', '')
    if '${DOMAIN}' in url:
        ws = t.get('webSocketDebuggerUrl', '')
        ws = ws.replace('localhost', '${WIN_HOST}').replace('127.0.0.1', '${WIN_HOST}')
        print(ws)
        break
" 2>/dev/null || echo "")

if [ -z "$PAGE_WS" ]; then
    echo ""
    echo "[ERROR] 在 Chrome 中未找到 ${DOMAIN} 的页面"
    echo ""
    echo "请在 Windows Chrome 中打开并登录: https://${DOMAIN}"
    echo "然后重新运行: $0 $PROVIDER"
    echo ""
    echo "或手动输入 cookies:"
    echo "  $0 $PROVIDER --cookies \"your_cookies\""
    exit 1
fi

echo "[INFO] 找到 ${DOMAIN} 页面，正在提取 cookies..."

# 安装 websockets (如果需要)
python3 -c "import websockets" 2>/dev/null || pip3 install websockets -q 2>/dev/null || true

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
    echo "[WARN] 自动提取失败"
    echo "请手动输入 cookies:"
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
store['credentials']['$PROVIDER'] = json.loads('''$CRED_JSON''')
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
echo "  cd rust && ./target/release/rusty-claude-cli --model $PROVIDER/deepseek-chat"

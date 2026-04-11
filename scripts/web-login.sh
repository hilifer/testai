#!/usr/bin/env bash
# Capture browser credentials for a web provider.
# Usage: ./scripts/web-login.sh <provider> [--cookies "cookie_string"] [--token "bearer_token"]
#
# Providers: deepseek, chatgpt, gemini, qwen, kimi
#
# Method 1 (automatic): Start Chrome debug mode first, then run this.
# Method 2 (manual): Paste cookies from browser DevTools.

set -euo pipefail

CDP_PORT=18892
CONFIG_DIR="${CLAW_CONFIG_HOME:-$HOME/.claw}"
CRED_FILE="$CONFIG_DIR/web-credentials.json"

usage() {
    echo "Usage: $0 <provider> [options]"
    echo ""
    echo "Providers:"
    echo "  deepseek   - DeepSeek (chat.deepseek.com)"
    echo "  chatgpt    - ChatGPT (chatgpt.com)"
    echo "  gemini     - Google Gemini (gemini.google.com)"
    echo "  qwen       - Qwen/通义千问 (tongyi.aliyun.com)"
    echo "  kimi       - Kimi/Moonshot (kimi.moonshot.cn)"
    echo ""
    echo "Options:"
    echo "  --cookies \"name1=val1; name2=val2\"   Manually set cookies"
    echo "  --token \"bearer_token\"               Manually set bearer token"
    echo ""
    echo "Examples:"
    echo "  # Auto-capture from Chrome debug mode:"
    echo "  $0 deepseek"
    echo ""
    echo "  # Manual cookie input:"
    echo "  $0 deepseek --cookies \"ds_session=abc123; token=xyz\""
    echo ""
    echo "  # Manual with bearer token:"
    echo "  $0 deepseek --token \"eyJhbGciOiJIUz...\""
    exit 1
}

[ $# -lt 1 ] && usage

PROVIDER="$1"
shift

COOKIES=""
TOKEN=""

while [ $# -gt 0 ]; do
    case "$1" in
        --cookies)
            COOKIES="$2"
            shift 2
            ;;
        --token)
            TOKEN="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Map provider to domain
case "$PROVIDER" in
    deepseek) DOMAIN="chat.deepseek.com" ;;
    chatgpt)  DOMAIN="chatgpt.com" ;;
    gemini)   DOMAIN="gemini.google.com" ;;
    qwen)     DOMAIN="tongyi.aliyun.com" ;;
    kimi)     DOMAIN="kimi.moonshot.cn" ;;
    *)
        echo "Unknown provider: $PROVIDER"
        echo "Available: deepseek, chatgpt, gemini, qwen, kimi"
        exit 1
        ;;
esac

mkdir -p "$CONFIG_DIR"

# If cookies provided manually, save directly
if [ -n "$COOKIES" ] || [ -n "$TOKEN" ]; then
    echo "Saving manual credentials for $PROVIDER..."

    # Build cookies JSON array
    COOKIES_JSON="[]"
    if [ -n "$COOKIES" ]; then
        COOKIES_JSON=$(echo "$COOKIES" | python3 -c "
import sys, json
cookies = []
for pair in sys.stdin.read().split(';'):
    pair = pair.strip()
    if '=' in pair:
        name, value = pair.split('=', 1)
        cookies.append({
            'name': name.strip(),
            'value': value.strip(),
            'domain': '$DOMAIN',
            'path': '/',
            'http_only': False,
            'secure': True
        })
print(json.dumps(cookies))
" 2>/dev/null || echo "[]")
    fi

    # Build credential JSON
    TIMESTAMP=$(date +%s)
    TOKEN_JSON="null"
    [ -n "$TOKEN" ] && TOKEN_JSON="\"$TOKEN\""

    CRED_JSON=$(cat <<ENDJSON
{
    "provider": "$PROVIDER",
    "cookies": $COOKIES_JSON,
    "bearer_token": $TOKEN_JSON,
    "user_agent": null,
    "captured_at": $TIMESTAMP
}
ENDJSON
)

    # Merge into credential store
    if [ -f "$CRED_FILE" ]; then
        # Update existing file
        python3 -c "
import json, sys
store = json.load(open('$CRED_FILE'))
store.setdefault('credentials', {})
store['credentials']['$PROVIDER'] = json.loads('''$CRED_JSON''')
json.dump(store, open('$CRED_FILE', 'w'), indent=2)
print('Updated credentials for $PROVIDER')
" 2>/dev/null || {
            # Fallback: create fresh
            echo "{\"credentials\":{\"$PROVIDER\":$CRED_JSON}}" | python3 -m json.tool > "$CRED_FILE"
        }
    else
        echo "{\"credentials\":{\"$PROVIDER\":$CRED_JSON}}" | python3 -m json.tool > "$CRED_FILE"
    fi

    echo "Credentials saved to $CRED_FILE"
    echo ""
    echo "You can now use: claw --model $PROVIDER/deepseek-chat"
    exit 0
fi

# Auto-capture from Chrome debug mode
echo "Attempting to capture credentials from Chrome (CDP port $CDP_PORT)..."

# Check if Chrome is running with CDP
if ! curl -s "http://127.0.0.1:$CDP_PORT/json/version" &>/dev/null; then
    echo ""
    echo "Error: Chrome debug mode not detected on port $CDP_PORT."
    echo ""
    echo "Please run first:"
    echo "  ./scripts/web-chrome.sh"
    echo ""
    echo "Or provide cookies manually:"
    echo "  $0 $PROVIDER --cookies \"your_cookies_here\""
    exit 1
fi

echo "Chrome detected. Extracting cookies for $DOMAIN..."

# Get cookies via CDP
TARGETS=$(curl -s "http://127.0.0.1:$CDP_PORT/json")
USER_AGENT=$(curl -s "http://127.0.0.1:$CDP_PORT/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('User-Agent',''))" 2>/dev/null || echo "")

# Find matching page
PAGE_WS=$(echo "$TARGETS" | python3 -c "
import json, sys
targets = json.load(sys.stdin)
for t in targets:
    url = t.get('url', '')
    if '$DOMAIN' in url:
        print(t.get('webSocketDebuggerUrl', ''))
        break
" 2>/dev/null || echo "")

if [ -z "$PAGE_WS" ]; then
    echo ""
    echo "No page found for $DOMAIN."
    echo "Please open https://$DOMAIN in the Chrome debug window and log in first."
    exit 1
fi

echo "Found matching page. Capturing cookies..."

# Use CDP to get all cookies for the domain
# This sends a Network.getCookies command via the CDP WebSocket
COOKIES_RAW=$(python3 -c "
import asyncio, json, websockets

async def get_cookies():
    async with websockets.connect('$PAGE_WS') as ws:
        await ws.send(json.dumps({
            'id': 1,
            'method': 'Network.getCookies',
            'params': {'urls': ['https://$DOMAIN']}
        }))
        resp = json.loads(await ws.recv())
        cookies = resp.get('result', {}).get('cookies', [])
        mapped = []
        for c in cookies:
            mapped.append({
                'name': c['name'],
                'value': c['value'],
                'domain': c.get('domain', '$DOMAIN'),
                'path': c.get('path', '/'),
                'expires': c.get('expires', None),
                'http_only': c.get('httpOnly', False),
                'secure': c.get('secure', True),
            })
        print(json.dumps(mapped))

asyncio.run(get_cookies())
" 2>/dev/null || echo "[]")

if [ "$COOKIES_RAW" = "[]" ] || [ -z "$COOKIES_RAW" ]; then
    echo ""
    echo "Warning: Could not capture cookies automatically."
    echo "Please provide cookies manually:"
    echo "  $0 $PROVIDER --cookies \"your_cookies_here\""
    echo ""
    echo "To get cookies from Chrome:"
    echo "  1. Open DevTools (F12) on https://$DOMAIN"
    echo "  2. Go to Application > Cookies"
    echo "  3. Copy the cookie values"
    exit 1
fi

TIMESTAMP=$(date +%s)
CRED_JSON=$(cat <<ENDJSON
{
    "provider": "$PROVIDER",
    "cookies": $COOKIES_RAW,
    "bearer_token": null,
    "user_agent": $([ -n "$USER_AGENT" ] && echo "\"$USER_AGENT\"" || echo "null"),
    "captured_at": $TIMESTAMP
}
ENDJSON
)

if [ -f "$CRED_FILE" ]; then
    python3 -c "
import json
store = json.load(open('$CRED_FILE'))
store.setdefault('credentials', {})
store['credentials']['$PROVIDER'] = json.loads('''$CRED_JSON''')
json.dump(store, open('$CRED_FILE', 'w'), indent=2)
"
else
    echo "{\"credentials\":{\"$PROVIDER\":$CRED_JSON}}" | python3 -m json.tool > "$CRED_FILE"
fi

NUM_COOKIES=$(echo "$COOKIES_RAW" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")

echo ""
echo "=== Success ==="
echo "Provider:  $PROVIDER"
echo "Domain:    $DOMAIN"
echo "Cookies:   $NUM_COOKIES captured"
echo "Saved to:  $CRED_FILE"
echo ""
echo "You can now use:"
echo "  claw --model $PROVIDER/deepseek-chat"
echo "  claw --model $PROVIDER/deepseek-reasoner"

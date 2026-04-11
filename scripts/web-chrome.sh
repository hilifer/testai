#!/usr/bin/env bash
# Launch Chrome in debug mode for web-bridge credential capture.
# Usage: ./scripts/web-chrome.sh
#
# This opens Chrome with remote debugging enabled on port 18892.
# After Chrome opens, log in to your AI provider(s):
#   - https://chat.deepseek.com
#   - https://chatgpt.com
#   - https://gemini.google.com
#   - https://tongyi.aliyun.com (Qwen)
#   - https://kimi.moonshot.cn
#
# Then run `claw web-login <provider>` in another terminal to capture credentials.

set -euo pipefail

CDP_PORT=18892
PROFILE_DIR="${CLAW_CONFIG_HOME:-$HOME/.claw}/chrome-profile"

# Find Chrome/Chromium
find_chrome() {
    local candidates=(
        "google-chrome"
        "google-chrome-stable"
        "chromium"
        "chromium-browser"
        "/usr/bin/google-chrome"
        "/usr/bin/chromium"
        "/usr/bin/chromium-browser"
        "/snap/bin/chromium"
        # macOS
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    )

    for cmd in "${candidates[@]}"; do
        if command -v "$cmd" &>/dev/null || [ -x "$cmd" ]; then
            echo "$cmd"
            return 0
        fi
    done

    echo ""
    return 1
}

CHROME=$(find_chrome)
if [ -z "$CHROME" ]; then
    echo "Error: Chrome/Chromium not found."
    echo "Please install Chrome or Chromium first."
    echo ""
    echo "  Ubuntu/Debian: sudo apt install chromium-browser"
    echo "  macOS:         brew install --cask google-chrome"
    echo "  Arch:          sudo pacman -S chromium"
    exit 1
fi

echo "=== Claw Web-Bridge: Chrome Debug Mode ==="
echo ""
echo "Chrome:  $CHROME"
echo "CDP Port: $CDP_PORT"
echo "Profile: $PROFILE_DIR"
echo ""
echo "After Chrome opens, log in to your AI provider(s):"
echo "  - DeepSeek:  https://chat.deepseek.com"
echo "  - ChatGPT:   https://chatgpt.com"
echo "  - Gemini:    https://gemini.google.com"
echo "  - Qwen:      https://tongyi.aliyun.com"
echo "  - Kimi:      https://kimi.moonshot.cn"
echo ""
echo "Then open another terminal and run:"
echo "  claw web-login deepseek"
echo ""
echo "Press Ctrl+C to stop Chrome."
echo ""

mkdir -p "$PROFILE_DIR"

exec "$CHROME" \
    --remote-debugging-port=$CDP_PORT \
    --user-data-dir="$PROFILE_DIR" \
    --no-first-run \
    --no-default-browser-check \
    "$@"

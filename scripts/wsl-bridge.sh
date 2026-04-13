#!/usr/bin/env bash
# ============================================================
# WSL: Connect to Windows Chrome CDP (one-click)
#
# Solves all WSL-to-Windows connectivity issues:
# 1. Chrome only listens on 127.0.0.1 (not reachable from WSL)
# 2. resolv.conf may not contain the real Windows IP
# 3. Windows firewall may block connections
#
# Usage: ./scripts/wsl-bridge.sh [start|stop|status]
# ============================================================

set -euo pipefail

CDP_PORT=18892
SOCAT_PID_FILE="/tmp/claw-wsl-bridge.pid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Get Windows host IP ---
get_win_ip() {
    # Method 1: default gateway (most reliable)
    local ip=$(ip route show default 2>/dev/null | awk '{print $3}')

    # Method 2: resolv.conf fallback
    if [ -z "$ip" ]; then
        ip=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    fi

    # Method 3: WSL interop
    if [ -z "$ip" ]; then
        ip=$(cat /proc/net/tcp 2>/dev/null | awk 'NR==2{print $3}' | cut -d: -f1 | sed 's/../0x& /g' | awk '{printf "%d.%d.%d.%d", $4, $3, $2, $1}')
    fi

    echo "$ip"
}

# --- Install socat if needed ---
ensure_socat() {
    if command -v socat &>/dev/null; then
        return
    fi
    echo -e "${YELLOW}[WARN]${NC} socat not installed, installing..."
    sudo apt-get update -qq && sudo apt-get install -y -qq socat >/dev/null 2>&1
    if ! command -v socat &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Failed to install socat"
        exit 1
    fi
}

# --- Start bridge ---
start_bridge() {
    local win_ip=$(get_win_ip)

    if [ -z "$win_ip" ]; then
        echo -e "${RED}[ERROR]${NC} Cannot detect Windows IP"
        exit 1
    fi

    echo "Windows IP: ${win_ip}"
    echo "CDP Port:   ${CDP_PORT}"
    echo ""

    # Check if Chrome is running on Windows
    echo -n "Checking Windows Chrome... "
    # Try multiple paths to reach Chrome CDP

    local chrome_reachable=false
    local working_ip=""

    # Try 1: direct connection to Windows IP
    if curl -sf --connect-timeout 2 "http://${win_ip}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        chrome_reachable=true
        working_ip="$win_ip"
    fi

    # Try 2: Windows portproxy may route 0.0.0.0 -> 127.0.0.1
    # (if user ran netsh interface portproxy command)
    if ! $chrome_reachable; then
        # Check if there's already a local socat or something on CDP_PORT
        if curl -sf --connect-timeout 2 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
            chrome_reachable=true
            working_ip="127.0.0.1"
        fi
    fi

    if $chrome_reachable; then
        echo -e "${GREEN}OK${NC} (direct connection to ${working_ip})"
        echo ""
        echo -e "${GREEN}[OK]${NC} Chrome CDP is reachable at http://${working_ip}:${CDP_PORT}"
        echo "No bridge needed."
        return
    fi

    echo -e "${YELLOW}not directly reachable${NC}"
    echo ""

    # Need socat bridge
    ensure_socat
    stop_bridge_quiet

    # Kill anything occupying the port
    local old_pids=$(lsof -t -i ":${CDP_PORT}" 2>/dev/null || true)
    if [ -n "$old_pids" ]; then
        echo "Killing old processes on port ${CDP_PORT}..."
        echo "$old_pids" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi

    echo "Starting socat bridge: localhost:${CDP_PORT} -> ${win_ip}:${CDP_PORT}"

    socat TCP-LISTEN:${CDP_PORT},fork,reuseaddr TCP:${win_ip}:${CDP_PORT} &
    local pid=$!
    echo "$pid" > "$SOCAT_PID_FILE"

    # Wait and verify
    sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} socat failed to start"
        echo ""
        echo "Port ${CDP_PORT} may be in use. Try:"
        echo "  sudo lsof -i :${CDP_PORT}"
        echo "  kill \$(sudo lsof -t -i :${CDP_PORT})"
        exit 1
    fi

    # Verify connection
    if curl -sf --connect-timeout 3 "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Bridge running (PID: ${pid})"
        echo ""
        local browser=$(curl -sf "http://localhost:${CDP_PORT}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Browser','unknown'))" 2>/dev/null || echo "unknown")
        echo "Chrome: ${browser}"
        echo ""
        echo "Now run:"
        echo "  ./scripts/web-login-wsl.sh deepseek"
    else
        echo -e "${RED}[ERROR]${NC} Bridge started but Chrome not responding"
        echo ""
        echo "Make sure Chrome is running on Windows with debug mode:"
        echo "  1. Close ALL Chrome windows on Windows"
        echo "  2. Open Windows CMD and run:"
        echo '     start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=18892 --remote-debugging-address=0.0.0.0 --user-data-dir="%USERPROFILE%\.claw\chrome-profile" --no-first-run'
        echo ""
        echo "Also in PowerShell (admin), run once:"
        echo "  netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=18892 connectaddress=127.0.0.1 connectport=18892"
        stop_bridge_quiet
    fi
}

# --- Stop bridge ---
stop_bridge() {
    stop_bridge_quiet
    echo -e "${GREEN}[OK]${NC} Bridge stopped"
}

stop_bridge_quiet() {
    if [ -f "$SOCAT_PID_FILE" ]; then
        local pid=$(cat "$SOCAT_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$SOCAT_PID_FILE"
    fi
    # Also kill any lingering socat on our port
    local pids=$(lsof -t -i ":${CDP_PORT}" 2>/dev/null | grep -v "$$" || true)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs kill 2>/dev/null || true
    fi
}

# --- Status ---
show_status() {
    local win_ip=$(get_win_ip)
    echo "Windows IP: ${win_ip:-unknown}"
    echo "CDP Port:   ${CDP_PORT}"
    echo ""

    # Check bridge process
    if [ -f "$SOCAT_PID_FILE" ] && kill -0 "$(cat "$SOCAT_PID_FILE")" 2>/dev/null; then
        echo "Bridge:     running (PID: $(cat "$SOCAT_PID_FILE"))"
    else
        echo "Bridge:     not running"
    fi

    # Check Chrome reachable
    echo -n "Chrome:     "
    if curl -sf --connect-timeout 2 "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        local browser=$(curl -sf "http://localhost:${CDP_PORT}/json/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Browser','unknown'))" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}reachable${NC} (${browser})"
    elif curl -sf --connect-timeout 2 "http://${win_ip}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
        echo -e "${GREEN}reachable via ${win_ip}${NC} (no bridge needed)"
    else
        echo -e "${RED}not reachable${NC}"
    fi

    # Check credentials
    echo -n "Credentials: "
    local cred_file="${CLAW_CONFIG_HOME:-$HOME/.claw}/web-credentials.json"
    if [ -f "$cred_file" ]; then
        local providers=$(python3 -c "import json; d=json.load(open('$cred_file')); print(', '.join(d.get('credentials',{}).keys()) or 'none')" 2>/dev/null || echo "?")
        echo "${providers}"
    else
        echo "none"
    fi
}

# --- Main ---
ACTION="${1:-start}"

case "$ACTION" in
    start)
        echo "=== Claw Code: WSL-to-Windows CDP Bridge ==="
        echo ""
        start_bridge
        ;;
    stop)
        stop_bridge
        ;;
    status)
        echo "=== WSL Bridge Status ==="
        echo ""
        show_status
        ;;
    *)
        echo "Usage: $0 [start|stop|status]"
        exit 1
        ;;
esac

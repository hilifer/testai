#!/usr/bin/env bash
# One-click test runner for claw-code + web-bridge
# Usage: ./scripts/test.sh [OPTIONS]
#
# Options:
#   --all           Run all workspace tests (default)
#   --web-bridge    Run only web-bridge tests
#   --api           Run only api crate tests
#   --verbose       Show detailed test output
#   --release       Run tests in release mode

set -euo pipefail

cd "$(dirname "$0")/../rust"

TARGET="${1:---all}"
EXTRA_ARGS=""

# Parse flags
VERBOSE=false
RELEASE=false
for arg in "$@"; do
    case "$arg" in
        --verbose|-v)
            VERBOSE=true
            ;;
        --release)
            RELEASE=true
            ;;
    esac
done

if $VERBOSE; then
    EXTRA_ARGS="$EXTRA_ARGS -- --nocapture"
fi

if $RELEASE; then
    EXTRA_ARGS="--release $EXTRA_ARGS"
fi

echo "=== Claw Code Test Runner ==="
echo ""

case "$TARGET" in
    --web-bridge)
        echo "[1/1] Testing web-bridge crate..."
        cargo test -p web-bridge $EXTRA_ARGS
        ;;
    --api)
        echo "[1/1] Testing api crate..."
        cargo test -p api $EXTRA_ARGS
        ;;
    --all|*)
        echo "[1/3] Testing web-bridge crate..."
        cargo test -p web-bridge $EXTRA_ARGS
        echo ""
        echo "[2/3] Testing api crate..."
        cargo test -p api $EXTRA_ARGS
        echo ""
        echo "[3/3] Testing full workspace..."
        cargo test --workspace $EXTRA_ARGS
        ;;
esac

echo ""
echo "=== All tests passed ==="

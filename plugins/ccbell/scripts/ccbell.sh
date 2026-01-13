#!/usr/bin/env bash
# ccbell bootstrap - Downloads ccbell binary if missing, then execs it
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PLUGIN_DIR/bin/ccbell"
readonly VERSION="0.2.25"
readonly REPO="mpolatcan/ccbell"

# Check if download tool exists
check_download_tool() {
    command -v curl &>/dev/null || command -v wget &>/dev/null
}

# Download binary if missing
download_binary() {
    [[ -f "$BINARY" ]] && return 0

    check_download_tool || { echo "ccbell: Error: curl or wget required" >&2; exit 1; }

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m | sed 's/x86_64/amd64/')
    URL="https://github.com/${REPO}/releases/download/v${VERSION}/ccbell-${OS}-${ARCH}.tar.gz"

    echo "ccbell: Downloading..." >&2

    TMP=$(mktemp).tar.gz
    trap 'rm -f "$TMP"' EXIT

    mkdir -p "$PLUGIN_DIR/bin"

    if command -v curl &>/dev/null; then
        curl -fsSL "$URL" -o "$TMP"
    else
        wget -q "$URL" -O "$TMP"
    fi

    tar -xzf "$TMP" -C "$PLUGIN_DIR/bin"
    # Rename extracted binary from ccbell-darwin-amd64 to ccbell
    mv "$PLUGIN_DIR/bin/ccbell-${OS}-${ARCH}" "$BINARY"
    chmod +x "$BINARY"
}

download_binary
exec "$BINARY" "$@"

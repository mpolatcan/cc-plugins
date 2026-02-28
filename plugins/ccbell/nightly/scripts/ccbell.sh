#!/usr/bin/env bash
# ccbell-nightly bootstrap - Downloads pre-release ccbell binary if missing, then execs it
# This is the NIGHTLY variant - uses pre-release tags and separate config/log paths
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PLUGIN_DIR/bin/ccbell"
readonly VERSION="0.3.0-nightly.1"
readonly REPO="mpolatcan/ccbell"

# Nightly-specific paths (isolated from stable ccbell)
export CCBELL_CONFIG="$HOME/.claude/ccbell-nightly.config.json"
export CCBELL_LOG="$HOME/.claude/ccbell-nightly.log"
export CCBELL_PACKS_DIR="$HOME/.claude/ccbell-nightly/packs"

# Check if download tool exists
check_download_tool() {
    command -v curl &>/dev/null || command -v wget &>/dev/null
}

# Download binary if missing
download_binary() {
    [[ -f "$BINARY" ]] && return 0

    check_download_tool || { echo "ccbell-nightly: Error: curl or wget required" >&2; exit 1; }

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
    URL="https://github.com/${REPO}/releases/download/v${VERSION}/ccbell-${OS}-${ARCH}.tar.gz"

    echo "ccbell-nightly: Downloading pre-release v${VERSION}..." >&2

    TMP=$(mktemp).tar.gz
    trap 'rm -f "$TMP"' EXIT

    mkdir -p "$PLUGIN_DIR/bin"

    # Retry download up to 3 times with exponential backoff
    local max_attempts=3
    local attempt=1
    local delay=1

    while [[ $attempt -le $max_attempts ]]; do
        if command -v curl &>/dev/null; then
            if curl -fsSL "$URL" -o "$TMP" 2>/dev/null; then
                break
            fi
        else
            if wget -q "$URL" -O "$TMP" 2>/dev/null; then
                break
            fi
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            echo "ccbell-nightly: Download failed (attempt $attempt/$max_attempts), retrying in ${delay}s..." >&2
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done

    if [[ $attempt -gt $max_attempts ]]; then
        echo "ccbell-nightly: Error: Failed to download after $max_attempts attempts" >&2
        exit 1
    fi

    tar -xzf "$TMP" -C "$PLUGIN_DIR/bin"
    # Rename extracted binary from ccbell-darwin-amd64 to ccbell
    mv "$PLUGIN_DIR/bin/ccbell-${OS}-${ARCH}" "$BINARY"
    chmod +x "$BINARY"
}

download_binary
exec "$BINARY" "$@"

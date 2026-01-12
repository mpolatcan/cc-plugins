#!/usr/bin/env bash
# ccbell runner - Downloads ccbell binary if missing and runs it
set -euo pipefail

REPO="mpolatcan/ccbell"
BINARY_NAME="ccbell"
PLUGIN_VERSION="0.2.4"

# Detect platform
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "darwin" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "darwin" ;;  # Default to darwin
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)             echo "amd64" ;;  # Default to amd64
    esac
}

# Detect plugin root
get_plugin_root() {
    # Use CLAUDE_PLUGIN_ROOT if set (for hooks)
    if [[ -n "$CLAUDE_PLUGIN_ROOT" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return 0
    fi

    # Fallback: find latest version folder (for commands)
    local base_dir="$HOME/.claude/plugins/cache/cc-plugins/ccbell"
    if [[ -d "$base_dir" ]]; then
        local latest_version
        latest_version=$(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -1)
        if [[ -n "$latest_version" ]]; then
            echo "$base_dir/$latest_version"
            return 0
        fi
    fi

    echo ""
    return 1
}

# Main
main() {
    local event="${1:-stop}"

    # Map "notification" to "permission_prompt" for general notifications
    if [[ "$event" == "notification" ]]; then
        event="permission_prompt"
    fi

    local plugin_root
    plugin_root=$(get_plugin_root)

    if [[ -z "$plugin_root" ]]; then
        echo "ccbell: Could not determine plugin root" >&2
        exit 1
    fi

    local bin_dir="${plugin_root}/bin"
    local binary="${bin_dir}/${BINARY_NAME}"
    [[ "$(detect_os)" == "windows" ]] && binary="${binary}.exe"

    # Create bin directory if missing
    mkdir -p "$bin_dir"

    # Download binary if missing
    if [[ ! -f "$binary" ]]; then
        local os arch archive_ext archive_name url
        os=$(detect_os)
        arch=$(detect_arch)
        archive_ext="tar.gz"
        [[ "$os" == "windows" ]] && archive_ext="zip"
        archive_name="${BINARY_NAME}-${os}-${arch}.${archive_ext}"
        url="https://github.com/${REPO}/releases/latest/download/${archive_name}"

        echo "ccbell: Downloading binary..." >&2
        local tmp_file
        tmp_file=$(mktemp)

        # Cleanup on exit
        trap 'rm -f "$tmp_file"' EXIT

        # Download
        if command -v curl &>/dev/null; then
            curl -fsSL "$url" -o "$tmp_file" || { echo "ccbell: Download failed" >&2; exit 1; }
        elif command -v wget &>/dev/null; then
            wget -q "$url" -O "$tmp_file" || { echo "ccbell: Download failed" >&2; exit 1; }
        else
            echo "ccbell: Neither curl nor wget found" >&2
            exit 1
        fi

        # Extract
        if [[ "$archive_ext" == "tar.gz" ]]; then
            tar -xzf "$tmp_file" -C "$bin_dir" || { echo "ccbell: Extraction failed" >&2; exit 1; }
        else
            unzip -q "$tmp_file" -d "$bin_dir" || { echo "ccbell: Extraction failed" >&2; exit 1; }
        fi

        # Rename extracted binary to just 'ccbell'
        local extracted_binary="${bin_dir}/${BINARY_NAME}-${os}-${arch}"
        [[ "$os" == "windows" ]] && extracted_binary="${extracted_binary}.exe"
        if [[ -f "$extracted_binary" ]]; then
            mv "$extracted_binary" "$binary" || { echo "ccbell: Failed to rename binary" >&2; exit 1; }
        else
            echo "ccbell: Extracted binary not found at ${extracted_binary}" >&2
            ls -la "$bin_dir" >&2 || true
            exit 1
        fi

        chmod +x "$binary" || { echo "ccbell: Failed to set executable permission" >&2; exit 1; }
        echo "ccbell: Installed to ${binary}" >&2
    fi

    # Run ccbell
    exec "$binary" "$event"
}

main "$@"

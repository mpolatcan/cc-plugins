#!/usr/bin/env bash
# ccbell runner - Downloads ccbell binary if missing and runs it
set -euo pipefail

REPO="mpolatcan/ccbell"
BINARY_NAME="ccbell"

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

# Get CLAUDE_PLUGIN_ROOT - resolve symlinks to get real path
resolve_plugin_root() {
    local root="${CLAUDE_PLUGIN_ROOT:-}"
    if [[ -z "$root" ]]; then
        # Try common locations
        if [[ -d "$HOME/.claude/plugins/local/ccbell" ]]; then
            root="$HOME/.claude/plugins/local/ccbell"
        elif [[ -d "$HOME/.claude/plugins/local/cc-plugins/plugins/ccbell" ]]; then
            root="$HOME/.claude/plugins/local/cc-plugins/plugins/ccbell"
        fi
    fi
    echo "$root"
}

# Main
main() {
    local event="${1:-stop}"
    local plugin_root
    plugin_root=$(resolve_plugin_root)
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
            tar -xzf "$tmp_file" -C "$bin_dir"
        else
            unzip -q "$tmp_file" -d "$bin_dir"
        fi

        # Rename extracted binary to just 'ccbell'
        local extracted_binary="${bin_dir}/${BINARY_NAME}-${os}-${arch}"
        [[ "$os" == "windows" ]] && extracted_binary="${extracted_binary}.exe"
        if [[ -f "$extracted_binary" ]]; then
            mv "$extracted_binary" "$binary"
        fi

        chmod +x "$binary"
        echo "ccbell: Installed to ${binary}" >&2
    fi

    # Run ccbell
    exec "$binary" "$event"
}

main "$@"

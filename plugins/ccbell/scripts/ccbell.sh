#!/usr/bin/env bash
# ccbell runner - Downloads ccbell binary if missing and runs it
set -euo pipefail

REPO="mpolatcan/ccbell"
BINARY_NAME="ccbell"
PLUGIN_VERSION="0.2.9"

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
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
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

# Generate default config file
generate_config() {
    local config_file="$1"

    cat > "$config_file" << 'EOF'
{
  "enabled": true,
  "debug": false,
  "activeProfile": "default",
  "events": {
    "stop": {
      "enabled": true,
      "sound": "bundled:stop",
      "volume": 0.5,
      "cooldown": 0
    },
    "permission_prompt": {
      "enabled": true,
      "sound": "bundled:permission_prompt",
      "volume": 0.7,
      "cooldown": 0
    },
    "idle_prompt": {
      "enabled": true,
      "sound": "bundled:idle_prompt",
      "volume": 0.5,
      "cooldown": 0
    },
    "subagent": {
      "enabled": true,
      "sound": "bundled:subagent",
      "volume": 0.5,
      "cooldown": 0
    }
  }
}
EOF
}

# Ensure config file exists
ensure_config() {
    # Check for project-level config first
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && [[ -f "${CLAUDE_PROJECT_DIR}/.claude/ccbell.config.json" ]]; then
        return 0
    fi

    # Check global config
    local global_config="$HOME/.claude/ccbell.config.json"
    if [[ -f "$global_config" ]]; then
        return 0
    fi

    # Create global config if missing
    mkdir -p "$HOME/.claude"
    generate_config "$global_config"
    echo "ccbell: Created default config at ${global_config}" >&2
}

# Main
main() {
    local event="${1:-stop}"

    # Events are passed directly from hooks (permission_prompt, idle_prompt, stop, subagent)
    # No mapping needed - hooks use explicit matchers

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
        local os arch archive_ext archive_name url tmp_file
        os=$(detect_os)
        arch=$(detect_arch)
        archive_ext="tar.gz"
        suffix=".tar.gz"
        [[ "$os" == "windows" ]] && { archive_ext="zip"; suffix=".zip"; }
        archive_name="${BINARY_NAME}-${os}-${arch}.${archive_ext}"
        url="https://github.com/${REPO}/releases/latest/download/${archive_name}"

        echo "ccbell: Downloading binary..." >&2
        tmp_file=$(mktempXXXXXX)$suffix

        # Cleanup on exit
        trap 'rm -f "$tmp_file"' EXIT

        # Download
        if command -v curl &>/dev/null; then
            curl -fsSL "$url" -o "$tmp_file" || { echo "ccbell: Download failed" >&2; exit 1; }
        elif command -v wget &>/dev/null; then
            wget -q "$url" -O "$tmp_file" || { echo "ccbell: Download failed" >&2; exit 1; }
        else
            echo "ccbell: Error: Neither curl nor wget found" >&2
            exit 1
        fi

        # Extract
        if [[ "$archive_ext" == "tar.gz" ]]; then
            tar -xzf "$tmp_file" -C "$bin_dir" || { echo "ccbell: Error: Extraction failed" >&2; exit 1; }
        else
            unzip -q "$tmp_file" -d "$bin_dir" || { echo "ccbell: Error: Extraction failed" >&2; exit 1; }
        fi

        # Rename extracted binary to just 'ccbell'
        local extracted_binary="${bin_dir}/${BINARY_NAME}-${os}-${arch}"
        [[ "$os" == "windows" ]] && extracted_binary="${extracted_binary}.exe"
        if [[ -f "$extracted_binary" ]]; then
            mv "$extracted_binary" "$binary" || { echo "ccbell: Error: Failed to rename binary" >&2; exit 1; }
        else
            echo "ccbell: Error: Extracted binary not found at ${extracted_binary}" >&2
            ls -la "$bin_dir" >&2 || true
            exit 1
        fi

        chmod +x "$binary" || { echo "ccbell: Error: Failed to set executable permission" >&2; exit 1; }
        echo "ccbell: Downloaded to ${binary}" >&2
    fi

    # Ensure config file exists
    ensure_config

    # Run ccbell
    exec "$binary" "$event"
}

main "$@"

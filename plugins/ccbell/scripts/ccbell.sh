#!/usr/bin/env bash
# ccbell runner - Downloads ccbell binary if missing and runs it
# Supports macOS and all major Linux distributions with auto-dependency installation
set -euo pipefail

REPO="mpolatcan/ccbell"
BINARY_NAME="ccbell"
PLUGIN_VERSION="0.2.20"

# Detect platform
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "darwin" ;;
        Linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)             echo "amd64" ;;
    esac
}

# Audio player detection and installation for Linux
install_audio_player_linux() {
    local audio_player="$1"
    local install_cmd=""

    # Detect package manager and install
    if command -v apt-get &>/dev/null && command -v sudo &>/dev/null; then
        # Debian/Ubuntu
        install_cmd="sudo apt-get update && sudo apt-get install -y"
    elif command -v dnf &>/dev/null && command -v sudo &>/dev/null; then
        # Fedora/RHEL 8+
        install_cmd="sudo dnf install -y"
    elif command -v yum &>/dev/null && command -v sudo &>/dev/null; then
        # CentOS/RHEL 7
        install_cmd="sudo yum install -y"
    elif command -v pacman &>/dev/null && command -v sudo &>/dev/null; then
        # Arch Linux
        install_cmd="sudo pacman -S --noconfirm"
    elif command -v zypper &>/dev/null && command -v sudo &>/dev/null; then
        # openSUSE
        install_cmd="sudo zypper install -y"
    elif command -v apk &>/dev/null && command -v sudo &>/dev/null; then
        # Alpine
        install_cmd="sudo apk add --no-cache"
    elif command -v emerge &>/dev/null && command -v sudo &>/dev/null; then
        # Gentoo
        install_cmd="sudo emerge --ask"
    elif command -v nix-env &>/dev/null; then
        # NixOS
        install_cmd="nix-env -i"
    fi

    case "$audio_player" in
        "paplay")
            if [[ -n "$install_cmd" ]]; then
                echo "ccbell: Installing pulseaudio-utils ($install_cmd)..." >&2
                eval "$install_cmd" pulseaudio-utils 2>/dev/null || \
                eval "$install_cmd" libpulse-mainloop-glib 2>/dev/null || \
                eval "$install_cmd" pulseaudio 2>/dev/null || true
            fi
            ;;
        "aplay")
            if [[ -n "$install_cmd" ]]; then
                echo "ccbell: Installing alsa-utils ($install_cmd)..." >&2
                eval "$install_cmd" alsa-utils 2>/dev/null || true
            fi
            ;;
        "mpv")
            if [[ -n "$install_cmd" ]]; then
                echo "ccbell: installing mpv ($install_cmd)..." >&2
                eval "$install_cmd" mpv 2>/dev/null || true
            fi
            ;;
        "ffplay")
            if [[ -n "$install_cmd" ]]; then
                echo "ccbell: installing ffmpeg ($install_cmd)..." >&2
                eval "$install_cmd" ffmpeg 2>/dev/null || true
            fi
            ;;
    esac
}

# Find best available audio player
find_audio_player() {
    local os="$1"
    local player=""

    case "$os" in
        "darwin")
            if command -v afplay &>/dev/null; then
                player="afplay"
            fi
            ;;
        "linux")
            # Priority order: mpv (most reliable), paplay (PulseAudio), aplay (ALSA), ffplay
            for p in mpv paplay aplay ffplay; do
                if command -v "$p" &>/dev/null; then
                    player="$p"
                    break
                fi
            done

            # Auto-install if not found
            if [[ -z "$player" ]]; then
                echo "ccbell: No audio player found, attempting auto-install..." >&2

                # Try mpv first (most portable)
                if command -v apt-get &>/dev/null; then
                    if command -v sudo &>/dev/null; then
                        sudo apt-get update -qq && sudo apt-get install -y -qq mpv 2>/dev/null && player="mpv"
                    else
                        apt-get update -qq && apt-get install -y -qq mpv 2>/dev/null && player="mpv"
                    fi
                elif command -v dnf &>/dev/null; then
                    if command -v sudo &>/dev/null; then
                        sudo dnf install -y -q mpv 2>/dev/null && player="mpv"
                    else
                        dnf install -y -q mpv 2>/dev/null && player="mpv"
                    fi
                elif command -v pacman &>/dev/null; then
                    if command -v sudo &>/dev/null; then
                        sudo pacman -S --noconfirm mpv 2>/dev/null && player="mpv"
                    else
                        pacman -S --noconfirm mpv 2>/dev/null && player="mpv"
                    fi
                fi

                # If mpv install failed, try ffplay
                if [[ -z "$player" ]]; then
                    install_audio_player_linux "ffplay"
                    if command -v ffplay &>/dev/null; then
                        player="ffplay"
                    fi
                fi

                # If ffplay install failed, try paplay
                if [[ -z "$player" ]]; then
                    install_audio_player_linux "paplay"
                    if command -v paplay &>/dev/null; then
                        player="paplay"
                    fi
                fi

                # If paplay install failed, try aplay
                if [[ -z "$player" ]]; then
                    install_audio_player_linux "aplay"
                    if command -v aplay &>/dev/null; then
                        player="aplay"
                    fi
                fi
            fi
            ;;
    esac

    echo "$player"
}

# Verify audio player works
verify_audio_player() {
    local player="$1"
    local test_file="${2:-}"

    if [[ -n "$test_file" ]] && [[ -f "$test_file" ]]; then
        case "$player" in
            "afplay")
                afplay -v 0.1 "$test_file" 2>/dev/null
                ;;
            "mpv")
                mpv --no-video --volume=20 "$test_file" 2>/dev/null
                ;;
            "ffplay")
                ffplay -nodisp -autoexit -volume=20 "$test_file" 2>/dev/null
                ;;
            "paplay")
                paplay "$test_file" 2>/dev/null
                ;;
            "aplay")
                aplay -q "$test_file" 2>/dev/null
                ;;
            *)
                return 1
                ;;
        esac
    fi
}

get_plugin_root() {
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return 0
    fi

    local base_dir="$HOME/.claude/plugins/cache"
    if [[ -d "$base_dir" ]]; then
        local ccbell_path
        ccbell_path=$(find "$base_dir" -mindepth 2 -maxdepth 2 -type d -name "ccbell" 2>/dev/null | head -1)
        if [[ -n "$ccbell_path" ]]; then
            local latest_version
            latest_version=$(find "$ccbell_path" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -1)
            if [[ -n "$latest_version" ]]; then
                echo "$ccbell_path/$latest_version"
                return 0
            fi
        fi
    fi

    echo ""
    return 1
}

generate_config() {
    local config_file="$1"

    cat > "$config_file" << 'EOF'
{
  "enabled": true,
  "debug": false,
  "activeProfile": "default",
  "quietHours": {
    "start": null,
    "end": null
  },
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

ensure_config() {
    local global_config="$HOME/.claude/ccbell.config.json"
    if [[ -f "$global_config" ]]; then
        return 0
    fi

    mkdir -p "$HOME/.claude"
    generate_config "$global_config"
    echo "ccbell: Created default config at ${global_config}" >&2
}

# Main
main() {
    local event="${1:-stop}"

    local os arch plugin_root
    os=$(detect_os)
    arch=$(detect_arch)

    if [[ "$os" == "unknown" ]]; then
        echo "ccbell: Error: Unsupported operating system" >&2
        exit 1
    fi

    plugin_root=$(get_plugin_root)

    if [[ -z "$plugin_root" ]]; then
        echo "ccbell: Could not determine plugin root" >&2
        exit 1
    fi

    # Check audio player availability
    local audio_player
    audio_player=$(find_audio_player "$os")

    if [[ -z "$audio_player" ]]; then
        echo "ccbell: Error: No audio player found for $os" >&2
        case "$os" in
            "darwin")
                echo "ccbell: Suggestion: afplay is built into macOS" >&2
                ;;
            "linux")
                echo "ccbell: Suggestion: Install one of: mpv, ffmpeg (ffplay), pulseaudio-utils (paplay), or alsa-utils (aplay)" >&2
                ;;
        esac
        exit 1
    fi

    echo "ccbell: Using audio player: $audio_player" >&2

    local bin_dir="${plugin_root}/bin"
    local binary="${bin_dir}/${BINARY_NAME}"

    mkdir -p "$bin_dir"

    if [[ ! -f "$binary" ]]; then
        local archive_name url tmp_file
        archive_name="${BINARY_NAME}-${os}-${arch}.tar.gz"
        url="https://github.com/${REPO}/releases/download/v${PLUGIN_VERSION}/${archive_name}"

        echo "ccbell: Downloading binary..." >&2
        tmp_file=$(mktemp).tar.gz

        trap 'rm -f "$tmp_file"' EXIT

        if command -v curl &>/dev/null; then
            curl -fsSL "$url" -o "$tmp_file" || { echo "ccbell: Download failed" >&2; exit 1; }
        elif command -v wget &>/dev/null; then
            wget -q "$url" -O "$tmp_file" || { echo "ccbell: Download failed" >&2; exit 1; }
        else
            echo "ccbell: Error: Neither curl nor wget found" >&2
            exit 1
        fi

        tar -xzf "$tmp_file" -C "$bin_dir" || { echo "ccbell: Error: Extraction failed" >&2; exit 1; }

        local extracted_binary="${bin_dir}/${BINARY_NAME}-${os}-${arch}"
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

    ensure_config

    exec "$binary" "$event"
}

main "$@"

#!/usr/bin/env bash
# ccbell installer - Downloads the correct binary for your platform
# Usage: ./install.sh [version]
# Example: ./install.sh v3.0.0

set -euo pipefail

# === Configuration ===
REPO="mpolatcan/ccbell"
BINARY_NAME="ccbell"

# CLAUDE_PLUGIN_ROOT is set by Claude Code when running postinstall
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    echo "ERROR: CLAUDE_PLUGIN_ROOT not set." >&2
    echo "This script should be run by Claude Code during plugin installation." >&2
    echo "To install manually, use: /plugin marketplace add mpolatcan/cc-plugins && /plugin install ccbell" >&2
    exit 1
fi

INSTALL_DIR="${CLAUDE_PLUGIN_ROOT}/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# === Functions ===

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

# Validate version tag format (e.g., v1.0.0)
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "Invalid version format: $version. Expected format: vX.Y.Z"
    fi
}

# Detect OS
detect_os() {
    local os=""
    case "$(uname -s)" in
        Darwin*)  os="darwin" ;;
        Linux*)   os="linux" ;;
        MINGW*|MSYS*|CYGWIN*) os="windows" ;;
        *)        die "Unsupported operating system: $(uname -s)" ;;
    esac
    echo "$os"
}

# Detect architecture
detect_arch() {
    local arch=""
    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *)             die "Unsupported architecture: $(uname -m)" ;;
    esac
    echo "$arch"
}

# Get latest release version from GitHub
get_latest_version() {
    local url="https://api.github.com/repos/${REPO}/releases/latest"
    local response=""
    local version=""

    if command -v curl &>/dev/null; then
        response=$(curl -fsSL --max-time 30 "$url" 2>/dev/null)
    elif command -v wget &>/dev/null; then
        response=$(wget -qO- --timeout=30 "$url" 2>/dev/null)
    else
        die "Neither curl nor wget found. Please install one of them."
    fi

    # Check for "Not Found" response (no releases)
    if echo "$response" | grep -q '"message".*"Not Found"'; then
        die "No releases found for ${REPO}. The plugin maintainer needs to create a release first.

Please check: https://github.com/${REPO}/releases

If you're the maintainer, create a release with:
  git tag v1.0.0
  git push origin v1.0.0"
    fi

    version=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        die "Failed to parse version from GitHub API response"
    fi

    echo "$version"
}

# Download file
download() {
    local url="$1"
    local output="$2"

    info "Downloading from: $url"

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output" || return 1
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$output" || return 1
    else
        die "Neither curl nor wget found"
    fi

    return 0
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local checksums_file="$2"
    local filename="$3"

    # Check if checksum tool is available
    if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
        error "No SHA256 checksum tool available (sha256sum or shasum)"
        error "Cannot verify download integrity - aborting"
        return 1
    fi

    local expected=""
    expected=$(grep "$filename" "$checksums_file" | awk '{print $1}')

    if [[ -z "$expected" ]]; then
        error "Checksum not found for $filename in checksums file"
        error "Cannot verify download integrity - aborting"
        return 1
    fi

    local actual=""
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    else
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    fi

    if [[ "$expected" != "$actual" ]]; then
        error "Checksum mismatch!"
        error "Expected: $expected"
        error "Actual:   $actual"
        return 1
    fi

    success "Checksum verified"
    return 0
}

# === Main ===

main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║       ccbell Installer                 ║"
    echo "║   Sound notifications for Claude Code  ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # Get version
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        info "Fetching latest version..."
        version=$(get_latest_version)
    fi
    validate_version "$version"
    info "Version: $version"

    # Detect platform
    local os=$(detect_os)
    local arch=$(detect_arch)
    info "Platform: ${os}/${arch}"

    # Construct download URLs
    local archive_ext="tar.gz"
    [[ "$os" == "windows" ]] && archive_ext="zip"

    local binary_name="${BINARY_NAME}-${os}-${arch}"
    [[ "$os" == "windows" ]] && binary_name="${binary_name}.exe"

    local archive_name="${BINARY_NAME}-${os}-${arch}.${archive_ext}"
    local base_url="https://github.com/${REPO}/releases/download/${version}"
    local archive_url="${base_url}/${archive_name}"
    local checksums_url="${base_url}/checksums.txt"

    # Create temp directory
    local tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    # Download checksums
    info "Downloading checksums..."
    if ! download "$checksums_url" "$tmp_dir/checksums.txt"; then
        error "Failed to download checksums file"
        die "Checksum verification is required - cannot continue without verification"
    fi

    # Download archive
    info "Downloading ${archive_name}..."
    if ! download "$archive_url" "$tmp_dir/$archive_name"; then
        die "Failed to download binary. Check if version $version exists."
    fi

    # Verify checksum
    if [[ -f "$tmp_dir/checksums.txt" ]]; then
        if ! verify_checksum "$tmp_dir/$archive_name" "$tmp_dir/checksums.txt" "$archive_name"; then
            die "Checksum verification failed - aborting installation"
        fi
    fi

    # Extract
    info "Extracting..."
    cd "$tmp_dir"
    if [[ "$archive_ext" == "tar.gz" ]]; then
        tar -xzf "$archive_name"
    else
        unzip -q "$archive_name"
    fi

    # Install
    info "Installing to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    local final_name="$BINARY_NAME"
    [[ "$os" == "windows" ]] && final_name="${BINARY_NAME}.exe"

    mv "$binary_name" "$INSTALL_DIR/$final_name"
    chmod +x "$INSTALL_DIR/$final_name"

    # Verify installation
    if [[ -x "$INSTALL_DIR/$final_name" ]]; then
        success "Installed successfully!"
        echo ""
        info "Binary location: $INSTALL_DIR/$final_name"
        info "Version: $("$INSTALL_DIR/$final_name" --version 2>/dev/null || echo "unknown")"
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║       Installation Complete!           ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
    else
        die "Installation failed - binary not executable"
    fi
}

main "$@"

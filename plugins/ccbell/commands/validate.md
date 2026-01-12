---
description: Validate ccbell installation and configuration
allowed-tools: ["Read", "Bash"]
---

# Validate ccbell Installation

Run a comprehensive validation of the ccbell plugin installation and configuration.

## Validation Steps

### 1. Check Plugin Installation

```bash
# Set plugin root
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/local/ccbell}"
SCRIPTS_DIR="$PLUGIN_ROOT/scripts"
SOUNDS_DIR="$PLUGIN_ROOT/sounds"

echo "=== ccbell Validation ==="
echo ""

# Check if plugin root exists
if [ -d "$PLUGIN_ROOT" ]; then
    echo "Plugin directory: OK ($PLUGIN_ROOT)"
else
    echo "Plugin directory: MISSING ($PLUGIN_ROOT)"
    echo "Please ensure the plugin is installed."
    exit 1
fi

# Check if ccbell.sh script exists
if [ -x "$SCRIPTS_DIR/ccbell.sh" ]; then
    echo "ccbell.sh script: OK (executable)"
else
    echo "ccbell.sh script: ERROR (not found or not executable)"
    echo "Expected at: $SCRIPTS_DIR/ccbell.sh"
    exit 1
fi
```

### 2. Check Sound Files

```bash
echo ""
echo "=== Sound Files Check ==="

REQUIRED_SOUNDS=("stop" "permission_prompt" "idle_prompt" "subagent")
SOUNDS_OK=0
SOUNDS_MISSING=0

for sound in "${REQUIRED_SOUNDS[@]}"; do
    SOUND_FILE="$SOUNDS_DIR/${sound}.aiff"
    if [ -f "$SOUND_FILE" ]; then
        echo "Sound ($sound): OK"
        SOUNDS_OK=$((SOUNDS_OK + 1))
    else
        echo "Sound ($sound): MISSING"
        SOUNDS_MISSING=$((SOUNDS_MISSING + 1))
    fi
done

echo ""
echo "Sounds: $SOUNDS_OK/$((SOUNDS_OK + SOUNDS_MISSING)) found"

if [ $SOUNDS_MISSING -gt 0 ]; then
    echo "Warning: Some sound files are missing"
fi
```

### 3. Audio Player & Sound Playback

```bash
echo ""
echo "=== Audio Player Check ==="

# Detect platform and audio player
OS_TYPE="$(uname 2>/dev/null || echo 'unknown')"
AUDIO_PLAYER=""

case "$OS_TYPE" in
    Darwin)
        if command -v afplay &>/dev/null; then
            AUDIO_PLAYER="afplay"
        fi
        ;;
    Linux)
        for player in paplay aplay mpv ffplay; do
            if command -v "$player" &>/dev/null; then
                AUDIO_PLAYER="$player"
                break
            fi
        done
        ;;
esac

if [ -z "$AUDIO_PLAYER" ]; then
    echo "Audio player: ERROR (no suitable player found for $OS_TYPE)"
    echo "  macOS requires: afplay"
    echo "  Linux requires: paplay, aplay, mpv, or ffplay"
    exit 1
fi

echo "Audio player ($OS_TYPE): OK ($AUDIO_PLAYER)"

# Test each sound with audio player
echo ""
echo "=== Sound Playback (Direct) ==="
echo "Playing sounds with native audio player..."

for sound in "${REQUIRED_SOUNDS[@]}"; do
    SOUND_FILE="$SOUNDS_DIR/${sound}.aiff"
    if [ -f "$SOUND_FILE" ]; then
        echo -n "  Testing $sound... "

        case "$OS_TYPE" in
            Darwin)
                afplay -v 0.2 "$SOUND_FILE" 2>/dev/null && echo "OK" || echo "FAILED"
                sleep 0.3
                ;;
            Linux)
                case "$AUDIO_PLAYER" in
                    paplay)
                        paplay "$SOUND_FILE" 2>/dev/null && echo "OK" || echo "FAILED"
                        ;;
                    aplay)
                        aplay -q "$SOUND_FILE" && echo "OK" || echo "FAILED"
                        ;;
                    mpv)
                        mpv --no-video --volume=30 "$SOUND_FILE" 2>/dev/null && echo "OK" || echo "FAILED"
                        ;;
                    ffplay)
                        ffplay -nodisp -autoexit -volume=30 "$SOUND_FILE" 2>/dev/null && echo "OK" || echo "FAILED"
                        ;;
                esac
                sleep 0.3
                ;;
            *)
                echo "SKIPPED (unsupported platform)"
                ;;
        esac
    else
        echo "  Testing $sound... SKIPPED (file missing)"
    fi
done
```

### 4. Download/Verify Binary

```bash
echo ""
echo "=== Binary Check ==="

BIN_DIR="$PLUGIN_ROOT/bin"
BINARY="$BIN_DIR/ccbell"

# Try to download/ensure binary exists by running ccbell.sh with stop event
# This will download the binary if missing
echo "Checking/downloading ccbell binary..."

if "$SCRIPTS_DIR/ccbell.sh" stop 2>&1; then
    echo "Binary: OK (download/verified successfully)"

    # Get version info
    if [ -x "$BINARY" ]; then
        VERSION=$("$BINARY" --version 2>/dev/null || echo "unknown")
        echo "  Version: $VERSION"
    fi
else
    echo "Binary: ERROR (download/verification failed)"
    exit 1
fi
```

### 5. Play Sounds with ccbell Binary

```bash
echo ""
echo "=== Sound Playback (ccbell) ==="
echo "Playing sounds through ccbell binary..."

# Test each sound using ccbell
for sound in "${REQUIRED_SOUNDS[@]}"; do
    echo -n "  Testing $sound... "
    if "$BINARY" "$sound" 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
    fi
    sleep 0.3
done
```

### 6. Check Dependencies

```bash
echo ""
echo "=== Dependencies ==="

# Check for jq (optional)
if command -v jq &>/dev/null; then
    echo "jq: OK ($(jq --version))"
else
    echo "jq: NOT INSTALLED (optional - using fallback defaults)"
fi

echo ""
echo "=== Validation Complete ==="
```

## Summary

| Component | Status |
|-----------|--------|
| Plugin directory | OK/MISSING |
| ccbell.sh script | OK/ERROR |
| Sound files | OK/MISSING (count) |
| Audio player | OK/ERROR (player name) |
| Binary download | OK/ERROR |
| ccbell playback | OK/FAILED |

## Troubleshooting

If binary download fails:
- Check internet connectivity
- Verify GitHub releases are accessible: https://github.com/mpolatcan/ccbell/releases
- Ensure write permission to `$PLUGIN_ROOT/bin`

If sounds fail to play:
- Check audio player installation
- Verify sound files exist in `$PLUGIN_ROOT/sounds`
- Check system volume settings

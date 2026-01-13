---
name: ccbell:validate
description: Validate ccbell installation and configuration
allowed-tools: ["Read", "Bash"]
---

# Validate ccbell Installation

Run a comprehensive validation of the ccbell plugin installation and configuration.

## Validation Steps

### 1. Check Plugin Installation

Find latest installed plugin version.

```bash
echo "=== ccbell Validation ==="
echo ""

# Find ccbell plugin in any marketplace path
CCBELL_PATH=$(find "$HOME/.claude/plugins/cache" -mindepth 2 -maxdepth 2 -type d -name "ccbell" 2>/dev/null | head -1)

if [ -z "$CCBELL_PATH" ]; then
    echo "Plugin directory: MISSING"
    echo ""
    echo "ccbell is NOT installed. To install, run:"
    echo "  /plugin marketplace add mpolatcan/cc-plugins"
    echo "  /plugin install ccbell"
    echo ""
    echo "For manual validation, ensure ccbell exists at:"
    echo "  ~/.claude/plugins/cache/<marketplace>/ccbell/<version>/"
    exit 1
fi

LATEST_VERSION=$(find "$CCBELL_PATH" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -1)

if [ -z "$LATEST_VERSION" ]; then
    echo "Plugin directory: ERROR (no version found)"
    echo "Please reinstall: /plugin install ccbell"
    exit 1
fi

PLUGIN_ROOT="$CCBELL_PATH/$LATEST_VERSION"
echo "Plugin directory: OK ($PLUGIN_ROOT)"

# Check if ccbell.sh script exists
if [ -x "$PLUGIN_ROOT/scripts/ccbell.sh" ]; then
    echo "ccbell.sh script: OK (executable)"
else
    echo "ccbell.sh script: ERROR (not found or not executable)"
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
    SOUND_FILE="$PLUGIN_ROOT/sounds/${sound}.aiff"
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
    SOUND_FILE="$PLUGIN_ROOT/sounds/${sound}.aiff"
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

BINARY="$PLUGIN_ROOT/bin/ccbell"

echo "Checking/downloading ccbell binary..."

if "$PLUGIN_ROOT/scripts/ccbell.sh" stop 2>&1; then
    echo "Binary: OK (download/verified successfully)"

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

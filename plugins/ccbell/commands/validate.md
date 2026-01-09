---
description: Validate ccbell installation and configuration
allowed-tools: ["Read", "Bash"]
---

# Validate ccbell Installation

Run a comprehensive validation of the ccbell plugin installation and configuration.

## Validation Steps

### 1. Check Plugin Installation

```bash
# Check if plugin root exists
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/local/ccbell}"
if [ -d "$PLUGIN_ROOT" ]; then
    echo "Plugin directory: OK ($PLUGIN_ROOT)"
else
    echo "Plugin directory: MISSING ($PLUGIN_ROOT)"
fi

# Check if ccbell binary exists and is executable
if [ -x "$PLUGIN_ROOT/bin/ccbell" ]; then
    echo "Binary: OK (executable)"
    echo "  Version: $("$PLUGIN_ROOT/bin/ccbell" --version 2>/dev/null || echo "unknown")"
else
    echo "Binary: ERROR (not found or not executable at $PLUGIN_ROOT/bin/ccbell)"
fi

# Check bundled sounds
for sound in stop permission_prompt idle_prompt subagent; do
    if [ -f "$PLUGIN_ROOT/sounds/${sound}.aiff" ]; then
        echo "Bundled sound ($sound): OK"
    else
        echo "Bundled sound ($sound): MISSING"
    fi
done
```

### 2. Check Dependencies

```bash
# Check for jq (optional but recommended)
if command -v jq &>/dev/null; then
    echo "jq: OK ($(jq --version))"
else
    echo "jq: NOT INSTALLED (using fallback defaults)"
fi

# Check audio player
# Use POSIX-compatible shell checks
case "$(uname 2>/dev/null || echo 'unknown')" in
    Darwin)
        if command -v afplay &>/dev/null; then
            echo "Audio player (macOS): OK (afplay)"
        else
            echo "Audio player (macOS): ERROR (afplay not found)"
        fi
        ;;
    Linux)
        players=("paplay" "aplay" "mpv" "ffplay")
        found=""
        for player in "${players[@]}"; do
            if command -v "$player" &>/dev/null; then
                found="$player"
                break
            fi
        done
        if [ -n "$found" ]; then
            echo "Audio player (Linux): OK ($found)"
        else
            echo "Audio player (Linux): ERROR (no player found - install pulseaudio, alsa, mpv, or ffmpeg)"
        fi
        ;;
esac
```

### 3. Check Configuration

```bash
# Check for config files
PROJECT_CONFIG="${CLAUDE_PROJECT_DIR:-.}/.claude/ccbell.config.json"
GLOBAL_CONFIG="$HOME/.claude/ccbell.config.json"

if [ -f "$PROJECT_CONFIG" ]; then
    echo "Project config: FOUND ($PROJECT_CONFIG)"
    # Validate JSON
    if command -v jq &>/dev/null && jq empty "$PROJECT_CONFIG" 2>/dev/null; then
        echo "  JSON syntax: VALID"
    else
        echo "  JSON syntax: INVALID or jq not available"
    fi
elif [ -f "$GLOBAL_CONFIG" ]; then
    echo "Global config: FOUND ($GLOBAL_CONFIG)"
    if command -v jq &>/dev/null && jq empty "$GLOBAL_CONFIG" 2>/dev/null; then
        echo "  JSON syntax: VALID"
    else
        echo "  JSON syntax: INVALID or jq not available"
    fi
else
    echo "Config: NONE (using defaults)"
fi
```

### 4. Check Configuration Values

If a config file exists and jq is available, validate the configuration structure:

```bash
CONFIG_FILE=""
if [ -f "$PROJECT_CONFIG" ]; then
    CONFIG_FILE="$PROJECT_CONFIG"
elif [ -f "$GLOBAL_CONFIG" ]; then
    CONFIG_FILE="$GLOBAL_CONFIG"
fi

if [ -n "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    echo ""
    echo "Configuration Details:"
    echo "  Enabled: $(jq -r '.enabled // "true (default)"' "$CONFIG_FILE")"
    echo "  Debug mode: $(jq -r '.debug // "false (default)"' "$CONFIG_FILE")"
    echo "  Active profile: $(jq -r '.activeProfile // "default"' "$CONFIG_FILE")"

    # Check quiet hours
    quiet_start=$(jq -r '.quietHours.start // empty' "$CONFIG_FILE")
    quiet_end=$(jq -r '.quietHours.end // empty' "$CONFIG_FILE")
    if [ -n "$quiet_start" ] && [ -n "$quiet_end" ]; then
        echo "  Quiet hours: $quiet_start - $quiet_end"
    else
        echo "  Quiet hours: not configured"
    fi

    echo ""
    echo "Events:"
    for event in stop permission_prompt idle_prompt subagent; do
        enabled=$(jq -r ".events.${event}.enabled // \"true\"" "$CONFIG_FILE")
        sound=$(jq -r ".events.${event}.sound // \"bundled:${event}\"" "$CONFIG_FILE")
        volume=$(jq -r ".events.${event}.volume // \"0.5\"" "$CONFIG_FILE")
        cooldown=$(jq -r ".events.${event}.cooldown // \"0\"" "$CONFIG_FILE")
        echo "  $event: enabled=$enabled sound=$sound vol=$volume cooldown=${cooldown}s"
    done

    # Check profiles
    profiles=$(jq -r '.profiles | keys[]? // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$profiles" ]; then
        echo ""
        echo "Profiles:"
        echo "$profiles" | while read -r profile; do
            echo "  - $profile"
        done
    fi
fi
```

### 5. Test Sound Playback

```bash
# Quick sound test
echo ""
echo "Sound Test:"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/local/ccbell}"
TEST_SOUND="$PLUGIN_ROOT/sounds/stop.aiff"

if [ -f "$TEST_SOUND" ]; then
    case "$(uname 2>/dev/null || echo 'unknown')" in
        Darwin)
            afplay -v 0.3 "$TEST_SOUND" &
            echo "  Playing test sound (stop.aiff at 30% volume)"
            ;;
        Linux)
            if command -v paplay &>/dev/null; then
                paplay "$TEST_SOUND" &
                echo "  Playing test sound with paplay"
            else
                echo "  Skipped (no audio player)"
            fi
            ;;
        *)
            echo "  Skipped (unsupported platform)"
            ;;
    esac
else
    echo "  ERROR: Test sound file not found"
fi
```

### 6. Check Log File (if debug enabled)

```bash
LOG_FILE="$HOME/.claude/ccbell.log"
if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "Debug log exists: $LOG_FILE"
    echo "Last 5 entries:"
    tail -5 "$LOG_FILE" | sed 's/^/  /'
fi
```

## Output Summary

Present a summary table:

| Component | Status | Notes |
|-----------|--------|-------|
| Plugin directory | OK/MISSING | Path |
| ccbell binary | OK/ERROR | Version and executable check |
| Bundled sounds | OK/PARTIAL | Count found |
| jq dependency | OK/MISSING | Optional |
| Audio player | OK/ERROR | Player name |
| Config file | OK/DEFAULT | Path or default |
| JSON syntax | VALID/INVALID | If config exists |

If any critical issues are found, provide specific remediation steps.

---
name: ccbell-nightly:status
description: Show current ccbell-nightly configuration status
allowed-tools: ["Read", "Bash"]
---

# ccbell-nightly Status

Show current configuration and status.

## Instructions

### 1. Read Configuration

Check for config at:
- Global: `~/.claude/ccbell-nightly.config.json`

### 2. Display Status

If config exists, parse and display:

```
## ccbell-nightly Status

**Global Status:** Enabled/Disabled
**Config Location:** ~/.claude/ccbell-nightly.config.json
**Active Profile:** default
**Active Pack:** none
**Debug Mode:** Off

### Quiet Hours
Not configured / 22:00 - 07:00 (currently active/inactive)

### Event Configuration

| Event | Enabled | Sound | Volume | Cooldown |
|-------|---------|-------|--------|----------|
| Stop | Yes | bundled:stop | 0.5 | 0s |
| Permission Prompt | Yes | bundled:permission_prompt | 0.7 | 0s |
| Idle Prompt | Yes | bundled:idle_prompt | 0.5 | 0s |
| Subagent | Yes | bundled:subagent | 0.5 | 0s |

### Profiles Available
- default (active)
- focus
- work
- loud
- silent

### Sound Packs Installed
- minimal (v1.0.0)
- classic (v1.0.0)

### Quick Commands

- `/ccbell-nightly:enable` - Enable all notifications
- `/ccbell-nightly:disable` - Disable all notifications
- `/ccbell-nightly:configure` - Change sound settings
- `/ccbell-nightly:profile` - Switch profiles
- `/ccbell-nightly:packs` - Browse and install sound packs
- `/ccbell-nightly:test` - Test sounds
- `/ccbell-nightly:validate` - Run diagnostics
```

### 3. Check Quiet Hours Status

Determine if currently in quiet hours:

```bash
CONFIG_FILE="$HOME/.claude/ccbell-nightly.config.json"

quiet_start=$(jq -r '.quietHours.start // empty' "$CONFIG_FILE")
quiet_end=$(jq -r '.quietHours.end // empty' "$CONFIG_FILE")

if [ -n "$quiet_start" ] && [ -n "$quiet_end" ]; then
    current_time=$(date '+%H:%M')
    echo "Quiet hours: $quiet_start - $quiet_end"
    echo "Current time: $current_time"
fi
```

### 4. Show Installed Sound Packs

List installed sound packs and show active pack:

```bash
# Check active pack
ACTIVE_PACK=$(jq -r '.activePack // "none"' "$CONFIG_FILE")
echo "Active Pack: $ACTIVE_PACK"

# List installed packs
PACKS_DIR="$HOME/.claude/ccbell-nightly/packs"
if [ -d "$PACKS_DIR" ]; then
    echo "Installed Packs:"
    for pack_dir in "$PACKS_DIR"/*; do
        if [ -d "$pack_dir" ] && [ -f "$pack_dir/pack.json" ]; then
            pack_name=$(basename "$pack_dir")
            pack_version=$(jq -r '.version // "unknown"' "$pack_dir/pack.json" 2>/dev/null)
            echo "  - $pack_name (v$pack_version)"
        fi
    done
else
    echo "No sound packs installed"
fi
```

### 5. Show Debug Log (if debug enabled)

If debug mode is on, show last few log entries:

```bash
if [ -f "$HOME/.claude/ccbell-nightly.log" ]; then
    echo "Recent log entries:"
    tail -5 "$HOME/.claude/ccbell-nightly.log"
fi
```

### 6. If No Config

If no config file exists:

```
## ccbell-nightly Status

**Status:** Not configured

No configuration file found. ccbell-nightly will use default settings:
- All events enabled
- Bundled sounds for each event
- 50% volume
- No cooldowns
- No quiet hours

Run /ccbell-nightly:configure to set up your preferences.
Run /ccbell-nightly:enable to create a default config.
```

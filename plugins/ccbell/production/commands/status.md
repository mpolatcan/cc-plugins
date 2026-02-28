---
name: ccbell:status
description: Show current ccbell configuration status
allowed-tools: ["Read", "Bash"]
---

# ccbell Status

Show current configuration and status.

## Instructions

### 1. Read Configuration

Check for config at:
- Global: `~/.claude/ccbell.config.json`

### 2. Display Status

If config exists, parse and display:

```
## ccbell Status

**Global Status:** Enabled/Disabled
**Config Location:** ~/.claude/ccbell.config.json
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

- `/ccbell:enable` - Enable all notifications
- `/ccbell:disable` - Disable all notifications
- `/ccbell:configure` - Change sound settings
- `/ccbell:profile` - Switch profiles
- `/ccbell:packs` - Browse and install sound packs
- `/ccbell:test` - Test sounds
- `/ccbell:validate` - Run diagnostics
```

### 3. Check Quiet Hours Status

Determine if currently in quiet hours:

```bash
CONFIG_FILE="$HOME/.claude/ccbell.config.json"

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
PACKS_DIR="$HOME/.claude/ccbell/packs"
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
if [ -f "$HOME/.claude/ccbell.log" ]; then
    echo "Recent log entries:"
    tail -5 "$HOME/.claude/ccbell.log"
fi
```

### 6. If No Config

If no config file exists:

```
## ccbell Status

**Status:** Not configured

No configuration file found. ccbell will use default settings:
- All events enabled
- Bundled sounds for each event
- 50% volume
- No cooldowns
- No quiet hours

Run /ccbell:configure to set up your preferences.
Run /ccbell:enable to create a default config.
```

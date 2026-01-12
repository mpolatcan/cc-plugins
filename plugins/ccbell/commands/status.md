---
description: Show current ccbell configuration status
argument-hint: ""
allowed-tools: ["Read", "Bash"]
---

# ccbell Status

Show current configuration and status.

## Instructions

### 1. Read Configuration

Check for config at:
- Project: `.claude/ccbell.config.json`
- Global: `~/.claude/ccbell.config.json`

### 2. Display Status

If config exists, parse and display:

```
## ccbell Status

**Global Status:** Enabled/Disabled
**Config Location:** ~/.claude/ccbell.config.json
**Active Profile:** default
**Debug Mode:** Off

### Quiet Hours
Not configured / 22:00 - 07:00 (currently active/inactive)

### Event Configuration

| Event | Enabled | Sound | Volume | Cooldown |
|-------|---------|-------|--------|----------|
| Stop | Yes | bundled:stop | 0.5 | 5s |
| Permission Prompt | Yes | bundled:permission_prompt | 0.7 | 0s |
| Subagent | Yes | bundled:subagent | 0.5 | 5s |

### Profiles Available
- default (active)
- work
- focus
- silent
- loud

### Quick Commands

- `/ccbell:enable` - Enable all notifications
- `/ccbell:disable` - Disable all notifications
- `/ccbell:configure` - Change sound settings
- `/ccbell:profile` - Switch profiles
- `/ccbell:test` - Test sounds
- `/ccbell:validate` - Run diagnostics
```

### 3. Check Quiet Hours Status

Determine if currently in quiet hours:

```bash
CONFIG_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/ccbell.config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$HOME/.claude/ccbell.config.json"
fi

quiet_start=$(jq -r '.quietHours.start // empty' "$CONFIG_FILE")
quiet_end=$(jq -r '.quietHours.end // empty' "$CONFIG_FILE")

if [ -n "$quiet_start" ] && [ -n "$quiet_end" ]; then
    current_time=$(date '+%H:%M')
    echo "Quiet hours: $quiet_start - $quiet_end"
    echo "Current time: $current_time"
    # Determine if currently in quiet period
fi
```

### 4. Show Debug Log (if debug enabled)

If debug mode is on, show last few log entries:

```bash
if [ -f "$HOME/.claude/ccbell.log" ]; then
    echo "Recent log entries:"
    tail -5 "$HOME/.claude/ccbell.log"
fi
```

### 5. If No Config

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

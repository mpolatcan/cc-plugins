---
description: Test ccbell sound notifications
argument-hint: "[stop|permission_prompt|subagent|all]"
allowed-tools: ["Read", "Bash"]
---

# Test ccbell Sounds

Test sound notifications for Claude Code events.

## Arguments

$ARGUMENTS

- `stop` - Test the stop event sound
- `permission_prompt` - Test the permission prompt sound
- `subagent` - Test the subagent completion sound
- `all` or no argument - Test all enabled sounds


## Instructions

### 1. Test Sounds

ccbell.sh automatically detects the plugin root.

**For specific event:**
```bash
"$HOME/.claude/plugins/cache/cc-plugins/ccbell/${PLUGIN_VERSION}/scripts/ccbell.sh" <event_name>
```

**For all events:**
```bash
for event in stop permission_prompt subagent; do
  echo "Testing: $event"
  "$HOME/.claude/plugins/cache/cc-plugins/ccbell/${PLUGIN_VERSION}/scripts/ccbell.sh" "$event"
  sleep 1.5
done
```

### 2. Report Results

After testing, report which sounds played:

```
## ccbell Sound Test Results

**Active Profile:** default
**Quiet Hours:** Not active

| Event | Status | Sound | Notes |
|-------|--------|-------|-------|
| Stop | Played | bundled:stop | 0.5 volume |
| Permission Prompt | Played | bundled:permission_prompt | 0.7 volume |
| Subagent | Played | bundled:subagent | 0.5 volume |

All enabled sounds working correctly!

To change sounds, run /ccbell:configure
```

### 3. If Sounds Didn't Play

Check potential issues:

```bash
# Check if currently in quiet hours
CONFIG_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/ccbell.config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$HOME/.claude/ccbell.config.json"
fi

if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    quiet_start=$(jq -r '.quietHours.start // empty' "$CONFIG_FILE")
    quiet_end=$(jq -r '.quietHours.end // empty' "$CONFIG_FILE")
    if [ -n "$quiet_start" ]; then
        echo "Quiet hours configured: $quiet_start - $quiet_end"
        echo "Current time: $(date '+%H:%M')"
    fi
fi

# Check debug log
if [ -f "$HOME/.claude/ccbell.log" ]; then
    echo "Last 5 log entries:"
    tail -5 "$HOME/.claude/ccbell.log"
fi
```

### 4. Troubleshooting Tips

If sounds don't play:
1. **Quiet hours active?** Check if current time is in quiet period
2. **Cooldown active?** Recent notification may have triggered cooldown
3. **Event disabled?** Check if the specific event is enabled in config
4. **Plugin enabled?** Check `enabled: true` in config
5. **Audio working?** Test with platform-specific player (afplay on macOS, paplay/mpv on Linux, PowerShell on Windows)
6. **Enable debug mode:** Set `"debug": true` in config and check `~/.claude/ccbell.log`

### 5. Force Test (Bypass Checks)

To test sounds ignoring quiet hours and cooldowns, use ccbell.sh directly:

```bash
"$HOME/.claude/plugins/cache/cc-plugins/ccbell/${PLUGIN_VERSION}/scripts/ccbell.sh" stop
```

This confirms audio output is working independent of ccbell config.

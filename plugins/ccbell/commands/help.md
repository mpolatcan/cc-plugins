---
description: Show ccbell help and documentation
allowed-tools: ["Read"]
---

# ccbell Help

Show help and documentation for the ccbell plugin.

## Response

Provide the following information:

```
# ccbell - Sound Notifications for Claude Code

Play audio notifications when Claude Code events occur, so you can work in
other windows without constantly checking if Claude is done.

## Supported Events

- **Stop** - Plays when Claude finishes responding
- **Permission Prompt** - Plays when Claude needs your permission
- **Subagent** - Plays when a background agent completes

**Note:** Idle Prompt is not currently supported as a hook event in Claude Code.

## Commands

| Command | Description |
|---------|-------------|
| /ccbell:configure | Interactive setup for sounds, events, cooldowns, and quiet hours |
| /ccbell:test [event] | Test sounds (all or specific event) |
| /ccbell:enable | Enable all notifications |
| /ccbell:disable | Disable all notifications |
| /ccbell:status | Show current configuration |
| /ccbell:profile | Switch between sound profiles |
| /ccbell:validate | Run installation diagnostics |
| /ccbell:help | Show this help |

## Features

### Sound Profiles
Create and switch between different notification presets:
- **default** - Standard settings
- **focus** - Minimal interruptions
- **work** - Professional, subtle sounds
- **silent** - All notifications disabled
- **loud** - Maximum volume for all events

Use `/ccbell:profile` to switch profiles.

### Quiet Hours (Do Not Disturb)
Set time windows when notifications are suppressed:
- Configure in `/ccbell:configure`
- Supports overnight periods (e.g., 22:00 - 07:00)

### Cooldowns (Debounce)
Prevent notification spam with per-event cooldowns:
- Set minimum seconds between same event notifications
- Example: 5-second cooldown on stop events

### Debug Mode
Enable logging for troubleshooting:
- Logs written to `~/.claude/ccbell.log`
- Enable via `/ccbell:configure` or config file

## Sound Options

### Bundled Sounds
Pre-packaged sounds included with the plugin. These work consistently across all platforms.

Available: `bundled:stop`, `bundled:permission_prompt`, `bundled:subagent`

### Custom Sounds
Use your own audio files (MP3, WAV, AIFF, M4A).

Format: `custom:/path/to/your/sound.mp3`

## Configuration

Config is stored at:
- Project: `.claude/ccbell.config.json`
- Global: `~/.claude/ccbell.config.json`

Project config takes precedence over global config.

### Full Config Example

```json
{
  "enabled": true,
  "debug": false,
  "activeProfile": "default",
  "quietHours": {
    "start": "22:00",
    "end": "07:00"
  },
  "events": {
    "stop": {
      "enabled": true,
      "sound": "bundled:stop",
      "volume": 0.5,
      "cooldown": 5
    },
    "permission_prompt": {
      "enabled": true,
      "sound": "bundled:permission_prompt",
      "volume": 0.7,
      "cooldown": 0
    },
    "subagent": {
      "enabled": true,
      "sound": "bundled:subagent",
      "volume": 0.5,
      "cooldown": 5
    }
  },
  "profiles": {
    "work": {
      "events": {
        "stop": { "sound": "bundled:stop", "volume": 0.3 }
      }
    }
  }
}
```

## Cross-Platform Support

- **macOS:** Full support (uses afplay)
- **Linux:** Requires paplay, aplay, mpv, or ffplay
- **Windows:** Uses PowerShell Media.SoundPlayer
- **WSL:** Detected and handled as Linux

## Quick Start

1. Run `/ccbell:enable` to enable with defaults
2. Run `/ccbell:test` to verify sounds work
3. Run `/ccbell:configure` to customize

## Troubleshooting

**Sounds not playing?**
1. Check if currently in quiet hours
2. Check cooldown settings
3. Run `/ccbell:status` to verify config
4. Enable debug mode and check `~/.claude/ccbell.log`
5. Verify bundled sounds exist in `$CLAUDE_PLUGIN_ROOT/sounds/`

**Too many notifications?**
Configure cooldowns in `/ccbell:configure` to add delays between sounds.

## Installation

**Via Marketplace:**
/plugin marketplace add mpolatcan/cc-plugins
/plugin install ccbell

The installer automatically downloads the correct binary for your platform.

## Source Code

The ccbell binary is built from: https://github.com/mpolatcan/ccbell
```

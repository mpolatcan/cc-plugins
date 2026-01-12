# ccbell

Audio notifications for Claude Code events. Get notified when Claude finishes responding, needs permission, or is waiting for your input.

## Features

- **Multiple Events** - Stop, Permission Prompt, Idle Prompt, Subagent completion
- **Sound Profiles** - Switch between work, focus, silent, loud, and custom presets
- **Quiet Hours** - Do-not-disturb time windows
- **Cooldowns** - Debounce rapid notifications
- **Cross-Platform** - macOS, Linux, Windows support
- **Flexible Sounds** - Bundled sounds, custom audio files

## Installation

```
/plugin marketplace add mpolatcan/cc-plugins
/plugin install ccbell
```

## Quick Start

```
/ccbell:enable     # Enable notifications
/ccbell:test       # Test sounds
/ccbell:configure  # Customize settings
/ccbell:status     # Check current configuration
/ccbell:profile    # Switch sound profiles
```

## Commands

| Command | Description |
|---------|-------------|
| `/ccbell:configure` | Interactive setup for sounds, events, cooldowns |
| `/ccbell:test [event]` | Test sounds (all or specific event) |
| `/ccbell:enable` | Enable all notifications |
| `/ccbell:disable` | Disable all notifications |
| `/ccbell:status` | Show current configuration |
| `/ccbell:profile` | Switch between sound profiles |
| `/ccbell:validate` | Run installation diagnostics |
| `/ccbell:help` | Show help documentation |

## Supported Events

| Event | When it triggers |
|-------|-----------------|
| `stop` | Claude finishes responding |
| `permission_prompt` | Claude needs your permission |
| `idle_prompt` | Claude is waiting for input |
| `subagent` | Background agent completes |

## Sound Profiles

| Profile | Description |
|---------|-------------|
| `default` | Standard - all events enabled |
| `focus` | Minimal - only permission prompts |
| `work` | Professional - subtle sounds |
| `loud` | Maximum volume for all events |
| `silent` | All notifications disabled |

## Sound Options

### Bundled Sounds (Recommended)

Pre-packaged sounds included with the plugin: `bundled:stop`, `bundled:permission_prompt`, `bundled:idle_prompt`, `bundled:subagent`

### Custom Sounds

Use your own audio files (MP3, WAV, AIFF, M4A): `custom:/path/to/sound.mp3`

**Note:** For volume control on Linux, install mpv or ffplay. The player order is: paplay → aplay → mpv → ffplay. Only mpv and ffplay fully support volume adjustment. paplay and aplay will play at fixed volume.

## Configuration

Config files (project takes precedence over global):
- **Project:** `.claude/ccbell.config.json`
- **Global:** `~/.claude/ccbell.config.json`

### Example Configuration

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
    "idle_prompt": {
      "enabled": true,
      "sound": "bundled:idle_prompt",
      "volume": 0.5,
      "cooldown": 10
    },
    "subagent": {
      "enabled": true,
      "sound": "bundled:subagent",
      "volume": 0.5,
      "cooldown": 5
    }
  }
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | true | Global on/off |
| `debug` | boolean | false | Enable logging |
| `quietHours.start` | string | - | Start of quiet period (HH:MM) |
| `quietHours.end` | string | - | End of quiet period (HH:MM) |
| `events.<event>.enabled` | boolean | true | Enable event |
| `events.<event>.sound` | string | bundled | Sound specification |
| `events.<event>.volume` | number | 0.5 | Volume 0.0-1.0 |
| `events.<event>.cooldown` | number | 0 | Seconds between notifications |

## Platform Support

| Platform | Audio Backend | Status |
|----------|--------------|--------|
| macOS | `afplay` | Full support |
| Linux | `paplay`, `aplay`, `mpv`, `ffplay` | Requires one |
| Windows | PowerShell | Basic support |

## Troubleshooting

**Sounds not playing?**
1. Check quiet hours: `/ccbell:status`
2. Enable debug mode in config
3. Check `~/.claude/ccbell.log`

**Too many notifications?**
Configure cooldowns via `/ccbell:configure`

**Run diagnostics:**
```
/ccbell:validate
```

## Uninstallation

```
/plugin uninstall ccbell
```

## Source Code

The ccbell binary is built from: https://github.com/mpolatcan/ccbell

## License

MIT

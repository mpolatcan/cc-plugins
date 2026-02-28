# ccbell-nightly

Nightly/pre-release build of ccbell - audio notifications for Claude Code events. This version uses pre-release binaries and a separate configuration, allowing it to coexist with the stable `ccbell` plugin.

## Why ccbell-nightly?

- Test new features before they reach the stable release
- Isolated config/logs - won't affect your stable ccbell setup
- Uses pre-release binary tags from GitHub

## Differences from Stable (ccbell)

| | ccbell (stable) | ccbell-nightly |
|---|---|---|
| Binary source | Stable release tags | Pre-release tags |
| Config file | `~/.claude/ccbell.config.json` | `~/.claude/ccbell-nightly.config.json` |
| Log file | `~/.claude/ccbell.log` | `~/.claude/ccbell-nightly.log` |
| Packs directory | `~/.claude/ccbell/packs/` | `~/.claude/ccbell-nightly/packs/` |
| Command prefix | `/ccbell:` | `/ccbell-nightly:` |

## Features

- **Multiple Events** - Stop, Permission Prompt, Idle Prompt, Subagent completion
- **Sound Profiles** - Switch between default, focus, work, loud, silent, and custom presets
- **Quiet Hours** - Do-not-disturb time windows
- **Cooldowns** - Debounce rapid notifications
- **Cross-Platform** - macOS and Linux support
- **Sound Packs** - AI-generated themed sound packs via [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator)
- **Flexible Sounds** - Bundled sounds, sound packs, custom audio files

## Installation

```
/plugin marketplace add mpolatcan/cc-plugins
/plugin install ccbell-nightly
```

## Quick Start

```
/ccbell-nightly:enable     # Enable notifications
/ccbell-nightly:test       # Test sounds
/ccbell-nightly:configure  # Customize settings
/ccbell-nightly:status     # Check current configuration
/ccbell-nightly:profile    # Switch sound profiles
```

## Commands

| Command | Description |
|---------|-------------|
| `/ccbell-nightly:configure` | Interactive setup for sounds, events, cooldowns |
| `/ccbell-nightly:test [event]` | Test sounds (all or specific event) |
| `/ccbell-nightly:enable` | Enable all notifications |
| `/ccbell-nightly:disable` | Disable all notifications |
| `/ccbell-nightly:status` | Show current configuration |
| `/ccbell-nightly:profile` | Switch between sound profiles |
| `/ccbell-nightly:packs` | Browse, install, and manage sound packs |
| `/ccbell-nightly:validate` | Run installation diagnostics |
| `/ccbell-nightly:help` | Show help and documentation |

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
| `default` | Standard settings - all events enabled at medium volume |
| `focus` | Minimal interruptions - only permission prompts at low volume |
| `work` | Professional mode - subtle sounds for all events |
| `loud` | Maximum volume for all events |
| `silent` | All notifications disabled |

## Sound Options

### Bundled Sounds (Recommended)

Pre-packaged sounds included with the plugin: `bundled:stop`, `bundled:permission_prompt`, `bundled:idle_prompt`, `bundled:subagent`

### Sound Pack Sounds

Use sounds from installed packs: `pack:pack_id:sound_file` (e.g., `pack:minimal:stop.wav`)

### Custom Sounds

Use your own audio files (MP3, WAV, AIFF, M4A): `custom:/path/to/sound.mp3`

## Configuration

Config file: `~/.claude/ccbell-nightly.config.json`

### Example Configuration

```json
{
  "enabled": true,
  "debug": false,
  "activeProfile": "default",
  "activePack": null,
  "quietHours": {
    "start": "22:00",
    "end": "07:00"
  },
  "events": {
    "stop": {
      "enabled": true,
      "sound": "bundled:stop",
      "volume": 0.5,
      "cooldown": 0
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
      "cooldown": 0
    },
    "subagent": {
      "enabled": true,
      "sound": "bundled:subagent",
      "volume": 0.5,
      "cooldown": 0
    }
  }
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | true | Global on/off |
| `debug` | boolean | false | Enable logging |
| `activePack` | string | - | Active sound pack ID (e.g., "minimal") |
| `quietHours.start` | string | - | Start of quiet period (HH:MM) |
| `quietHours.end` | string | - | End of quiet period (HH:MM) |
| `events.<event>.enabled` | boolean | true | Enable event |
| `events.<event>.sound` | string | bundled | Sound specification |
| `events.<event>.volume` | number | 0.5 | Volume 0.0-1.0 |
| `events.<event>.cooldown` | number | 0 | Seconds between notifications |

## Platform Support

| Platform | Architecture | Audio Backend | Status |
|----------|--------------|--------------|--------|
| macOS | x86_64 (Intel) | `afplay` | Full support |
| macOS | arm64 (Apple Silicon) | `afplay` | Full support |
| Linux | x86_64 (amd64) | `mpv`, `paplay`, `aplay`, `ffplay` | Requires one |
| Linux | aarch64 (ARM64) | `mpv`, `paplay`, `aplay`, `ffplay` | Requires one |

### Audio Player Support

| Player | macOS | Linux | Volume Control |
|--------|-------|-------|----------------|
| `afplay` | Built-in | - | Fixed |
| `mpv` | Supported | Supported | Adjustable |
| `paplay` | - | Supported | Fixed |
| `aplay` | - | Supported | Fixed |
| `ffplay` | Supported | Supported | Adjustable |

**Note:** For Linux, install `mpv` (recommended) for best results with volume control:
- Debian/Ubuntu: `sudo apt install mpv`
- Fedora: `sudo dnf install mpv`
- Arch: `sudo pacman -S mpv`
- macOS (Homebrew): `brew install mpv`

## Troubleshooting

**Sounds not playing?**
1. Check quiet hours: `/ccbell-nightly:status`
2. Enable debug mode in config
3. Check `~/.claude/ccbell-nightly.log`

**Run diagnostics:**
```
/ccbell-nightly:validate
```

## Uninstallation

```
/plugin uninstall ccbell-nightly
```

## Source Code

The ccbell binary is built from: https://github.com/mpolatcan/ccbell

## License

MIT

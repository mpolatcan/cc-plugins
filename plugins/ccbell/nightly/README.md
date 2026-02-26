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
- **Flexible Sounds** - Bundled sounds, custom audio files

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
| `/ccbell-nightly:validate` | Run installation diagnostics |
| `/ccbell-nightly:help` | Show help and documentation |

## Supported Events

| Event | When it triggers |
|-------|-----------------|
| `stop` | Claude finishes responding |
| `permission_prompt` | Claude needs your permission |
| `idle_prompt` | Claude is waiting for input |
| `subagent` | Background agent completes |

## Configuration

Config file: `~/.claude/ccbell-nightly.config.json`

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

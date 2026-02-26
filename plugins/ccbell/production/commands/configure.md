---
name: ccbell:configure
description: Configure ccbell sound notifications for different events
allowed-tools: ["Read", "Write", "AskUserQuestion", "Bash"]
---

# Configure ccbell Sound Notifications

Help the user configure sound notifications for Claude Code events.

## Available Sounds

ccbell uses bundled sounds by default for consistent cross-platform support:

- `bundled:stop` - Claude finished responding
- `bundled:permission_prompt` - Claude needs your permission
- `bundled:idle_prompt` - Claude is waiting for input
- `bundled:subagent` - Background agent completed

You can also use custom sounds:

- `custom:/path/to/your/sound.mp3` - Absolute path to audio file

## Configuration Steps

### 1. Ask User for Event Selection

Use AskUserQuestion to ask which events should trigger sounds:

```json
{
  "questions": [
    {
      "question": "Which events should trigger sound notifications?",
      "header": "Events",
      "multiSelect": true,
      "options": [
        {"label": "Stop (Claude finishes)", "description": "Play sound when Claude completes responding"},
        {"label": "Permission Prompt", "description": "Play sound when Claude needs permission"},
        {"label": "Idle Prompt", "description": "Play sound when Claude is waiting for input"},
        {"label": "Subagent Complete", "description": "Play sound when a background agent finishes"}
      ]
    }
  ]
}
```

### 2. For Each Selected Event, Ask Sound Choice

For each enabled event, ask the user to choose a sound:

```json
{
  "questions": [
    {
      "question": "Choose sound for the Stop event:",
      "header": "Stop sound",
      "options": [
        {"label": "Stop (bundled)", "description": "Default stop sound - bundled:stop"},
        {"label": "Custom sound", "description": "Use a custom audio file"}
      ]
    }
  ]
}
```

### 3. Ask for Volume

```json
{
  "questions": [
    {
      "question": "What volume level? (0.0 to 1.0)",
      "header": "Volume",
      "options": [
        {"label": "Low (0.3)", "description": "Quiet notifications"},
        {"label": "Medium (0.5)", "description": "Balanced volume"},
        {"label": "High (0.7)", "description": "Louder notifications"},
        {"label": "Full (1.0)", "description": "Maximum volume"}
      ]
    }
  ]
}
```

### 4. Ask About Cooldown (Optional)

```json
{
  "questions": [
    {
      "question": "Set a cooldown period between notifications?",
      "header": "Cooldown",
      "options": [
        {"label": "No cooldown", "description": "Play every notification immediately"},
        {"label": "5 seconds", "description": "Minimum 5 seconds between same event sounds"},
        {"label": "15 seconds", "description": "Minimum 15 seconds between same event sounds"},
        {"label": "30 seconds", "description": "Minimum 30 seconds between same event sounds"}
      ]
    }
  ]
}
```

### 5. Ask About Quiet Hours (Optional)

```json
{
  "questions": [
    {
      "question": "Would you like to set quiet hours (do not disturb)?",
      "header": "Quiet Hours",
      "options": [
        {"label": "No quiet hours", "description": "Notifications play anytime"},
        {"label": "Night (22:00-07:00)", "description": "Suppress sounds overnight"},
        {"label": "Evening (18:00-09:00)", "description": "Suppress sounds outside work hours"},
        {"label": "Custom", "description": "Set custom quiet hours"}
      ]
    }
  ]
}
```

If custom is selected, ask for start and end times in HH:MM format.

### 6. Ask About Debug Mode (Optional)

```json
{
  "questions": [
    {
      "question": "Enable debug logging?",
      "header": "Debug",
      "options": [
        {"label": "No (Recommended)", "description": "Normal operation, no logging"},
        {"label": "Yes", "description": "Log all events to ~/.claude/ccbell.log for troubleshooting"}
      ]
    }
  ]
}
```

### 7. Write Configuration

Create the configuration file at `~/.claude/ccbell.config.json`:

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

### 8. Confirm Configuration

After writing the config, confirm to the user and offer to test the sounds with `/ccbell:test`.

## Sound Specification Formats

- `bundled:stop`, `bundled:permission_prompt`, `bundled:idle_prompt`, `bundled:subagent` - Bundled sounds (recommended)
- `custom:/path/to/sound.mp3` - Custom audio file (absolute path required)

## Configuration Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | true | Global on/off switch |
| `debug` | boolean | false | Enable debug logging |
| `activeProfile` | string | "default" | Active sound profile |
| `quietHours.start` | string | - | Start of quiet period (HH:MM) |
| `quietHours.end` | string | - | End of quiet period (HH:MM) |
| `events.<event>.enabled` | boolean | true | Enable this event |
| `events.<event>.sound` | string | bundled | Sound specification |
| `events.<event>.volume` | number | 0.5 | Volume 0.0-1.0 |
| `events.<event>.cooldown` | number | 0 | Seconds between notifications |

## Quick Presets

You can also suggest these quick setup options:

- **Minimal**: Only permission prompts, low volume
- **Standard**: All events, medium volume
- **Productive**: All events with cooldowns, quiet hours set
- **Focus**: Disabled during quiet hours, permission prompts only

Use `/ccbell:profile` to switch between saved profiles.

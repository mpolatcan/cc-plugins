---
name: ccbell:profile
description: Switch between ccbell sound profiles
argument-hint: "[default|focus|work|loud|silent]"
allowed-tools: ["Read", "Write", "AskUserQuestion", "Bash"]
---

# Switch ccbell Profile

Manage and switch between sound notification profiles.

## Available Preset Profiles

When configuring profiles, offer these presets:

| Profile | Description |
|---------|-------------|
| **default** | Standard settings - all events enabled at medium volume |
| **focus** | Minimal interruptions - only permission prompts at low volume |
| **work** | Professional mode - subtle sounds for all events |
| **loud** | Maximum volume for all events |
| **silent** | All notifications disabled |

## Profile Command Workflow

### 1. Check Current Profile

First, read the config and display the current active profile:

```bash
GLOBAL_CONFIG="$HOME/.claude/ccbell.config.json"

if [ -f "$GLOBAL_CONFIG" ]; then
    ACTIVE_CONFIG="$GLOBAL_CONFIG"
else
    echo "No config found, using defaults"
    exit 0
fi

if command -v jq &>/dev/null; then
    current=$(jq -r '.activeProfile // "default"' "$ACTIVE_CONFIG")
    echo "Current profile: $current"

    # List available profiles
    profiles=$(jq -r '.profiles | keys[]? // empty' "$ACTIVE_CONFIG" 2>/dev/null)
    if [ -n "$profiles" ]; then
        echo "Available custom profiles:"
        echo "$profiles" | sed 's/^/  - /'
    fi
fi
```

### 2. Ask User for Profile Selection

Use AskUserQuestion to let user select a profile:

```json
{
  "questions": [
    {
      "question": "Which profile would you like to activate?",
      "header": "Profile",
      "options": [
        {"label": "default", "description": "Standard settings - all events enabled"},
        {"label": "focus", "description": "Minimal - only permission prompts"},
        {"label": "work", "description": "Professional - subtle notifications"},
        {"label": "loud", "description": "Maximum volume for all events"},
        {"label": "silent", "description": "All notifications disabled"}
      ]
    }
  ]
}
```

### 3. Apply Profile

Based on user selection, update the config:

**For preset profiles**, use these configurations:

#### default
```json
{
  "activeProfile": "default"
}
```
(Uses standard event settings)

#### focus
Create profile in config if not exists, then activate:
```json
{
  "activeProfile": "focus",
  "profiles": {
    "focus": {
      "events": {
        "stop": { "enabled": false },
        "permission_prompt": { "enabled": true, "volume": 0.3 },
        "idle_prompt": { "enabled": false },
        "subagent": { "enabled": false }
      }
    }
  }
}
```

#### work
```json
{
  "activeProfile": "work",
  "profiles": {
    "work": {
      "events": {
        "stop": { "enabled": true, "sound": "bundled:stop", "volume": 0.3 },
        "permission_prompt": { "enabled": true, "sound": "bundled:permission_prompt", "volume": 0.4 },
        "idle_prompt": { "enabled": true, "sound": "bundled:idle_prompt", "volume": 0.2 },
        "subagent": { "enabled": true, "sound": "bundled:subagent", "volume": 0.2 }
      }
    }
  }
}
```

#### loud
```json
{
  "activeProfile": "loud",
  "profiles": {
    "loud": {
      "events": {
        "stop": { "enabled": true, "sound": "bundled:stop", "volume": 1.0 },
        "permission_prompt": { "enabled": true, "sound": "bundled:permission_prompt", "volume": 1.0 },
        "idle_prompt": { "enabled": true, "sound": "bundled:idle_prompt", "volume": 1.0 },
        "subagent": { "enabled": true, "sound": "bundled:subagent", "volume": 1.0 }
      }
    }
  }
}
```

#### silent
```json
{
  "activeProfile": "silent",
  "profiles": {
    "silent": {
      "events": {
        "stop": { "enabled": false },
        "permission_prompt": { "enabled": false },
        "idle_prompt": { "enabled": false },
        "subagent": { "enabled": false }
      }
    }
  }
}
```

### 4. Write the Updated Config

Use the Write tool to update the config file. Merge the new profile settings with existing config.

Example of reading, modifying, and writing config:

```bash
if command -v jq &>/dev/null; then
    existing=$(cat "$ACTIVE_CONFIG")
fi
```

### 5. Confirm Profile Change

After updating, confirm to the user:

```
Profile changed to: [profile_name]

Settings active:
- Stop: enabled/disabled (sound, volume)
- Permission prompt: enabled/disabled (sound, volume)
- Idle prompt: enabled/disabled (sound, volume)
- Subagent: enabled/disabled (sound, volume)

Use /ccbell:test to hear your new notification sounds.
```

## Custom Profile Creation

If user selects "Other" or wants to create a custom profile, guide them through:

1. Ask for profile name
2. For each event, ask if enabled
3. For enabled events, ask for sound and volume
4. Save as new profile in config

## Profile Configuration Structure

```json
{
  "enabled": true,
  "activeProfile": "work",
  "events": {
    "stop": { "enabled": true, "sound": "bundled:stop", "volume": 0.5 },
    ...
  },
  "profiles": {
    "work": {
      "events": {
        "stop": { "enabled": true, "sound": "bundled:stop", "volume": 0.3 },
        ...
      }
    },
    "focus": {
      "events": {
        "stop": { "enabled": false },
        ...
      }
    }
  }
}
```

When a profile is active:
- Profile-specific event settings override default event settings
- Settings not specified in profile fall back to default events
- Global settings (enabled, quietHours) still apply

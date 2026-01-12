---
description: Disable ccbell sound notifications
allowed-tools: ["Read", "Write", "Bash"]
---

# Disable ccbell

Disable ccbell sound notifications.

## Instructions

### 1. Find Configuration File

Check for config at:
- Project: `.claude/ccbell.config.json`
- Global: `~/.claude/ccbell.config.json`

### 2. Update Configuration

Read the existing config and set `enabled: false`.

If no config exists, create one with `enabled: false`:

```json
{
  "enabled": false,
  "debug": false,
  "activeProfile": "default",
  "events": {
    "stop": { "enabled": false, "sound": "bundled:stop", "volume": 0.5, "cooldown": 0 },
    "permission_prompt": { "enabled": false, "sound": "bundled:permission_prompt", "volume": 0.7, "cooldown": 0 },
    "idle_prompt": { "enabled": false, "sound": "bundled:idle_prompt", "volume": 0.5, "cooldown": 0 },
    "subagent": { "enabled": false, "sound": "bundled:subagent", "volume": 0.5, "cooldown": 0 }
  }
}
```

### 3. Write Configuration

Write the updated config.

### 4. Confirm

Tell the user:
```
ccbell sound notifications disabled.

No sounds will play until you run /ccbell:enable.
Your sound preferences have been preserved.
```

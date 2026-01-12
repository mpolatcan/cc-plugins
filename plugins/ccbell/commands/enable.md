---
name: ccbell:enable
description: Enable ccbell sound notifications
allowed-tools: ["Read", "Write", "Bash"]
---

# Enable ccbell

Enable ccbell sound notifications globally.

## Instructions

### 1. Find Configuration File

Check for config at:
- Project: `.claude/ccbell.config.json`
- Global: `~/.claude/ccbell.config.json`

### 2. Update or Create Configuration

If config exists, read it and set `enabled: true`.

If no config exists, create a default one:

```json
{
  "enabled": true,
  "debug": false,
  "activeProfile": "default",
  "quietHours": null,
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

### 3. Write Configuration

Write the updated config to `~/.claude/ccbell.config.json`.

### 4. Confirm

Tell the user:
```
ccbell sound notifications enabled!

Sounds will play for:
- Stop (Claude finishes responding)
- Permission Prompt (needs approval)
- Idle Prompt (waiting for input)
- Subagent (background agent completes)

Run /ccbell:test to verify sounds work.
Run /ccbell:configure to customize sounds.
```

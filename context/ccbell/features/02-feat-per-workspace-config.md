# Feature: Per-Workspace Configuration

Different notification settings per project/repo using local config files.

## Summary

Allow ccbell to read project-specific config from `.claude-ccbell.json` in the workspace root. Enables context-aware notifications (louder for production, subtle for dev).

## Technical Feasibility

### Config File Discovery

```
/project/
├── .claude-ccbell.json    # Local workspace config
└── .claude/
    └── ccbell.config.json # Global user config
```

```go
func FindConfig() (*Config, error) {
    // 1. Check CWD for local config
    localPath := ".claude-ccbell.json"
    if _, err := os.Stat(localPath); err == nil {
        return LoadConfig(localPath)
    }

    // 2. Check .claude/ in CWD
    localPath = ".claude/ccbell.json"
    if _, err := os.Stat(localPath); err == nil {
        return LoadConfig(localPath)
    }

    // 3. Fallback to global config
    return LoadConfig(globalPath)
}
```

### Config Merging

```go
func MergeConfigs(global, local *Config) *Config {
    merged := *global // Copy global

    // Override with local values
    if local.Enabled != nil {
        merged.Enabled = local.Enabled
    }
    if local.Profile != "" {
        merged.Profile = local.Profile
    }
    if local.Volume != nil {
        merged.Volume = local.Volume
    }

    // Merge events
    for event, localEvent := range local.Events {
        if merged.Events == nil {
            merged.Events = make(map[string]EventConfig)
        }
        if existing, ok := merged.Events[event]; ok {
            // Merge existing with local overrides
            merged.Events[event] = mergeEventConfig(existing, localEvent)
        } else {
            merged.Events[event] = localEvent
        }
    }

    return &merged
}
```

## Commands

```bash
# Generate local config template
/ccbell:config init --local

# Show resolved config (global + local)
/ccbell:config show --resolved

# Edit local config
/ccbell:config edit --local
```

## Example Local Config

```json
{
  "inherit": true,
  "profile": "work",
  "volume": 0.3,
  "quiet_hours": {
    "enabled": true,
    "start": "18:00",
    "end": "09:00"
  },
  "events": {
    "stop": {
      "enabled": true,
      "volume": 0.2
    }
  }
}
```

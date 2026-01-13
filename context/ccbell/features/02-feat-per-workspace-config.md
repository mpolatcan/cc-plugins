# Feature: Per-Workspace Configuration

Different notification settings per project/repo using local config files.

## Summary

Allow ccbell to read project-specific config from `.claude-ccbell.json` in the workspace root. Enables context-aware notifications (louder for production, subtle for dev).

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current Configuration Analysis

The current config loading (`internal/config/config.go:81-102`) only reads from:
- `~/.claude/ccbell.config.json` (global user config)

**Key Finding**: Adding local config support requires modifying the `Load()` function to search for local configs and merge with global config.

### Config File Discovery

```
/project/
├── .claude-ccbell.json    # Local workspace config (CWD)
└── .claude/
    └── ccbell.config.json # Global user config
```

### Implementation Strategy

```go
func LoadWithLocal(homeDir, localPath string) (*Config, string, error) {
    // 1. Load global config
    globalCfg, globalPath, err := Load(homeDir)
    if err != nil {
        return nil, "", err
    }

    // 2. Check for local config
    if localPath != "" {
        if data, err := os.ReadFile(localPath); err == nil {
            localCfg := &Config{}
            if err := json.Unmarshal(data, localCfg); err == nil {
                // 3. Merge configs
                return mergeConfigs(globalCfg, localCfg), globalPath, nil
            }
        }
    }

    return globalCfg, globalPath, nil
}
```

### Merging Strategy

From `internal/config/config.go:206-220`, the merge pattern already exists:
```go
func mergeEvent(dst, src *Event) {
    if src.Enabled != nil {
        dst.Enabled = src.Enabled
    }
    if src.Sound != "" {
        dst.Sound = src.Sound
    }
    // ... etc
}
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

---

## Feasibility Research

### Audio Player Compatibility

No changes needed to the audio player. This feature only modifies config loading and merging logic.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Works with current audio player |
| Linux | ✅ Supported | Works with current audio player |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Environment Variables

The current implementation uses `CLAUDE_PLUGIN_ROOT` environment variable. We can use a similar approach for local config:

```go
// In main.go, add:
localConfigPath := os.Getenv("CCBELL_LOCAL_CONFIG")
if localConfigPath == "" {
    // Check CWD for .claude-ccbell.json
    if _, err := os.Stat(".claude-ccbell.json"); err == nil {
        localConfigPath = ".claude-ccbell.json"
    }
}
```

### Validation Changes

Add local config validation that inherits from global config validation.

---

## References

- [Current config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [Config merge pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L206-L220)

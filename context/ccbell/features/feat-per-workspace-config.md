# Feature: Per-Workspace Configuration 📂

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Allow ccbell to read project-specific config from `.claude-ccbell.json` in the workspace root. Enables context-aware notifications (louder for production, subtle for dev).

## Motivation

- Different projects need different notification strategies
- Production environments may need louder alerts
- Personal projects might prefer subtle notifications
- Team configurations can be committed to repos

---

## Benefit

- **Context-aware behavior**: Notifications adapt to the project context
- **Team consistency**: Shared configs ensure everyone hears the same alerts
- **Workflow optimization**: Louder for production, subtle for exploration
- **No global config changes**: Switch between project configs seamlessly

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

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### Research Sources

- [Go filepath package](https://pkg.go.dev/path/filepath) - For path resolution
- [os.Stat documentation](https://pkg.go.dev/os#Stat) - For config file detection

### ccbell Implementation Research

- [Current config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Base implementation to extend
- [Config merge pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L206-L220) - Existing merge logic
- [Environment variable usage](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Uses `CLAUDE_PLUGIN_ROOT` pattern

---

[Back to Feature Index](index.md)

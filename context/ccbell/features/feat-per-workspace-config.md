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

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Category** | Config Management |

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Add `LoadWithWorkspace(cwd string)` for local config merging |
| **Core Logic** | Add | Add workspace config detection from `.claude-ccbell.json` |
| **Commands** | Modify | Add `--local` flag to commands for workspace-specific ops |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add local config options |
| **commands/config.md** | Update | Add init --local command |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/config.go:**
```go
func (c *CCBell) LoadWithWorkspace(cwd string) (*Config, string, error) {
    globalCfg, globalPath, err := Load(homeDir)
    if err != nil { return nil, "", err }

    // Check for local config
    localPath := filepath.Join(cwd, ".claude-ccbell.json")
    if _, err := os.Stat(localPath); err == nil {
        localCfg, _, err := Load(cwd)
        if err != nil {
            log.Warn("Failed to load local config: %v", err)
        } else {
            // Merge local into global
            merged := c.MergeConfigs(globalCfg, localCfg)
            return merged, localPath, nil
        }
    }

    return globalCfg, globalPath, nil
}

func (c *CCBell) MergeConfigs(global, local *Config) *Config {
    merged := global.DeepCopy()

    // Override enabled
    if local.Enabled != nil {
        merged.Enabled = local.Enabled
    }

    // Override events (selective merge)
    for event, localEvent := range local.Events {
        if merged.Events[event] == nil {
            merged.Events[event] = localEvent
        } else {
            // Merge event config
            if localEvent.Sound != nil {
                merged.Events[event].Sound = localEvent.Sound
            }
            if localEvent.Volume != nil {
                merged.Events[event].Volume = localEvent.Volume
            }
        }
    }

    return merged
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    cwd, _ := os.Getwd()
    cfg, _, err := LoadWithWorkspace(cwd)
    // Use merged config
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/configure.md` with local config commands |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: No schema change, adds local config file detection (`.claude-ccbell.json`)
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/configure.md` (add --local flag documentation)
  - `plugins/ccbell/commands/config.md` (add init --local command)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag
- **Local Config Priority**: Local config > Global config (merges with overrides)

### Implementation Checklist

- [ ] Update `commands/configure.md` with local config options
- [ ] Update `commands/config.md` with init --local command
- [ ] Document config merge behavior
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

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

# Feature: Per-Workspace Configuration 📂

## Summary

Allow ccbell to read project-specific config from `.claude-ccbell.json` in the workspace root. Enables context-aware notifications (louder for production, subtle for dev).

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

## Technical Feasibility

### Configuration

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

### Implementation

```go
func LoadWithWorkspace(cwd string) (*Config, string, error) {
    globalCfg, globalPath, err := Load(homeDir)
    if err != nil { return nil, "", err }

    localPath := filepath.Join(cwd, ".claude-ccbell.json")
    if _, err := os.Stat(localPath); err == nil {
        localCfg, _, err := Load(cwd)
        if err != nil {
            log.Warn("Failed to load local config: %v", err)
        } else {
            merged := MergeConfigs(globalCfg, localCfg)
            return merged, localPath, nil
        }
    }

    return globalCfg, globalPath, nil
}

func MergeConfigs(global, local *Config) *Config {
    merged := global.DeepCopy()

    if local.Enabled != nil {
        merged.Enabled = local.Enabled
    }
    if local.Volume != nil {
        merged.Volume = local.Volume
    }

    for event, localEvent := range local.Events {
        if merged.Events[event] == nil {
            merged.Events[event] = localEvent
        } else {
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

### Commands

```bash
/ccbell:config init --local           # Generate local config template
/ccbell:config show --resolved        # Show resolved config (global + local)
/ccbell:config edit --local           # Edit local config
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Add `LoadWithWorkspace(cwd string)` for local config merging |
| **Core Logic** | Add | Add workspace config detection from `.claude-ccbell.json` |
| **Commands** | Modify | Add `--local` flag to commands for workspace-specific ops |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add local config options |
| **commands/config.md** | Update | Add init --local command |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [Config merge pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L206-L220)
- [Environment variable usage](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)

---

[Back to Feature Index](index.md)

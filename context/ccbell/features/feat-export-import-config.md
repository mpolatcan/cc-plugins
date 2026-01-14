# Feature: Export/Import Config 📤

## Summary

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs.

## Benefit

- **Team collaboration**: Standardize notification setups
- **Easy backup**: Protect configurations from accidental loss
- **Rapid onboarding**: New members get productive instantly
- **Experimentation safe**: Export before changes, restore if needed

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Low |
| **Category** | Config Management |

## Technical Feasibility

### Commands

```bash
/ccbell:config export --file ~/ccbell-config.json
/ccbell:config import ~/ccbell-config.json
/ccbell:config import https://example.com/my-config.json
```

### Implementation

```go
func (c *Config) Export(path string, includeSecrets bool) error {
    exportCfg := c.DeepCopy()

    if !includeSecrets {
        exportCfg.GlobalVolume = nil
        for _, event := range exportCfg.Events {
            event.Volume = nil
        }
    }

    data, _ := json.MarshalIndent(exportCfg, "", "  ")
    return os.WriteFile(path, data, 0644)
}

func (c *Config) Import(path string, merge bool) error {
    data, err := os.ReadFile(path)
    if err != nil { return err }

    var imported Config
    if err := json.Unmarshal(data, &imported); err != nil {
        return fmt.Errorf("invalid config: %w", err)
    }

    if merge {
        return c.Merge(&imported)
    }
    *c = imported
    return nil
}
```

## Configuration

No schema change - pure JSON serialization.

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `Export()`, `Import()`, `Merge()` methods |
| **Commands** | Add | `config` command (export, import) |
| **New File** | Add | `internal/config/export.go` |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/config.md** | Add | New command doc |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [JSON marshaling](https://pkg.go.dev/encoding/json)

---

[Back to Feature Index](index.md)

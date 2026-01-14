# Feature: Config Migration 📁

## Summary

Automatically update old config formats to newer versions while preserving settings.

## Benefit

- **Zero-downtime upgrades**: Update ccbell without losing or manually reconfiguring settings
- **Future-proof configuration**: New features automatically adopted without user intervention
- **Reduced maintenance burden**: No manual config cleanup or migration scripts needed
- **Improved user experience**: Seamless transitions build trust and reduce friction

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Category** | Config Management |

## Technical Feasibility

### Migration Chain

| From Version | To Version | Changes |
|--------------|------------|---------|
| 0.1.0 | 0.2.0 | Added profiles, new volume range |
| 0.2.0 | 0.3.0 | Added quiet hours |
| 0.3.0 | 0.4.0 | Renamed events |

### Implementation

```go
type Migration struct {
    FromVersion string
    ToVersion   string
    Migrate     func(*Config) error
}

var migrations = []Migration{
    {FromVersion: "0.1.0", ToVersion: "0.2.0", Migrate: migrate_v010_to_v020},
    {FromVersion: "0.2.0", ToVersion: "0.3.0", Migrate: migrate_v020_to_v030},
}

func (c *CCBell) LoadWithMigration(homeDir string) (*Config, string, error) {
    cfg, path, err := Load(homeDir)
    if err != nil { return nil, "", err }

    version := getConfigVersion(cfg) // default "0.1.0" if not set

    for _, m := range migrations {
        if semverLess(version, m.FromVersion) {
            if err := m.Migrate(cfg); err != nil {
                return nil, "", fmt.Errorf("migration %s->%s failed: %w",
                    version, m.ToVersion, err)
            }
            version = m.ToVersion
            log.Info("Migrated config: %s -> %s", version, m.ToVersion)
        }
    }

    setConfigVersion(cfg, currentVersion)
    return cfg, path, Save(path, cfg)
}
```

### Commands

```bash
/ccbell:migrate dry-run           # Preview migrations
/ccbell:migrate apply             # Apply migrations
/ccbell:migrate status            # Show current version
```

## Configuration

```json
{
  "version": "0.3.0"
}
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Add `version` field, migration chain |
| **Core Logic** | Modify | Add `LoadWithMigration()` function |
| **Commands** | Add | New `migrate` command |
| **Version** | Bump | 0.2.30 → 0.3.0 |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/** | Add | `migrate.md` command doc |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175)

---

[Back to Feature Index](index.md)

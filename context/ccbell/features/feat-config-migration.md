# Feature: Config Migration 📁

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

Automatically update old config formats to newer versions while preserving settings.

## Motivation

- Smooth upgrades between ccbell versions
- Backward compatibility
- Automatic schema updates

---

## Benefit

- **Zero-downtime upgrades**: Users can update ccbell without losing or manually reconfiguring settings
- **Future-proof configuration**: New features automatically adopted without user intervention
- **Reduced maintenance burden**: No need for manual config cleanup or migration scripts
- **Improved user experience**: Seamless transition between versions builds trust and reduces friction

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Category** | Config Management |

---

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
    {
        FromVersion: "0.1.0",
        ToVersion:   "0.2.0",
        Migrate:     migrate_v010_to_v020,
    },
    {
        FromVersion: "0.2.0",
        ToVersion:   "0.3.0",
        Migrate:     migrate_v020_to_v030,
    },
}

func migrate_v010_to_v020(cfg *Config) error {
    // Convert old volume (0-100) to (0.0-1.0)
    for _, event := range cfg.Events {
        if event.Volume != nil {
            *event.Volume = *event.Volume / 100.0
        }
    }
    return nil
}
```

### Migration Process

```go
func LoadWithMigration(homeDir string) (*Config, string, error) {
    cfg, configPath, err := Load(homeDir)
    if err != nil {
        return nil, "", err
    }

    // Get config version (default to "0.1.0" if not set)
    version := getConfigVersion(cfg)

    // Apply migrations if needed
    for _, migration := range migrations {
        if versionLess(version, migration.FromVersion) {
            if err := migration.Migrate(cfg); err != nil {
                return nil, "", fmt.Errorf("migration %s->%s failed: %w",
                    version, migration.ToVersion, err)
            }
            version = migration.ToVersion
            log.Info("Migrated config from %s to %s", version, migration.ToVersion)
        }
    }

    // Update version in config
    setConfigVersion(cfg, currentVersion)

    return cfg, configPath, nil
}
```

### Commands

```bash
/ccbell:migrate dry-run           # Preview migrations
/ccbell:migrate apply             # Apply migrations
/ccbell:migrate status            # Show current version
/ccbell:config version            # Show config version
```

### Migration Report

```
$ ccbell:migrate dry-run

Config version: 0.1.0 (current: 0.4.0)

Required migrations:
  0.1.0 -> 0.2.0: Volume range conversion
  0.2.0 -> 0.3.0: Quiet hours addition
  0.3.0 -> 0.4.0: Event renaming

Changes:
  - volume values will be divided by 100
  - default quiet hours will be added
  - 'idle' event will be renamed to 'idle_prompt'

Apply migrations? [y/n]:
```

---

## Audio Player Compatibility

Config migration doesn't interact with audio playback:
- Purely config transformation
- No player changes required
- Happens before any playback

---

## Implementation

### Version Detection

```go
type Config struct {
    Version string `json:"version,omitempty"`
    // ... other fields
}

func getConfigVersion(cfg *Config) string {
    if cfg.Version == "" {
        return "0.1.0" // Original version before versioning
    }
    return cfg.Version
}
```

### Migration Logging

```go
// Log migrations for debugging
func (c *CCBell) logMigration(from, to string) {
    log.Printf("Migrated config: %s -> %s", from, to)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

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
| **Config** | Modify | Add `version` field, migration chain functions |
| **Core Logic** | Modify | Add `LoadWithMigration()` function |
| **Commands** | Add | New `migrate` command with dry-run/apply/status |
| **Version** | Bump | 0.2.30 → 0.3.0 |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/** | Add | `migrate.md` command doc |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/migrate.go:**
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

func migrate_v010_to_v020(cfg *Config) error {
    // Convert volume 0-100 to 0.0-1.0
    for _, event := range cfg.Events {
        if event.Volume != nil {
            *event.Volume = *event.Volume / 100.0
        }
    }
    return nil
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    migrateCmd := flag.NewFlagSet("migrate", flag.ExitOnError)
    dryRun := migrateCmd.Bool("dry-run", false, "Preview migrations")
    apply := migrateCmd.Bool("apply", false, "Apply migrations")

    switch os.Args[1] {
    case "migrate":
        migrateCmd.Parse(os.Args[2:])
        cfg, _, err := LoadWithMigration(homeDir)
        // ... output migration report
    }
}
```

---

## References

### ccbell Implementation Research

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - Config loading
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) - Validation pattern

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | New `/ccbell:migrate` command documentation required in `commands/migrate.md` |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `version` field to config for migration tracking
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/migrate.md` (new file)
  - `plugins/ccbell/commands/config.md` (update to reference migrate)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/migrate.md` with dry-run, apply, status commands
- [ ] Update `commands/config.md` to reference migration capability
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)

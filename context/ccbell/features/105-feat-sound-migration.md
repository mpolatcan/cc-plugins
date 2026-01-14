# Feature: Sound Migration

Migrate sounds and configurations between versions.

## Summary

Tools to migrate sounds when upgrading ccbell or changing platforms.

## Motivation

- Upgrade between versions
- Platform migration
- Configuration transfer

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Migration Types

| Type | Description | Source |
|------|-------------|--------|
| Version | Upgrade to new ccbell | Old config |
| Platform | macOS to Linux or vice versa | Old config |
| Backup | Restore from backup | Backup |
| Import | Import from external source | External |

### Configuration

```go
type MigrationConfig struct {
    SourceVersion  string `json:"source_version"`
    TargetVersion  string `json:"target_version"`
    SourcePlatform string `json:"source_platform"`
    BackupDir      string `json:"backup_dir"`
    IncludeSounds  bool   `json:"include_sounds"`
    IncludeConfig  bool   `json:"include_config"`
    IncludeState   bool   `json:"include_state"`
    DryRun         bool   `json:"dry_run"`
}

type MigrationPlan struct {
    Steps       []*MigrationStep `json:"steps"`
    Warnings    []string         `json:"warnings"`
    BackupSize  int64            `json:"backup_size"`
    Duration    time.Duration    `json:"estimated_duration"`
}

type MigrationStep struct {
    Action      string `json:"action"`       // "copy", "convert", "skip"
    Source      string `json:"source"`
    Destination string `json:"destination"`
    Reason      string `json:"reason"`
}
```

### Commands

```bash
/ccbell:migrate --dry-run                 # Preview migration
/ccbell:migrate --backup                  # Create backup first
/ccbell:migrate --from-version 0.9        # Migrate from version
/ccbell:migrate platform macos-to-linux   # Platform migration
/ccbell:migrate import ~/backup           # Import backup
/ccbell:migrate status                    # Check migration status
/ccbell:migrate validate                  # Validate after migration
```

### Output

```
$ ccbell:migrate --dry-run

=== Migration Plan ===

Source: v0.9 (macOS)
Target: v1.0 (macOS)
Actions: 8

[1] Copy config
    From: ~/.config/ccbell/config.json
    To: ~/.config/ccbell/config.json.new
    Status: Compatible

[2] Copy sounds
    From: ~/Library/Application Support/ccbell/sounds/
    To: ~/.local/share/ccbell/sounds/
    Status: 12 sounds

[3] Migrate state
    From: ~/.config/ccbell/state.json
    To: ~/.config/ccbell/state.json.new
    Status: Compatible

[4] Convert format
    From: AIFF (macOS) to AIFF (universal)
    Status: No conversion needed

Warnings:
  - Volume levels may need adjustment for new player
  - Some sounds may not be compatible with Linux

Estimated Duration: 2s
Backup First? [Yes] [No] [Cancel]
```

---

## Audio Player Compatibility

Migration doesn't play sounds:
- File and config operations
- No player changes required

---

## Implementation

### Migration Planning

```go
func (m *MigrationManager) Plan(config *MigrationConfig) (*MigrationPlan, error) {
    plan := &MigrationPlan{
        Steps:    make([]*MigrationStep, 0),
        Warnings: make([]string, 0),
    }

    // Check source config
    if config.IncludeConfig {
        step := &MigrationStep{
            Action:      "copy",
            Source:      m.getConfigPath(),
            Destination: m.getNewConfigPath(),
            Reason:      "Copy configuration",
        }
        if err := m.validateConfigCompatible(); err != nil {
            step.Action = "convert"
            step.Reason = fmt.Sprintf("Convert config: %v", err)
            plan.Warnings = append(plan.Warnings, err.Error())
        }
        plan.Steps = append(plan.Steps, step)
    }

    // Check sound files
    if config.IncludeSounds {
        sounds := m.listSounds()
        for _, sound := range sounds {
            step := &MigrationStep{
                Action:      "copy",
                Source:      sound.Path,
                Destination: m.getNewSoundPath(sound.Name),
                Reason:      fmt.Sprintf("Copy sound: %s", sound.Name),
            }
            plan.Steps = append(plan.Steps, step)
        }
    }

    return plan, nil
}
```

### Migration Execution

```go
func (m *MigrationManager) Execute(plan *MigrationPlan) error {
    // Create backup first
    if err := m.createBackup(); err != nil {
        return fmt.Errorf("backup failed: %w", err)
    }

    // Execute each step
    for _, step := range plan.Steps {
        switch step.Action {
        case "copy":
            if err := m.copyFile(step.Source, step.Destination); err != nil {
                return fmt.Errorf("copy failed: %w", err)
            }
        case "convert":
            if err := m.convertConfig(step.Source, step.Destination); err != nil {
                return fmt.Errorf("convert failed: %w", err)
            }
        case "skip":
            log.Debug("Skipping: %s", step.Reason)
        }
    }

    // Finalize
    if err := m.activateNewConfig(); err != nil {
        return fmt.Errorf("activation failed: %w", err)
    }

    return nil
}
```

### Platform Migration

```go
func (m *MigrationManager) migratePlatform(sourcePlatform, targetPlatform string) error {
    // macOS uses AIFF, Linux may need WAV for better compatibility
    if sourcePlatform == "macos" && targetPlatform == "linux" {
        for _, sound := range m.listSounds() {
            if strings.HasSuffix(sound.Path, ".aiff") {
                // Convert AIFF to WAV for Linux
                wavPath := strings.TrimSuffix(sound.Path, ".aiff") + ".wav"
                if err := m.convertToWAV(sound.Path, wavPath); err != nil {
                    log.Debug("Conversion failed for %s: %v", sound.Path, err)
                }
            }
        }
    }
    return nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config migration
- [Sound paths](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Sound paths
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-91) - Platform handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

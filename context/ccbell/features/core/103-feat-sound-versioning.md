# Feature: Sound Versioning

Version control for sound configurations.

## Summary

Track changes to sounds and configurations with version history.

## Motivation

- Track configuration changes
- Roll back to previous versions
- Audit trail

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Version Types

| Type | Description | Storage |
|------|-------------|---------|
| Config | Configuration changes | JSON diffs |
| Sound | Sound file versions | Full copies |
| Snapshot | Full system state | Archive |

### Configuration

```go
type VersionConfig struct {
    Enabled          bool     `json:"enabled"`
    MaxVersions      int      `json:"max_versions"`      // keep N versions
    IncludeSounds    bool     `json:"include_sounds"`    // include sound files
    IncludeState     bool     `json:"include_state"`     // include state
    AutoSnapshot     bool     `json:"auto_snapshot"`     // auto-save on change
    SnapshotInterval int      `json:"snapshot_interval"` // hours
    StorageDir       string   `json:"storage_dir"`
}

type VersionEntry struct {
    ID          string    `json:"id"`
    Timestamp   time.Time `json:"timestamp"`
    Type        string    `json:"type"`        // config, sound, snapshot
    Changes     []Change  `json:"changes"`
    SoundHashes map[string]string `json:"sound_hashes"`
    CreatedBy   string    `json:"created_by"`  // user, auto
}

type Change struct {
    Field    string `json:"field"`
    OldValue string `json:"old_value"`
    NewValue string `json:"new_value"`
}
```

### Commands

```bash
/ccbell:version list                 # List versions
/ccbell:version show <id>            # Show version details
/ccbell:version diff <id1> <id2>     # Compare versions
/ccbell:version restore <id>         # Restore version
/ccbell:version snapshot             # Create manual snapshot
/ccbell:version rollback <id>        # Rollback to version
/ccbell:version cleanup --keep 10    # Keep 10 versions
/ccbell:version export <id>          # Export version
```

### Output

```
$ ccbell:version list

=== Sound Version History ===

Total: 24 versions (15 config, 9 snapshots)

[1] v24  Today 10:30 AM
    Type: config
    Changes: 2 events modified
    [Show] [Diff] [Restore] [Export]

[2] v23  Today 09:00 AM
    Type: snapshot
    Included: 12 sounds
    [Show] [Diff] [Restore] [Export]

[3] v22  Yesterday 04:00 PM
    Type: config
    Changes: quiet hours updated
    [Show] [Diff] [Restore] [Export]

...

[24] v1   2 weeks ago
    Type: initial
    Changes: initial configuration
    [Show] [Restore]

Showing 10 of 24
[More] [Cleanup] [Settings]
```

---

## Audio Player Compatibility

Versioning doesn't play sounds:
- Storage feature
- No player changes required

---

## Implementation

### Version Creation

```go
func (v *VersionManager) CreateVersion(versionType string) (*VersionEntry, error) {
    entry := &VersionEntry{
        ID:        generateID(),
        Timestamp: time.Now(),
        Type:      versionType,
        Changes:   v.detectChanges(),
    }

    // Hash current sounds
    if v.config.IncludeSounds {
        entry.SoundHashes = v.hashAllSounds()
    }

    // Save version
    versionPath := filepath.Join(v.config.StorageDir, entry.ID+".json")
    data, _ := json.MarshalIndent(entry, "", "  ")
    os.WriteFile(versionPath, data, 0644)

    // Cleanup old versions
    v.cleanup()

    return entry, nil
}
```

### Change Detection

```go
func (v *VersionManager) detectChanges() []Change {
    changes := []Change{}

    prevConfig := v.loadPreviousConfig()
    if prevConfig == nil {
        return []Change{{Field: "initial", OldValue: "", NewValue: "initialized"}}
    }

    // Compare events
    for event, current := range v.config.Events {
        if prev, exists := prevConfig.Events[event]; exists {
            if !reflect.DeepEqual(current, prev) {
                changes = append(changes, Change{
                    Field:    fmt.Sprintf("event.%s", event),
                    OldValue: prev.String(),
                    NewValue: current.String(),
                })
            }
        } else {
            changes = append(changes, Change{
                Field:    fmt.Sprintf("event.%s", event),
                OldValue: "(none)",
                NewValue: current.String(),
            })
        }
    }

    return changes
}
```

### Version Restore

```go
func (v *VersionManager) Restore(versionID string) error {
    entry, err := v.loadVersion(versionID)
    if err != nil {
        return err
    }

    // Create backup of current state
    v.CreateVersion("backup")

    // Restore sounds
    if v.config.IncludeSounds && len(entry.SoundHashes) > 0 {
        for soundID, expectedHash := range entry.SoundHashes {
            currentHash := v.hashSound(soundID)
            if currentHash != expectedHash {
                v.restoreSound(soundID, versionID)
            }
        }
    }

    // Restore config
    v.restoreConfig(entry)

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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config versioning
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

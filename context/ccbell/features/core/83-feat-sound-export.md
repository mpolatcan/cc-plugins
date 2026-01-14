# Feature: Sound Export

Export sounds and configuration.

## Summary

Export sounds to portable formats and backup configuration for portability.

## Motivation

- Move sounds between systems
- Share sound packs
- Backup configuration
- Portability across installations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Export Options

| Option | Description | Output |
|--------|-------------|--------|
| Sounds | Export all sounds | `.zip` archive |
| Config | Export configuration | `.json` file |
| Profile | Export specific profile | `.json` bundle |
| Sounds+Config | Full export | `.zip` with both |
| Single sound | Export one sound | `.aiff`/`.wav` |

### Implementation

```go
type ExportConfig struct {
    IncludeSounds    bool     `json:"include_sounds"`
    IncludeConfig    bool     `json:"include_config"`
    IncludeAnalytics bool     `json:"include_analytics"`
    Format           string   `json:"format"`           // "zip", "tar.gz"
    SoundFormat      string   `json:"sound_format"`     // "original", "wav", "mp3"
    Profile          string   `json:"profile"`          // specific profile
    Events           []string `json:"events"`           // specific events
}

type ExportMetadata struct {
    Version       string    `json:"version"`
    ExportedAt    time.Time `json:"exported_at"`
    CcbellVersion string    `json:"ccbell_version"`
    Platform      string    `json:"platform"`
    Included      ExportContents `json:"included"`
}

type ExportContents struct {
    SoundCount    int      `json:"sound_count"`
    ConfigSize    int64    `json:"config_size_bytes"`
    TotalSize     int64    `json:"total_size_bytes"`
    Profiles      []string `json:"profiles"`
    Events        []string `json:"events"`
}
```

### Commands

```bash
/ccbell:export sounds                    # Export all sounds
/ccbell:export config                    # Export configuration
/ccbell:export all                       # Export sounds + config
/ccbell:export sounds --format tar.gz    # Different format
/ccbell:export profile work              # Export profile
/ccbell:export sounds --to ~/backup.zip  # Custom output
/ccbell:export single bundled:stop       # Export one sound
/ccbell:import ~/backup.zip              # Import exported
```

### Output

```
$ ccbell:export all

=== Sound Export ===

Source:
  Sounds: 24
  Config: ~/.config/ccbell/config.json
  Profile: default

Creating archive...
  Adding sounds/ (15.2 MB)
  Adding config.json (2.3 KB)
  Adding metadata.json (512 B)

Archive: ccbell-export-2024-01-15.zip
Size: 15.4 MB

[Export] [Cancel]
```

---

## Audio Player Compatibility

Export doesn't play sounds:
- File copy/zip operations
- No player changes required

---

## Implementation

### Archive Creation

```go
func (e *Exporter) Export(config *ExportConfig, outputPath string) error {
    archive, err := os.Create(outputPath)
    if err != nil {
        return err
    }
    defer archive.Close()

    zw := zip.NewWriter(archive)
    defer zw.Close()

    // Add metadata
    metadata := e.generateMetadata(config)
    if err := e.addJSON(zw, "metadata.json", metadata); err != nil {
        return err
    }

    // Add sounds
    if config.IncludeSounds {
        sounds, err := e.getExportableSounds(config)
        if err != nil {
            return err
        }
        for _, sound := range sounds {
            if err := e.addFile(zw, sound.Path, "sounds/"+sound.Name); err != nil {
                return err
            }
        }
    }

    // Add config
    if config.IncludeConfig {
        if err := e.addJSON(zw, "config.json", e.config); err != nil {
            return err
        }
    }

    return zw.Close()
}
```

### Import Handler

```go
func (e *Importer) Import(archivePath string) (*ImportResult, error) {
    archive, err := zip.OpenReader(archivePath)
    if err != nil {
        return nil, err
    }
    defer archive.Close()

    result := &ImportResult{}

    for _, file := range archive.File {
        switch {
        case strings.HasPrefix(file.Name, "sounds/"):
            result.SoundsImported++
            e.extractSound(file)
        case file.Name == "config.json":
            result.ConfigImported = true
            e.importConfig(file)
        case file.Name == "metadata.json":
            e.validateVersion(file)
        }
    }

    return result, nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Go standard library (archive/zip) |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config export
- [Sound paths](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound resolution

### Research Sources

- [Go archive/zip](https://pkg.go.dev/archive/zip)
- [ZIP file format](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

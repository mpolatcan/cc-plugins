# Feature: Sound Event Export

Export configurations and sounds.

## Summary

Export ccbell configuration, sounds, and settings to a portable format.

## Motivation

- Backup configurations
- Share settings
- Migrate between machines

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Export Types

| Type | Description | Example |
|-------|-------------|---------|
| Config | Export config JSON | ~/.claude/ccbell.config.json |
| Sounds | Bundle sound files | Sounds folder |
| All | Complete backup | Config + sounds |
| Profile | Single profile | Work profile |

### Configuration

```go
type ExportConfig struct {
    Enabled       bool              `json:"enabled"`
    DefaultFormat string           `json:"default_format"` // "zip", "tar"
    IncludeSounds bool             `json:"include_sounds"`
    IncludeState  bool             `json:"include_state"`
    Encryption    *EncryptionConfig `json:"encryption,omitempty"`
}

type EncryptionConfig struct {
    Enabled     bool   `json:"enabled"`
    Algorithm   string `json:"algorithm"` // "aes256"
    PasswordEnv string `json:"password_env"` // Environment variable
}
```

### Commands

```bash
/ccbell:export config               # Export config only
/ccbell:export sounds               # Export sounds only
/ccbell:export all                  # Export everything
/ccbell:export profile work         # Export profile
/ccbell:export all /path/to/backup.zip
/ccbell:export encrypt              # Enable encryption
/ccbell:export decrypt <file>       # Decrypt export
```

### Output

```
$ ccbell:export config

=== Sound Event Export ===

Export Type: Config Only
Format: zip
Include Sounds: No
Include State: No
Encryption: Disabled

Ready to export:
  ~/.claude/ccbell.config.json
  ~/.claude/ccbell.state

[Export to File] [Export to stdout]
```

---

## Audio Player Compatibility

Export doesn't play sounds:
- Data operation
- No player changes required

---

## Implementation

### Export Manager

```go
type ExportManager struct {
    config   *ExportConfig
}

func (m *ExportManager) Export(exportType, outputPath string) error {
    var archive *zip.Writer
    var err error

    if outputPath == "-" {
        archive = zip.NewWriter(os.Stdout)
    } else {
        f, err := os.Create(outputPath)
        if err != nil {
            return err
        }
        defer f.Close()
        archive = zip.NewWriter(f)
    }
    defer archive.Close()

    switch exportType {
    case "config":
        return m.exportConfig(archive)
    case "sounds":
        return m.exportSounds(archive)
    case "all":
        return m.exportAll(archive)
    case "profile":
        return m.exportProfile(archive)
    default:
        return fmt.Errorf("unknown export type: %s", exportType)
    }
}

func (m *ExportManager) exportConfig(archive *zip.Writer) error {
    homeDir, _ := os.UserHomeDir()

    files := []string{
        filepath.Join(homeDir, ".claude", "ccbell.config.json"),
    }

    if m.config.IncludeState {
        files = append(files, filepath.Join(homeDir, ".claude", "ccbell.state"))
    }

    for _, file := range files {
        if err := m.addFileToArchive(archive, file, filepath.Base(file)); err != nil {
            if os.IsNotExist(err) {
                continue
            }
            return err
        }
    }

    return nil
}

func (m *ExportManager) exportSounds(archive *zip.Writer) error {
    pluginRoot := os.Getenv("CLAUDE_PLUGIN_ROOT")
    if pluginRoot == "" {
        pluginRoot = findPluginRoot(homeDir)
    }

    soundsDir := filepath.Join(pluginRoot, "sounds")
    return m.addDirectoryToArchive(archive, soundsDir, "sounds")
}

func (m *ExportManager) addFileToArchive(archive *zip.Writer, filePath, arcName string) error {
    f, err := archive.Create(arcName)
    if err != nil {
        return err
    }

    data, err := os.ReadFile(filePath)
    if err != nil {
        return err
    }

    _, err = f.Write(data)
    return err
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| zip | Go Stdlib | Free | ZIP file handling |
| archive/tar | Go Stdlib | Free | TAR file handling |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config file location
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Config path resolution
- [Player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound path resolution

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

# Feature: Sound Event Import

Import configurations and sounds.

## Summary

Import ccbell configuration, sounds, and settings from portable formats.

## Motivation

- Restore backups
- Import shared settings
- Migration support

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Import Types

| Type | Description | Example |
|-------|-------------|---------|
| Config | Import config | JSON file |
| Sounds | Import sounds | AIFF files |
| All | Complete restore | Backup zip |
| Profile | Import profile | Work profile |

### Configuration

```go
type ImportConfig struct {
    Enabled       bool              `json:"enabled"`
    DefaultFormat string           `json:"default_format"` // "zip", "auto"
    Backup        bool              `json:"backup_before_import"`
    MergeStrategy string           `json:"merge_strategy"` // "replace", "merge"
    ValidateOnly  bool             `json:"validate_only"` // Don't import, just validate
}

type ImportResult struct {
    Success      bool              `json:"success"`
    FilesImported int              `json:"files_imported"`
    Errors       []ImportError     `json:"errors,omitempty"`
    Warnings     []ImportWarning   `json:"warnings,omitempty"`
}

type ImportError struct {
    File    string `json:"file"`
    Message string `json:"message"`
}
```

### Commands

```bash
/ccbell:import config /path/to/config.json
/ccbell:import sounds /path/to/sounds.zip
/ccbell:import all /path/to/backup.zip
/ccbell:import profile work /path/to/work-profile.zip
/ccbell:import --dry-run /path/to/backup.zip  # Validate only
/ccbell:import --merge /path/to/config.json   # Merge instead of replace
```

### Output

```
$ ccbell:import --dry-run /path/to/backup.zip

=== Sound Event Import ===

Source: /path/to/backup.zip
Format: zip
Strategy: replace

Files to import:
  ccbell.config.json (valid)
  ccbell.state (valid)
  sounds/stop.aiff (valid)
  sounds/permission_prompt.aiff (valid)

Validation: PASSED (4/4 files)

[Import] [Cancel]
```

---

## Audio Player Compatibility

Import doesn't play sounds:
- Data operation
- No player changes required

---

## Implementation

### Import Manager

```go
type ImportManager struct {
    config   *ImportConfig
}

func (m *ImportManager) Import(sourcePath string) (*ImportResult, error) {
    result := &ImportResult{Success: true}

    // Open archive
    reader, err := zip.OpenReader(sourcePath)
    if err != nil {
        return nil, fmt.Errorf("failed to open archive: %w", err)
    }
    defer reader.Close()

    // Validate all files first
    for _, file := range reader.File {
        if err := m.validateFile(file); err != nil {
            result.Success = false
            result.Errors = append(result.Errors, ImportError{
                File:    file.Name,
                Message: err.Error(),
            })
        }
    }

    // If validate only or has errors, return
    if m.config.ValidateOnly || !result.Success {
        return result, nil
    }

    // Backup existing config if needed
    if m.config.Backup {
        if err := m.createBackup(); err != nil {
            return nil, fmt.Errorf("backup failed: %w", err)
        }
    }

    // Extract files
    for _, file := range reader.File {
        if err := m.extractFile(file); err != nil {
            result.Success = false
            result.Errors = append(result.Errors, ImportError{
                File:    file.Name,
                Message: err.Error(),
            })
        } else {
            result.FilesImported++
        }
    }

    return result, nil
}

func (m *ImportManager) validateFile(file *zip.File) error {
    // Check for path traversal
    if strings.Contains(file.Name, "..") {
        return fmt.Errorf("path traversal not allowed")
    }

    // Check for dangerous paths
    dangerous := []string{"/etc/", "/usr/", "/bin/", "/sbin/"}
    for _, d := range dangerous {
        if strings.HasPrefix(file.Name, d) {
            return fmt.Errorf("dangerous path: %s", file.Name)
        }
    }

    return nil
}

func (m *ImportManager) extractFile(file *zip.File) error {
    homeDir, _ := os.UserHomeDir()

    // Determine destination
    var destPath string
    if strings.HasPrefix(file.Name, "sounds/") {
        pluginRoot := os.Getenv("CLAUDE_PLUGIN_ROOT")
        if pluginRoot == "" {
            pluginRoot = findPluginRoot(homeDir)
        }
        destPath = filepath.Join(pluginRoot, file.Name)
    } else if file.Name == "ccbell.config.json" {
        destPath = filepath.Join(homeDir, ".claude", "ccbell.config.json")
    } else if file.Name == "ccbell.state" {
        destPath = filepath.Join(homeDir, ".claude", "ccbell.state")
    } else {
        return nil // Skip unknown files
    }

    return m.extractFileFromZip(file, destPath)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| zip | Go Stdlib | Free | ZIP file handling |

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

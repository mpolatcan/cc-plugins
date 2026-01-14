# Feature: Sound Profile Export/Import

Export and import sound profiles for sharing.

## Summary

Export sound profiles to share configurations with others.

## Motivation

- Share configurations
- Backup profiles
- Team configurations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Export Options

| Option | Description | Output |
|--------|-------------|--------|
| JSON | Export as JSON | `.json` file |
| YAML | Export as YAML | `.yaml` file |
| Archive | Include sounds | `.zip` archive |

### Implementation

```go
type ProfileExport struct {
    Version       string            `json:"version"`
    ExportedAt    time.Time         `json:"exported_at"`
    ProfileName   string            `json:"profile_name"`
    Config        *config.Config    `json:"config"`
    IncludedSounds []string         `json:"included_sounds"` // sound IDs
    Checksum      string            `json:"checksum"`
}

type ExportOptions struct {
    Format         string   `json:"format"`          // "json", "yaml", "archive"
    IncludeSounds  bool     `json:"include_sounds"`
    IncludeState   bool     `json:"include_state"`
    Password       string   `json:"password,omitempty"` // encryption
}
```

### Commands

```bash
/ccbell:profile export myprofile           # Export profile
/ccbell:profile export myprofile --yaml    # YAML format
/ccbell:profile export myprofile --archive # Include sounds
/ccbell:profile export all                 # Export all profiles
/ccbell:profile import myprofile.json      # Import profile
/ccbell:profile import --password xxx      # Encrypted import
/ccbell:profile validate myprofile.json    # Validate export
```

### Output

```
$ ccbell:profile export work --archive

=== Export Profile ===

Profile: work
Format: Archive (ZIP)

Contents:
  - config.json
  - sounds/bundled/stop.aiff
  - sounds/bundled/permission_prompt.aiff
  - sounds/custom/notification.aiff

Size: 2.4 MB
Checksum: SHA256:a1b2c3d4...

[Save to] [/Users/user/Downloads/work-ccbell.zip]
[Share] [Copy Link] [Cancel]
```

---

## Audio Player Compatibility

Export/import doesn't play sounds:
- Configuration transfer
- No player changes required

---

## Implementation

### Profile Export

```go
func (p *ProfileManager) Export(profileName string, opts *ExportOptions) ([]byte, error) {
    profile, ok := p.profiles[profileName]
    if !ok {
        return nil, fmt.Errorf("profile not found: %s", profileName)
    }

    export := &ProfileExport{
        Version:     "1.0",
        ExportedAt:  time.Now(),
        ProfileName: profileName,
        Config:      profile.Config,
    }

    switch opts.Format {
    case "archive":
        return p.exportArchive(export, opts)
    case "yaml":
        return p.exportYAML(export)
    default:
        return p.exportJSON(export)
    }
}

func (p *ProfileManager) exportArchive(export *ProfileExport, opts *ExportOptions) ([]byte, error) {
    buf := new(bytes.Buffer)
    zw := zip.NewWriter(buf)

    // Add config
    configData, _ := json.MarshalIndent(export.Config, "", "  ")
    zw.Write(configData, "config.json")

    // Add sounds
    if opts.IncludeSounds {
        for _, soundID := range export.IncludedSounds {
            soundPath, _ := p.resolveSoundPath(soundID)
            if data, err := os.ReadFile(soundPath); err == nil {
                path := fmt.Sprintf("sounds/%s", filepath.Base(soundPath))
                zw.Write(data, path)
            }
        }
    }

    zw.Close()
    return buf.Bytes(), nil
}
```

### Profile Import

```go
func (p *ProfileManager) Import(data []byte, opts *ExportOptions) (*ImportResult, error) {
    var export *ProfileExport

    switch opts.Format {
    case "archive":
        return p.importArchive(data, opts)
    case "yaml":
        export = &ProfileExport{}
        yaml.Unmarshal(data, export)
    default:
        export = &ProfileExport{}
        json.Unmarshal(data, export)
    }

    // Validate checksum
    if err := p.validateChecksum(export, data); err != nil {
        return nil, fmt.Errorf("invalid checksum: %w", err)
    }

    // Create profile
    profile := &Profile{
        Name:   export.ProfileName,
        Config: export.Config,
    }

    p.profiles[profile.Name] = profile
    return &ImportResult{ProfileName: profile.Name}, p.saveProfiles()
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
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

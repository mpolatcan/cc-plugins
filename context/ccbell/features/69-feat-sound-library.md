# Feature: Sound Library Management

Organize and browse all available sounds in a library view.

## Summary

Central library to view, organize, and manage all installed sounds (bundled, custom, and packs).

## Motivation

- Easy sound browsing
- Organize custom sounds
- Quick access to all sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Library Structure

```
~/.claude/ccbell/
├── sounds/
│   ├── bundled/
│   │   ├── stop.aiff
│   │   ├── permission_prompt.aiff
│   │   ├── idle_prompt.aiff
│   │   └── subagent.aiff
│   ├── custom/
│   │   ├── my-sound-1.aiff
│   │   └── my-sound-2.wav
│   └── packs/
│       └── zen-bells-v1.0/
│           ├── stop.aiff
│           ├── permission.aiff
│           └── ...
```

### Sound Metadata

```go
type SoundMetadata struct {
    ID          string    `json:"id"`
    Name        string    `json:"name"`
    Path        string    `json:"path"`
    Source      string    `json:"source"` // "bundled", "custom", "pack"
    Pack        string    `json:"pack,omitempty"`
    Duration    float64   `json:"duration"`
    SizeBytes   int64     `json:"size_bytes"`
    Format      string    `json:"format"`
    SampleRate  int       `json:"sample_rate"`
    Created     time.Time `json:"created"`
    UsedCount   int       `json:"used_count"`
    LastUsed    time.Time `json:"last_used"`
}
```

### Commands

```bash
/ccbell:library list             # List all sounds
/ccbell:library list --bundled   # List bundled sounds
/ccbell:library list --custom    # List custom sounds
/ccbell:library list --packs     # List pack sounds
/ccbell:library info stop        # Show sound details
/ccbell:library preview stop     # Preview sound
/ccbell:library stats            # Show library statistics
/ccbell:library search "chime"   # Search sounds
/ccbell:library tag stop my-tag  # Add tag to sound
```

### Output

```
$ ccbell:library list --custom

=== Sound Library (Custom) ===

[1] my-alert.aiff
    Tags: [alert] [important]
    Duration: 1.2s | Size: 245 KB | Format: AIFF
    Used: 45 times | Last used: Jan 12

[2] gentle-chime.wav
    Tags: [calm] [subtle]
    Duration: 0.8s | Size: 128 KB | Format: WAV
    Used: 12 times | Last used: Jan 10

[3] notification-sound.mp3
    Tags: [notification]
    Duration: 0.5s | Size: 85 KB | Format: MP3
    Used: 89 times | Last used: Jan 14

$ ccbell:library stats

=== Library Statistics ===

Total sounds: 45
  Bundled: 4
  Custom: 12
  Packs: 29

Total size: 45.2 MB
  Bundled: 2.1 MB
  Custom: 15.5 MB
  Packs: 27.6 MB

Most used:
  1. bundled:stop (234 uses)
  2. custom:notification (89 uses)
  3. bundled:permission_prompt (67 uses)
```

---

## Audio Player Compatibility

Library management doesn't play sounds directly:
- Uses `player.Play()` for preview
- No player changes required
- Purely organizational

---

## Implementation

### Library Index

```go
type SoundLibrary struct {
    sounds     map[string]*SoundMetadata
    indexPath  string
}

func (l *SoundLibrary) BuildIndex() error {
    l.sounds = make(map[string]*SoundMetadata)

    // Index bundled sounds
    bundledDir := filepath.Join(pluginRoot, "sounds")
    l.indexDir(bundledDir, "bundled")

    // Index custom sounds
    customDir := filepath.Join(homeDir, "sounds")
    l.indexDir(customDir, "custom")

    // Index pack sounds
    packsDir := filepath.Join(homeDir, "packs")
    l.indexPacksDir(packsDir)

    return l.saveIndex()
}

func (l *SoundLibrary) Search(query string) []*SoundMetadata {
    results := []*SoundMetadata{}
    for _, sound := range l.sounds {
        if strings.Contains(strings.ToLower(sound.Name), strings.ToLower(query)) ||
           containsTag(sound.Tags, query) {
            results = append(results, sound)
        }
    }
    return results
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

- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling
- [File walking](https://pkg.go.dev/path/filepath#Walk) - Directory traversal
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Sound references

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | File I/O |
| Linux | ✅ Supported | File I/O |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

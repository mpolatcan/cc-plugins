# Feature: Sound File Validation

Validate sound files before using them.

## Summary

Check sound files for validity (format, duration, sample rate) before accepting them in configuration.

## Motivation

- Prevent configuration errors from bad sound files
- Warn users about incompatible audio formats
- Ensure consistent notification quality

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Audio File Analysis Tools

| Tool | Format Support | Platform |
|------|----------------|----------|
| `ffprobe` (ffmpeg) | All | macOS, Linux |
| `afinfo` (macOS) | AIFF, WAV, MP3 | macOS only |
| `file` command | Basic | macOS, Linux |

### Implementation with ffprobe

```bash
# Get audio file information
ffprobe -v quiet -print_format json -show_format -show_streams sound.aiff

# Check duration and format
{
    "format": {
        "format_name": "aiff",
        "duration": "1.234"
    },
    "streams": [{
        "codec_name": "pcm_s24be",
        "sample_rate": "44100",
        "channels": "1"
    }]
}
```

### Validation Rules

```go
type SoundValidation struct {
    MaxDuration    time.Duration `json:"max_duration"`    // e.g., 5s
    MinDuration    time.Duration `json:"min_duration"`    // e.g., 100ms
    AllowedFormats []string      `json:"allowed_formats"` // ["aiff", "wav", "mp3"]
    MaxFileSize    int64         `json:"max_file_size"`   // bytes
}

func validateSound(path string, rules SoundValidation) error {
    info, err := getAudioInfo(path)
    if err != nil {
        return fmt.Errorf("failed to analyze sound: %w", err)
    }

    if info.Duration > rules.MaxDuration {
        return fmt.Errorf("sound too long: %s (max: %s)", info.Duration, rules.MaxDuration)
    }

    if !contains(rules.AllowedFormats, info.Format) {
        return fmt.Errorf("unsupported format: %s (allowed: %v)", info.Format, rules.AllowedFormats)
    }

    return nil
}
```

### Configuration

```json
{
  "validation": {
    "max_duration": "5s",
    "min_duration": "100ms",
    "allowed_formats": ["aiff", "wav", "mp3", "ogg", "flac"],
    "max_file_size": "10485760"
  }
}
```

---

## Audio Player Compatibility

Validation runs before audio player is invoked:
- Uses ffprobe to analyze files
- Does not affect player compatibility
- Helps prevent player errors

---

## Implementation

### Info Extraction

```go
type AudioInfo struct {
    Format      string
    Duration    time.Duration
    SampleRate  int
    Channels    int
    BitDepth    int
    FileSize    int64
}

func getAudioInfo(path string) (*AudioInfo, error) {
    cmd := exec.Command("ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", "-show_streams", path)

    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    // Parse JSON output
    // Extract format, duration, streams
}
```

### Configure Validation

```go
// In config validation
func (c *Config) Validate() error {
    // ... existing validation ...

    if c.Validation != nil {
        for eventName, event := range c.Events {
            if strings.HasPrefix(event.Sound, "custom:") {
                path := strings.TrimPrefix(event.Sound, "custom:")
                if err := validateSound(path, *c.Validation); err != nil {
                    return fmt.Errorf("event %s: %w", eventName, err)
                }
            }
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffprobe | External tool | Free | Part of ffmpeg, already supported |

---

## References

### Research Sources

- [ffprobe documentation](https://ffmpeg.org/ffprobe.html)
- [ffprobe JSON output format](https://ffmpeg.org/ffprobe.html#Output)

### ccbell Implementation Research

- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) - Validation pattern to extend
- [Current player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Uses ffplay as fallback

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

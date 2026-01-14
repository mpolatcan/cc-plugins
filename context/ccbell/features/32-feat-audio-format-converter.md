# Feature: Audio Format Converter

Convert sound files to supported formats.

## Summary

Built-in tool to convert user-provided sound files to formats compatible with ccbell audio players.

## Motivation

- Users have MP3/WAV files but need AIFF
- Cross-platform format compatibility
- Reduce friction in adding custom sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Conversion Tool

The current audio players support different formats:
- **afplay** (macOS): AIFF, WAV, MP3, AU
- **mpv** (Linux): All formats
- **ffplay** (Linux): All formats

**Key Finding**: ffmpeg is the universal converter.

### FFmpeg Conversion

```bash
# Convert MP3 to AIFF
ffmpeg -i input.mp3 -codec:a pcm_s16be output.aiff

# Convert WAV to AIFF
ffmpeg -i input.wav -codec:a pcm_s24be output.aiff

# Normalize volume during conversion
ffmpeg -i input.mp3 -af "volumedetect" -codec:a pcm_s16be output.aiff
```

### Implementation

```go
func convertSound(inputPath, outputPath string) error {
    cmd := exec.Command("ffmpeg", "-y",
        "-i", inputPath,
        "-codec:a", "pcm_s16be",
        outputPath,
    )
    return cmd.Run()
}
```

### Commands

```bash
# Convert a file
/ccbell:convert input.mp3 --output output.aiff

# Convert and install
/ccbell:convert input.wav --install --event stop

# List supported formats
/ccbell:convert --formats

# Convert with normalization
/ccbell:convert input.mp3 --normalize --output output.aiff
```

### Supported Conversions

| Input | Output | Converter |
|-------|--------|-----------|
| MP3 | AIFF | ffmpeg |
| WAV | AIFF | ffmpeg |
| OGG | AIFF | ffmpeg |
| FLAC | AIFF | ffmpeg |
| Any | Any | ffmpeg |

---

## Audio Player Compatibility

Converter creates files compatible with audio players:
- AIFF format for bundled sounds
- Any format for custom sounds
- Works with afplay, mpv, ffplay

---

## Implementation

### Conversion Function

```go
type ConvertOptions struct {
    Input       string
    Output      string
    Format      string
    Normalize   bool
    Install     bool
    Event       string
}

func ConvertSound(opts ConvertOptions) error {
    args := []string{"-y", "-i", opts.Input}

    if opts.Normalize {
        args = append(args, "-af", "loudnorm")
    }

    // Set output format
    if opts.Format != "" {
        args = append(args, "-f", opts.Format)
    }

    args = append(args, opts.Output)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

### Installation Integration

```go
func ConvertAndInstall(inputPath, eventType string) error {
    // Convert to AIFF
    outputPath := filepath.Join(pluginRoot, "sounds", eventType+".aiff")

    if err := ConvertSound(ConvertOptions{
        Input:  inputPath,
        Output: outputPath,
    }); err != nil {
        return err
    }

    // Update config
    cfg, _, _ := config.Load(homeDir)
    if cfg.Events[eventType] == nil {
        cfg.Events[eventType] = &config.Event{}
    }
    cfg.Events[eventType].Sound = fmt.Sprintf("bundled:%s", eventType)

    return config.Save(homeDir, cfg)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Already supported player |

---

## References

### Research Sources

- [FFmpeg audio codecs](https://ffmpeg.org/ffmpeg-codecs.html#Audio-Encoders)
- [AIFF encoding](https://ffmpeg.org/ffmpeg-all.html#aiff)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg as fallback
- [Player args](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L48-L62) - ffplay arguments

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

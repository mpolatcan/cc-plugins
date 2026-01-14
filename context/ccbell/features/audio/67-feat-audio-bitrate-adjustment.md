# Feature: Audio Bitrate Adjustment

Convert sound files to optimal bitrates.

## Summary

Adjust audio bitrate for smaller file sizes or higher quality.

## Motivation

- Reduce storage space
- Faster loading times
- Quality vs size tradeoffs

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### FFmpeg Bitrate Control

```bash
# Convert to lower bitrate (smaller files)
ffmpeg -i input.aiff -b:a 128k output.aiff

# Convert to higher bitrate (better quality)
ffmpeg -i input.aiff -b:a 320k output.aiff

# Variable bitrate
ffmpeg -i input.aiff -q:a 2 output.aiff
```

### Configuration

```json
{
  "bitrate": {
    "target_bitrate": "192k",
    "mode": "constant",  // "constant", "variable"
    "quality": 2,        // 0-9 (VBR)
    "convert_on_import": true,
    "max_size_kb": 500
  }
}
```

### Implementation

```go
type BitrateConfig struct {
    TargetBitrate string `json:"target_bitrate"`
    Mode          string `json:"mode"` // "constant", "variable"
    Quality       int    `json:"quality"`
    ConvertOnImport bool `json:"convert_on_import"`
    MaxSizeKB     int64  `json:"max_size_kb"`
}

func convertBitrate(inputPath, outputPath string, cfg *BitrateConfig) error {
    args := []string{"-y", "-i", inputPath}

    if cfg.Mode == "constant" {
        args = append(args, "-b:a", cfg.TargetBitrate)
    } else {
        args = append(args, "-q:a", fmt.Sprintf("%d", cfg.Quality))
    }

    args = append(args, outputPath)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

### Commands

```bash
/ccbell:bitrate convert input.aiff --192k
/ccbell:bitrate convert input.aiff --quality 2
/ccbell:bitrate status              # Show current settings
/ccbell:bitrate apply bundled:stop  # Convert a bundled sound
/ccbell:bitrate batch --all         # Convert all sounds
```

---

## Audio Player Compatibility

Bitrate adjustment creates new audio files:
- Uses FFmpeg for conversion
- Result plays via existing players
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Already supported |

---

## References

### Research Sources

- [FFmpeg audio options](https://ffmpeg.org/ffmpeg.html#Audio-Options)
- [FFmpeg codec options](https://ffmpeg.org/ffmpeg-codec.html#Audio-Encoders)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

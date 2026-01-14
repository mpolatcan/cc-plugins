# Feature: Audio Normalization

Normalize sound file volume to consistent levels.

## Summary

Adjust sound file volume to a target level to ensure consistent notification loudness.

## Motivation

- Some sounds are quieter than others
- Consistent notification experience
- Avoid surprises from user-provided sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### FFmpeg Normalization

```bash
# Normalize to -16 LUFS (broadcast standard)
ffmpeg -i input.aiff -af "loudnorm=I=-16:TP=-1.5:LRA=11" output.aiff

# Simple volume adjustment
ffmpeg -i input.aiff -af "volume=0.8" output.aiff

# Detect current volume
ffmpeg -i input.aiff -af "volumedetect" -f null /dev/null
```

### Implementation

```go
func normalizeSound(inputPath, outputPath string, targetLUFS float64) error {
    cmd := exec.Command("ffmpeg", "-y",
        "-i", inputPath,
        "-af", fmt.Sprintf("loudnorm=I=%.2f:TP=-1.5:LRA=11", targetLUFS),
        outputPath,
    )
    return cmd.Run()
}

func detectVolumeInfo(path string) (*VolumeInfo, error) {
    cmd := exec.Command("ffmpeg", "-i", path,
        "-af", "volumedetect",
        "-f", "null", "/dev/null")

    output, err := cmd.CombinedOutput()
    if err != nil {
        // Parse output for volume info
    }

    // Parse mean_volume and max_volume from output
}
```

### Configuration

```json
{
  "normalization": {
    "enabled": true,
    "target_lufs": -16.0,
    "normalize_on_install": true,
    "auto_normalize_existing": false
  }
}
```

### Commands

```bash
/ccbell:normalize /path/to/sound.aiff          # Normalize a file
/ccbell:normalize /path/to/sound.aiff --preview  # Preview without saving
/ccbell:normalize /path/to/sound.aiff --install  # Normalize and install
/ccbell:normalize status                        # Show normalization status
```

---

## Audio Player Compatibility

Normalization creates new audio files:
- Uses FFmpeg for processing
- Result plays via existing players
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Already supported player |

---

## References

### Research Sources

- [FFmpeg loudnorm filter](https://ffmpeg.org/ffmpeg-filters.html#loudnorm)
- [LUFS metering](https://en.wikipedia.org/wiki/LKFS)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - For playback after normalization

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

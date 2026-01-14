# Feature: Audio Echo Cancellation

Reduce audio artifacts and echo in notifications.

## Summary

Apply audio processing to reduce echo and artifacts in notification sounds.

## Motivation:

- Improve sound quality
- Reduce audio fatigue
- Better clarity in quiet environments

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Echo Cancellation

| Tool | Echo Cancellation | Platform |
|------|-------------------|----------|
| FFmpeg | ✅ Yes (filters) | macOS, Linux |
| SoX | ✅ Yes | macOS, Linux |

### FFmpeg Filters

```bash
# Remove DC offset
ffmpeg -i input.aiff -af "dcshift=0.5" output.aiff

# High-pass filter (remove low rumble)
ffmpeg -i input.aiff -af "highpass=f=200" output.aiff

# Low-pass filter (remove hiss)
ffmpeg -i input.aiff -af "lowpass=f=8000" output.aiff

# De-ess (remove sibilance)
ffmpeg -i input.aiff -af "deesser" output.aiff

# Echo cancellation (complex)
ffmpeg -i input.aiff -af "aecho=0.8:0.9:1000:0.3" output.aiff
```

### Configuration

```json
{
  "echo_cancellation": {
    "enabled": true,
    "highpass_hz": 200,
    "lowpass_hz": 8000,
    "normalize": true,
    "dc_offset": false
  }
}
```

### Commands

```bash
/ccbell:echo apply input.aiff --output output.aiff
/ccbell:echo clean bundled:stop --install
/ccbell:echo settings              # Show current settings
/ccbell:echo preview before after  # Compare before/after
```

### Processing Pipeline

```go
func processWithEchoCancellation(inputPath, outputPath string, cfg *EchoConfig) error {
    filters := []string{}

    if cfg.HighpassHz > 0 {
        filters = append(filters, fmt.Sprintf("highpass=f=%d", cfg.HighpassHz))
    }
    if cfg.LowpassHz > 0 {
        filters = append(filters, fmt.Sprintf("lowpass=f=%d", cfg.LowpassHz))
    }
    if cfg.Normalize {
        filters = append(filters, "loudnorm=I=-16:TP=-1.5:LRA=11")
    }
    if cfg.DCOffset {
        filters = append(filters, "dcshift=0.1")
    }

    filterStr := strings.Join(filters, ",")

    args := []string{"-y", "-i", inputPath}
    if filterStr != "" {
        args = append(args, "-af", filterStr)
    }
    args = append(args, outputPath)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

---

## Audio Player Compatibility

Echo cancellation preprocesses audio:
- Creates new audio files
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

- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html)
- [FFmpeg highpass/lowpass](https://ffmpeg.org/ffmpeg-filters.html#highpass)
- [DC offset correction](https://wiki.hydrogenaud.io/index.php?title=DC_offset)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Audio processing](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Audio handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

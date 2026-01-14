# Feature: Sound Frequency Optimization

Optimize sounds for better playback on different systems.

## Summary

Adjust sound characteristics for optimal playback on various audio configurations.

## Motivation:

- Better playback on all systems
- Optimize for Bluetooth speakers
- Improve clarity on low-quality audio

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Optimization Types

| Optimization | Description | Use Case |
|--------------|-------------|----------|
| Bass boost | Enhance low frequencies | Small speakers |
| Treble boost | Enhance high frequencies | Voice clarity |
| Dynamic range | Compress dynamic range | Low volume playback |
| Mono downmix | Convert to mono | Single speaker |
| High-pass | Remove sub-bass | Save bandwidth |
| Loudness EQ | Match loudness standards | Consistent volume |

### FFmpeg Implementation

```bash
# Bass boost
ffmpeg -i input.aiff -af "bass=g=6" output.aiff

# Treble boost
ffmpeg -i input.aiff -af "treble=g=3" output.aiff

# Dynamic range compression
ffmpeg -i input.aiff -af "acompressor=threshold=-20" output.aiff

# Mono downmix
ffmpeg -i input.aiff -ac 1 output.aiff

# High-pass filter (remove sub-bass)
ffmpeg -i input.aiff -af "highpass=f=40" output.aiff

# Combined optimization
ffmpeg -i input.aiff -af "bass=g=3,highpass=f=40,loudnorm" output.aiff
```

### Configuration

```json
{
  "optimization": {
    "enabled": true,
    "preset": "auto",
    "presets": {
      "bluetooth": {
        "bass_boost": 4,
        "treble_boost": 2,
        "highpass": true
      },
      "voice": {
        "treble_boost": 3,
        "highpass": true,
        "compress": true
      },
      "speaker": {
        "bass_boost": 2,
        "mono_downmix": false
      },
      "headphone": {
        "bass_boost": 6,
        "stereo_enhance": true
      }
    }
  }
}
```

### Commands

```bash
/ccbell:optimize apply bundled:stop --preset bluetooth
/ccbell:optimize apply custom:sound.aiff --bass 4 --treble 2
/ccbell:optimize preview bundled:stop --preset bluetooth
/ccbell:optimize reset bundled:stop  # Remove optimizations
/ccbell:optimize list                # List available presets
```

### Optimization Preview

```
$ ccbell:optimize preview bundled:stop --preset bluetooth

=== Optimization Preview ===

Sound: bundled:stop
Preset: Bluetooth

Applied filters:
  - bass=g=4 (Bass boost +4dB)
  - highpass=f=40 (Remove sub-bass)

Original spectrum:
                    ██████
Optimized spectrum:
                    ████████

[Preview sound] [Apply] [Cancel]
```

---

## Audio Player Compatibility

Optimization creates new audio files:
- Uses FFmpeg for processing
- Result plays via existing players
- No player changes required

---

## Implementation

### Preset Application

```go
func applyOptimizationPreset(inputPath, outputPath string, preset string) error {
    presetCfg := optimizationConfig.Presets[preset]
    filters := []string{}

    if presetCfg.BassBoost > 0 {
        filters = append(filters, fmt.Sprintf("bass=g=%d", presetCfg.BassBoost))
    }
    if presetCfg.TrebleBoost > 0 {
        filters = append(filters, fmt.Sprintf("treble=g=%d", presetCfg.TrebleBoost))
    }
    if presetCfg.Highpass {
        filters = append(filters, "highpass=f=40")
    }
    if presetCfg.Compress {
        filters = append(filters, "acompressor=threshold=-20")
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

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Already supported |

---

## References

### Research Sources

- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html)
- [FFmpeg bass/treble](https://ffmpeg.org/ffmpeg-filters.html#bass)
- [Audio optimization guide](https://www.soundonsound.com/techniques/audio-optimisation)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Optimization config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

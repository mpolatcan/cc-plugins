# Feature: Crossfade Sounds

Smooth transitions between notification sounds.

## Summary

Crossfade between multiple sounds for seamless audio transitions.

## Motivation:

- Smoother audio experience
- No hard cuts between sounds
- Professional audio feel

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Crossfade Implementation

```bash
# FFmpeg crossfade two audio files
ffmpeg -i sound1.aiff -i sound2.aiff -filter_complex \
  "[0:a][1:a]acrossfade=d=0.5" output.aiff
```

### Configuration

```json
{
  "crossfade": {
    "enabled": true,
    "duration_ms": 500,
    "preset": "linear"  // "linear", "equal_power", "logarithmic"
  }
}
```

### Implementation

```go
type CrossfadeConfig struct {
    Enabled   bool   `json:"enabled"`
    Duration  string `json:"duration"` // Parseable duration
    Preset    string `json:"preset"`   // "linear", "equal_power"
}

func crossfadeSounds(sound1, sound2, output string, cfg *CrossfadeConfig) error {
    duration := parseDuration(cfg.Duration)

    args := []string{"-y", "-i", sound1, "-i", sound2}

    filter := fmt.Sprintf("[0:a][1:a]acrossfade=d=%.3f", duration.Seconds())
    if cfg.Preset == "equal_power" {
        filter += ":c=1" // Equal power curve
    }

    args = append(args, "-filter_complex", filter, output)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

### Use Cases

```go
// Crossfade for sound chains
func (c *CCBell) playWithCrossfade(sounds []string, volume float64) error {
    if len(sounds) < 2 {
        return c.player.Play(sounds[0], volume)
    }

    // Crossfade first two
    tempFile := filepath.Join(c.cacheDir, "crossfade", randomName()+".aiff")
    crossfadeSounds(sounds[0], sounds[1], tempFile, c.crossfadeConfig)

    // Crossfade remaining
    for i := 2; i < len(sounds); i++ {
        nextFile := filepath.Join(c.cacheDir, "crossfade", randomName()+".aiff")
        crossfadeSounds(tempFile, sounds[i], nextFile, c.crossfadeConfig)
        os.Remove(tempFile)
        tempFile = nextFile
    }

    // Play result
    defer os.Remove(tempFile)
    return c.player.Play(tempFile, volume)
}
```

### Commands

```bash
/ccbell:crossfade test sound1.aiff sound2.aiff
/ccbell:crossfade set 500ms
/ccbell:crossfade set --preset equal_power
/ccbell:crossfade apply sound1.aiff sound2.aiff --output merged.aiff
```

---

## Audio Player Compatibility

Crossfade creates new audio files:
- Uses FFmpeg for processing
- Result plays via existing players
- No player changes required

---

## Implementation

### Crossfade Options

```go
func getCrossfadeFilter(duration time.Duration, preset string) string {
    switch preset {
    case "equal_power":
        return fmt.Sprintf("[0:a][1:a]acrossfade=d=%.3f:c=1", duration.Seconds())
    case "logarithmic":
        return fmt.Sprintf("[0:a][1:a]acrossfade=d=%.3f:c=0", duration.Seconds())
    default: // linear
        return fmt.Sprintf("[0:a][1:a]acrossfade=d=%.3f", duration.Seconds())
    }
}
```

### Cache Management

```go
func (c *CCBell) cleanupCrossfadeCache() {
    // Remove old crossfade files
    // Keep cache size reasonable
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

- [FFmpeg acrossfade](https://ffmpeg.org/ffmpeg-filters.html#acrossfade)
- [Crossfade curves](https://dsp.stackexchange.com/questions/21838/crossfade-curves)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Cache handling](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Temp file handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

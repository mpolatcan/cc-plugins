# Feature: Sound Mixing

Mix multiple sounds into a single notification.

## Summary

Combine multiple sound files into a single audio output for richer notifications.

## Motivation

- Create unique notification signatures
- Layer sounds for emphasis
- Support "sound layering" patterns

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Mixing Tools

| Tool | Mixing Support | Platform |
|------|----------------|----------|
| FFmpeg | ✅ Excellent | macOS, Linux |
| SoX | ✅ Excellent | macOS, Linux |
| afplay/mpv | ⚠️ Limited | Native only |

**Key Finding**: FFmpeg can mix multiple audio files.

### FFmpeg Mixing

```bash
# Overlay two sounds
ffmpeg -i sound1.aiff -i sound2.aiff -filter_complex amix=inputs=2:duration=longest output.aiff

# Add sounds sequentially
ffmpeg -i sound1.aiff -i sound2.aiff -filter_complex [0:a][1:a]concat=n=2:v=0:a=1 output.aiff

# Mix with volume adjustment
ffmpeg -i base.aiff -i overlay.aiff -filter_complex [0:a][1:a]amix=inputs=2:duration=longest:weights='1 0.5' output.aiff
```

### Implementation

```go
func mixSounds(inputs []string, output string, weights []float64) error {
    filter := buildMixFilter(inputs, weights)

    args := []string{"-y"}
    for _, input := range inputs {
        args = append(args, "-i", input)
    }
    args = append(args, "-filter_complex", filter, output)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}

func buildMixFilter(inputs []string, weights []float64) string {
    if len(weights) == 0 {
        weights = make([]float64, len(inputs))
        for i := range weights {
            weights[i] = 1.0
        }
    }

    weightStr := make([]string, len(weights))
    for i, w := range weights {
        weightStr[i] = fmt.Sprintf("%.2f", w)
    }

    return fmt.Sprintf("amix=inputs=%d:duration=longest:weights='%s'",
        len(inputs), strings.Join(weightStr, " "))
}
```

### Configuration

```json
{
  "events": {
    "permission_prompt": {
      "sound_mix": [
        "bundled:ding",
        "bundled:voice"
      ],
      "mix_weights": [0.7, 0.3]
    }
  }
}
```

### Commands

```bash
/ccbell:mix create out.aiff in1.aiff in2.aiff --weights 0.7 0.3
/ccbell:mix preview ding+voice
/ccbell:mix install permission_prompt --sounds ding,voice
```

---

## Audio Player Compatibility

Sound mixing creates new audio files:
- Uses FFmpeg for mixing
- Result plays via existing players
- No player changes required

---

## Implementation

### Mixing Workflow

```go
func (c *CCBell) playMixedSound(mixSpec *SoundMix, volume float64) error {
    // Create temp file for mixed output
    tempFile := filepath.Join(c.cacheDir, "mix", randomName()+".aiff")

    // Mix sounds
    if err := mixSounds(mixSpec.Sounds, tempFile, mixSpec.Weights); err != nil {
        return fmt.Errorf("mix failed: %w", err)
    }
    defer os.Remove(tempFile)

    // Play mixed sound
    return c.player.Play(tempFile, volume)
}
```

### Caching

```go
// Cache mixed sounds to avoid re-mixing
func getMixedSoundCacheKey(sounds []string, weights []float64) string {
    key := strings.Join(sounds, ":") + ":" + fmt.Sprintf("%v", weights)
    return fmt.Sprintf("mix_%x", sha256.Sum256([]byte(key)))
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

- [FFmpeg amix filter](https://ffmpeg.org/ffmpeg-filters.html#amix)
- [FFmpeg concat filter](https://ffmpeg.org/ffmpeg-filters.html#concat)
- [SoX mix](http://sox.sourceforge.net/sox.html)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - For mixing input

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

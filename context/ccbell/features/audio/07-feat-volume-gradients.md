# Feature: Volume Gradients

Fade in/out for less jarring audio playback.

## Summary

Smooth volume transitions instead of abrupt starts/stops. Configurable ramp duration per event.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Current Audio Player Analysis

The current `internal/audio/player.go` uses native players:
- **macOS**: `afplay -v <volume> <file>`
- **Linux**: `mpv --volume=<percent>`, `ffplay -volume=<percent>`

**Key Finding**: None of the native players support fade in/out. Options:

| Approach | Platform | Quality | Dependencies |
|----------|----------|---------|--------------|
| SoX `play` | Cross-platform | Excellent | sox (external) |
| FFmpeg filter | Cross-platform | Excellent | ffmpeg |
| Go processing | Cross-platform | Good | go-audio libraries |

### Implementation with FFmpeg

```bash
# Fade in 100ms, fade out 200ms
ffplay -nodisp -autoexit -af "afade=tin:0.1:0,afade=tout:0.2:0.5" -volume 50 sound.aiff
```

### Go Implementation with Oto

```go
func (p *Player) PlayWithFade(path string, fadeIn, fadeOut time.Duration) error {
    data, err := LoadAudio(path)
    if err != nil {
        return err
    }

    // Apply fade in
    for i := 0; i < int(fadeIn.SampleRate()); i++ {
        ratio := float64(i) / float64(fadeIn.SampleRate())
        data.Samples[i] = float64(data.Samples[i]) * ratio
    }

    // Apply fade out
    for i := len(data.Samples) - int(fadeOut.SampleRate()); i < len(data.Samples); i++ {
        ratio := float64(len(data.Samples)-i) / float64(fadeOut.SampleRate())
        data.Samples[i] = float64(data.Samples[i]) * ratio
    }

    return p.player.Play(data)
}
```

## Configuration

```json
{
  "events": {
    "stop": {
      "volume": 0.5,
      "fade_in": "100ms",
      "fade_out": "200ms"
    },
    "permission_prompt": {
      "volume": 0.7,
      "fade_in": "50ms",
      "fade_out": "100ms"
    }
  }
}
```

## Commands

```bash
/ccbell:test stop --fade
/ccbell:configure stop fade-in 100ms fade-out 200ms
```

---

## Feasibility Research

### Audio Player Compatibility

Volume gradients require changing the audio player implementation:
- Current: Non-blocking `cmd.Start()`
- Required: Audio decoding + processing + playback

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| FFmpeg | External tool | Free | Already supported player |
| go-audio/wav | Go library | Free | WAV processing |
| ebitengine/oto | Go library | Free | Audio playback |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | FFmpeg or Go library |
| Linux | ✅ Supported | FFmpeg or Go library |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Recommended Approach

Use FFmpeg as it's already supported as a fallback player:

```go
func (p *Player) playWithFadeFFmpeg(path string, volume float64, fadeIn, fadeOut time.Duration) error {
    volPercent := int(volume * 100)
    fadeInSec := fadeIn.Seconds()
    fadeOutSec := fadeOut.Seconds()

    args := []string{
        "-nodisp", "-autoexit",
        "-af", fmt.Sprintf("afade=tin:%.3f:0,afade=tout:%.3f", fadeInSec, fadeOutSec),
        "-volume", fmt.Sprintf("%d", volPercent),
        path,
    }

    cmd := exec.Command("ffplay", args...)
    return cmd.Start()
}
```

### Format Support

| Format | FFmpeg | Go Library |
|--------|--------|------------|
| AIFF | ✅ | ❌ |
| WAV | ✅ | ✅ |
| MP3 | ✅ | ✅ |
| Other | ✅ | ❌ |

---

## References

### Research Sources

- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html#afade)
- [go-audio library](https://github.com/go-audio/audio)
- [ebitengine/oto](https://github.com/ebitengine/oto) - Go audio playback library

### ccbell Implementation Research

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Shows ffplay is already a supported fallback player
- [Player args](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L76-L91) - ffplay arguments pattern for adding fade filters
- [Volume handling](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Current volume range 0.0-1.0

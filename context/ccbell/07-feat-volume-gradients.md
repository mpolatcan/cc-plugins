# Feature: Volume Gradients

Fade in/out for less jarring audio playback.

## Summary

Smooth volume transitions instead of abrupt starts/stops. Configurable ramp duration per event.

## Technical Feasibility

### Implementation Approaches

| Approach | Platform | Quality |
|----------|----------|---------|
| SoX play | Cross-platform | Excellent |
| ffmpeg | Cross-platform | Excellent |
| Go libraries | Platform-specific | Good |
| Native players | macOS/Linux | Varies |

### SoX Fade

```bash
# Fade in 100ms, fade out 200ms
play sound.aiff fade t 0.1 0 0.2
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
